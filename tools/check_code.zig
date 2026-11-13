//! 源码静态检查（M0 第一批：AC-ARCH-001、AC-PLAT-018、AC-CONV-001 至 AC-CONV-030 中可静态判定的部分）。
//!
//! 用法：`check_code [--zig <zig 可执行文件>]`，在仓库根目录运行（`zig build check-code`）。
//! 每条扫描都是纯函数：输入文件路径与内容（`File`），输出违规列表（`Report`），
//! 因此既能对真实仓库运行，也能对植入缺陷的小样本运行，证明扫描能抓到违规。
//! 任一违规即以非零码退出；规则严格按 docs/ 的条款，不设白名单（文档明确允许的排除项除外）。
//!
//! 文档没有规定、本脚本为可执行而补充的约定（均在对应扫描处注明）：
//!   - 绑定文件的判定：`src/<模块>/` 下文件名为 `bindings.zig` 或以 `_bindings.zig` 结尾。
//!   - THIRD_PARTY_NOTICES.md 与 PATCHES.md 的条目字段格式（见各扫描的注释）。

const std = @import("std");
const build_options = @import("build_options");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

// ---------------------------------------------------------------------------
// 基础类型
// ---------------------------------------------------------------------------

pub const File = struct {
    /// 仓库根相对路径，使用 '/' 分隔。
    path: []const u8,
    text: []const u8 = "",
};

pub const Violation = struct {
    path: []const u8,
    line: usize,
    msg: []const u8,
};

pub const Report = struct {
    a: Allocator,
    items: List(Violation) = .empty,

    pub fn add(self: *Report, path: []const u8, line: usize, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.a, fmt, args) catch @panic("oom");
        self.items.append(self.a, .{ .path = path, .line = line, .msg = msg }) catch @panic("oom");
    }
};

pub const Commit = struct {
    hash: []const u8,
    subject: []const u8,
    body: []const u8,
    files: []const []const u8,
};

// ---------------------------------------------------------------------------
// 文本工具
// ---------------------------------------------------------------------------

fn isIdent(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn startsWith(s: []const u8, p: []const u8) bool {
    return std.mem.startsWith(u8, s, p);
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn contains(s: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, s, needle) != null;
}

/// 在 hay 中查找整词 word（前后不是标识符字符）。
fn wordIndex(hay: []const u8, word: []const u8, from: usize) ?usize {
    var pos = from;
    while (std.mem.indexOfPos(u8, hay, pos, word)) |at| {
        const before_ok = at == 0 or !isIdent(hay[at - 1]);
        const end = at + word.len;
        const after_ok = end >= hay.len or !isIdent(hay[end]);
        if (before_ok and after_ok) return at;
        pos = at + 1;
    }
    return null;
}

fn hasWord(hay: []const u8, word: []const u8) bool {
    return wordIndex(hay, word, 0) != null;
}

fn splitLines(a: Allocator, text: []const u8) ![][]const u8 {
    var out: List([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |l| try out.append(a, std.mem.trimEnd(u8, l, "\r"));
    return out.items;
}

fn isSnake(s: []const u8) bool {
    if (s.len == 0 or !std.ascii.isLower(s[0])) return false;
    for (s) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '_')) return false;
    return true;
}

fn isCamel(s: []const u8) bool {
    if (s.len == 0 or !std.ascii.isLower(s[0])) return false;
    for (s) |c| if (!std.ascii.isAlphanumeric(c)) return false;
    return true;
}

fn isPascal(s: []const u8) bool {
    if (s.len == 0 or !std.ascii.isUpper(s[0])) return false;
    for (s) |c| if (!std.ascii.isAlphanumeric(c)) return false;
    return true;
}

fn isUpperSnake(s: []const u8) bool {
    if (s.len == 0 or !std.ascii.isUpper(s[0])) return false;
    for (s) |c| if (!(std.ascii.isUpper(c) or std.ascii.isDigit(c) or c == '_')) return false;
    return true;
}

/// 含汉字（U+3400-4DBF、U+4E00-9FFF）。
fn hasHan(s: []const u8) bool {
    var i: usize = 0;
    while (i + 2 < s.len) : (i += 1) {
        const b = s[i];
        if (b >= 0xE3 and b <= 0xE9 and (s[i + 1] & 0xC0) == 0x80 and (s[i + 2] & 0xC0) == 0x80) {
            const cp: u32 = (@as(u32, b & 0x0F) << 12) | (@as(u32, s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F);
            if ((cp >= 0x3400 and cp <= 0x4DBF) or (cp >= 0x4E00 and cp <= 0x9FFF)) return true;
        }
    }
    return false;
}

fn hasLetterOrDigit(s: []const u8) bool {
    for (s) |c| if (std.ascii.isAlphanumeric(c) or c >= 0x80) return true;
    return false;
}

fn extOf(path: []const u8) []const u8 {
    const base = std.fs.path.basenamePosix(path);
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return "";
    return base[dot..];
}

/// 解析相对路径（含 `..`），结果为仓库根相对路径。
fn joinNorm(a: Allocator, dir: []const u8, rel: []const u8) ![]const u8 {
    var parts: List([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, dir, '/');
    while (it.next()) |p| if (p.len > 0) try parts.append(a, p);
    var rit = std.mem.splitScalar(u8, rel, '/');
    while (rit.next()) |p| {
        if (p.len == 0 or std.mem.eql(u8, p, ".")) continue;
        if (std.mem.eql(u8, p, "..")) {
            if (parts.items.len > 0) _ = parts.pop();
            continue;
        }
        try parts.append(a, p);
    }
    return std.mem.join(a, "/", parts.items);
}

// ---------------------------------------------------------------------------
// 词法：逐行拆出代码与注释
// ---------------------------------------------------------------------------

const Lexed = struct {
    /// 去掉注释、字符串内容保留；多行字符串行记为 `""`。
    raw: []const u8,
    /// 在 raw 基础上把字符串与字符字面量的内容替换为空格（长度不变）。
    code: []const u8,
    /// `//` 起至行尾（含 `//`），无注释为 null。
    comment: ?[]const u8,
};

fn lexLine(a: Allocator, line: []const u8) !Lexed {
    const t = std.mem.trimStart(u8, line, " \t");
    if (startsWith(t, "\\\\")) return .{ .raw = "\"\"", .code = "\"\"", .comment = null };
    var raw: List(u8) = .empty;
    var code: List(u8) = .empty;
    var comment: ?[]const u8 = null;
    var i: usize = 0;
    while (i < line.len) {
        const c = line[i];
        if (c == '"') {
            var j = i + 1;
            while (j < line.len and line[j] != '"') : (j += 1) {
                if (line[j] == '\\' and j + 1 < line.len) j += 1;
            }
            const end = @min(j + 1, line.len);
            try raw.appendSlice(a, line[i..end]);
            try code.append(a, '"');
            var k = i + 1;
            while (k < end) : (k += 1) {
                if (k == j and line[k] == '"') {
                    try code.append(a, '"');
                } else try code.append(a, ' ');
            }
            i = end;
            continue;
        }
        if (c == '\'') {
            var j = i + 1;
            if (j < line.len and line[j] == '\\') j += 1;
            j += 1;
            while (j < line.len and line[j] != '\'') : (j += 1) {}
            if (j < line.len and j - i <= 12) {
                try raw.appendSlice(a, line[i .. j + 1]);
                try code.append(a, '\'');
                var k = i + 1;
                while (k < j) : (k += 1) try code.append(a, ' ');
                try code.append(a, '\'');
                i = j + 1;
                continue;
            }
        }
        if (c == '/' and i + 1 < line.len and line[i + 1] == '/') {
            comment = line[i..];
            break;
        }
        try raw.append(a, c);
        try code.append(a, c);
        i += 1;
    }
    return .{ .raw = raw.items, .code = code.items, .comment = comment };
}

// ---------------------------------------------------------------------------
// 声明解析（容器级声明、函数签名、枚举成员）
// ---------------------------------------------------------------------------

const FrameKind = enum { file, container, enum_c, union_c, block };

const DeclKind = enum { fn_decl, var_decl, const_decl, enum_member };

const Decl = struct {
    kind: DeclKind,
    name: []const u8,
    line: usize,
    is_pub: bool,
    frame_kind: FrameKind,
    /// 所在容器链是否整体公开（顶层为公开）。
    frame_pub: bool,
    /// const/var 的 `=` 之后文本；fn 为空。
    rhs: []const u8 = "",
    /// 整条声明头（到 `{` 或 `;` 之前）。
    sig: []const u8 = "",
    has_body: bool = false,
    is_extern: bool = false,
    is_threadlocal: bool = false,
    /// const 的右侧是 struct/union/enum/opaque/error 声明。
    is_type_decl: bool = false,
};

const Frame = struct {
    kind: FrameKind,
    is_pub: bool,
    paren: u32 = 0,
    in_paren: bool = false,
    pending: List(u8) = .empty,
    pending_line: usize = 0,
};

const Why = enum { open, close, semicolon, comma };

fn skipWordPrefix(rest: *[]const u8, word: []const u8) bool {
    const r = rest.*;
    if (startsWith(r, word) and (r.len == word.len or !isIdent(r[word.len]))) {
        rest.* = std.mem.trimStart(u8, r[word.len..], " \t");
        return true;
    }
    return false;
}

fn identAt(s: []const u8) []const u8 {
    if (startsWith(s, "@\"")) {
        const end = std.mem.indexOfScalarPos(u8, s, 2, '"') orelse return s;
        return s[0 .. end + 1];
    }
    var n: usize = 0;
    while (n < s.len and isIdent(s[n])) n += 1;
    return s[0..n];
}

/// 把 `(...)` 之类的尾部括号组剥掉，用于判断 `{` 前是 struct/enum/union 等。
fn classifyOpen(pending: []const u8) FrameKind {
    var p = trim(pending);
    while (p.len > 0 and p[p.len - 1] == ')') {
        var depth: usize = 0;
        var i = p.len;
        while (i > 0) {
            i -= 1;
            if (p[i] == ')') depth += 1;
            if (p[i] == '(') {
                depth -= 1;
                if (depth == 0) break;
            }
        }
        p = trim(p[0..i]);
    }
    const kinds = [_]struct { w: []const u8, k: FrameKind }{
        .{ .w = "struct", .k = .container },
        .{ .w = "opaque", .k = .container },
        .{ .w = "enum", .k = .enum_c },
        .{ .w = "union", .k = .union_c },
        .{ .w = "error", .k = .container },
    };
    for (kinds) |k| {
        if (std.mem.endsWith(u8, p, k.w) and (p.len == k.w.len or !isIdent(p[p.len - k.w.len - 1]))) return k.k;
    }
    return .block;
}

fn rhsIsTypeDecl(rhs_in: []const u8) bool {
    var r = trim(rhs_in);
    while (skipWordPrefix(&r, "packed") or skipWordPrefix(&r, "extern")) {}
    inline for (.{ "struct", "union", "enum", "opaque", "error" }) |w| {
        if (startsWith(r, w) and (r.len == w.len or !isIdent(r[w.len]))) return true;
    }
    return false;
}

fn finalize(a: Allocator, frame: *Frame, why: Why, out: *List(Decl)) !void {
    defer frame.pending.clearRetainingCapacity();
    const p = trim(frame.pending.items);
    if (p.len == 0) return;
    var rest = p;
    var is_pub = false;
    var is_extern = false;
    var thread = false;
    while (true) {
        if (skipWordPrefix(&rest, "pub")) {
            is_pub = true;
        } else if (skipWordPrefix(&rest, "extern")) {
            is_extern = true;
            if (startsWith(rest, "\"")) {
                const end = std.mem.indexOfScalarPos(u8, rest, 1, '"') orelse rest.len - 1;
                rest = std.mem.trimStart(u8, rest[end + 1 ..], " \t");
            }
        } else if (skipWordPrefix(&rest, "threadlocal")) {
            thread = true;
        } else if (skipWordPrefix(&rest, "export") or skipWordPrefix(&rest, "inline") or skipWordPrefix(&rest, "noinline")) {} else break;
    }
    const in_container = frame.kind != .block;
    var decl: Decl = .{
        .kind = .fn_decl,
        .name = "",
        .line = frame.pending_line,
        .is_pub = is_pub,
        .frame_kind = frame.kind,
        .frame_pub = frame.is_pub,
        .sig = try a.dupe(u8, p),
        .has_body = why == .open,
        .is_extern = is_extern,
        .is_threadlocal = thread,
    };
    if (skipWordPrefix(&rest, "fn")) {
        if (!in_container) return;
        decl.kind = .fn_decl;
        decl.name = try a.dupe(u8, identAt(rest));
        if (decl.name.len == 0) return;
        try out.append(a, decl);
        return;
    }
    const is_const = skipWordPrefix(&rest, "const");
    const is_var = !is_const and skipWordPrefix(&rest, "var");
    if (is_const or is_var) {
        decl.kind = if (is_const) .const_decl else .var_decl;
        decl.name = try a.dupe(u8, identAt(rest));
        if (decl.name.len == 0) return;
        const after = rest[identAt(rest).len..];
        if (std.mem.indexOfScalar(u8, after, '=')) |eq| {
            decl.rhs = try a.dupe(u8, trim(after[eq + 1 ..]));
        }
        decl.is_type_decl = is_const and rhsIsTypeDecl(decl.rhs);
        if (!in_container and !decl.is_type_decl) return;
        try out.append(a, decl);
        return;
    }
    if (frame.kind == .enum_c and (why == .comma or why == .close)) {
        const kw = [_][]const u8{ "test", "comptime", "usingnamespace" };
        for (kw) |k| if (startsWith(rest, k) and (rest.len == k.len or !isIdent(rest[k.len]))) return;
        const name = identAt(rest);
        if (name.len == 0 or std.mem.eql(u8, name, "_")) return;
        decl.kind = .enum_member;
        decl.name = try a.dupe(u8, name);
        try out.append(a, decl);
    }
}

fn pushChar(frame: *Frame, a: Allocator, c: u8, line_no: usize) !void {
    if (frame.pending.items.len == 0) {
        if (c == ' ' or c == '\t') return;
        frame.pending_line = line_no;
    }
    try frame.pending.append(a, c);
}

fn parseDecls(a: Allocator, lex: []const Lexed) ![]Decl {
    var frames: List(Frame) = .empty;
    try frames.append(a, .{ .kind = .file, .is_pub = true });
    var out: List(Decl) = .empty;
    for (lex, 0..) |lx, li| {
        const line_no = li + 1;
        const raw = lx.raw;
        var i: usize = 0;
        while (i < raw.len) {
            const c = raw[i];
            const top = &frames.items[frames.items.len - 1];
            if (c == '"' or c == '\'') {
                var j = i + 1;
                while (j < raw.len and raw[j] != c) : (j += 1) {
                    if (raw[j] == '\\' and j + 1 < raw.len) j += 1;
                }
                const end = @min(j + 1, raw.len);
                for (raw[i..end]) |ch| try pushChar(top, a, ch, line_no);
                i = end;
                continue;
            }
            switch (c) {
                '(', '[' => {
                    top.paren += 1;
                    try pushChar(top, a, c, line_no);
                },
                ')', ']' => {
                    if (top.paren > 0) top.paren -= 1;
                    try pushChar(top, a, c, line_no);
                },
                '{' => {
                    if (top.paren > 0) {
                        try pushChar(top, a, '{', line_no);
                        try frames.append(a, .{ .kind = .block, .is_pub = false, .in_paren = true });
                    } else {
                        const kind = classifyOpen(top.pending.items);
                        const pub_start = startsWith(trim(top.pending.items), "pub ");
                        const new_pub = if (top.kind == .block) top.is_pub else (top.is_pub and pub_start);
                        try finalize(a, top, .open, &out);
                        try frames.append(a, .{ .kind = kind, .is_pub = new_pub });
                    }
                },
                '}' => {
                    if (frames.items.len > 1) {
                        try finalize(a, top, .close, &out);
                        const popped = frames.pop().?;
                        if (popped.in_paren) {
                            const parent = &frames.items[frames.items.len - 1];
                            try pushChar(parent, a, '}', line_no);
                        }
                    }
                },
                ';' => if (top.paren == 0) try finalize(a, top, .semicolon, &out) else try pushChar(top, a, c, line_no),
                ',' => if (top.paren == 0) try finalize(a, top, .comma, &out) else try pushChar(top, a, c, line_no),
                else => try pushChar(top, a, c, line_no),
            }
            i += 1;
        }
        const top = &frames.items[frames.items.len - 1];
        if (top.pending.items.len > 0) try top.pending.append(a, ' ');
    }
    return out.items;
}

const Param = struct { name: []const u8, ty: []const u8 };
const Sig = struct { params: []const Param, ret: []const u8 };

fn parseSig(a: Allocator, sig: []const u8) !?Sig {
    const fn_at = wordIndex(sig, "fn", 0) orelse return null;
    const open = std.mem.indexOfScalarPos(u8, sig, fn_at, '(') orelse return null;
    var depth: usize = 0;
    var close: usize = open;
    for (sig[open..], open..) |ch, idx| {
        if (ch == '(' or ch == '[' or ch == '{') depth += 1;
        if (ch == ')' or ch == ']' or ch == '}') {
            depth -= 1;
            if (depth == 0) {
                close = idx;
                break;
            }
        }
    }
    const inner = sig[open + 1 .. close];
    var params: List(Param) = .empty;
    var start: usize = 0;
    var d: usize = 0;
    var idx: usize = 0;
    while (idx <= inner.len) : (idx += 1) {
        const at_end = idx == inner.len;
        if (!at_end) {
            const ch = inner[idx];
            if (ch == '(' or ch == '[' or ch == '{') d += 1;
            if (ch == ')' or ch == ']' or ch == '}') d -|= 1;
        }
        if (at_end or (inner[idx] == ',' and d == 0)) {
            var seg = trim(inner[start..idx]);
            start = idx + 1;
            if (seg.len == 0) continue;
            while (skipWordPrefix(&seg, "comptime") or skipWordPrefix(&seg, "noalias")) {}
            const colon = std.mem.indexOfScalar(u8, seg, ':') orelse continue;
            try params.append(a, .{ .name = trim(seg[0..colon]), .ty = trim(seg[colon + 1 ..]) });
        }
    }
    var ret = trim(sig[close + 1 ..]);
    while (true) {
        var progressed = false;
        inline for (.{ "callconv", "align", "linksection", "addrspace" }) |w| {
            if (startsWith(ret, w) and ret.len > w.len and ret[w.len] == '(') {
                var dd: usize = 0;
                var e: usize = w.len;
                while (e < ret.len) : (e += 1) {
                    if (ret[e] == '(') dd += 1;
                    if (ret[e] == ')') {
                        dd -= 1;
                        if (dd == 0) break;
                    }
                }
                ret = trim(ret[@min(e + 1, ret.len)..]);
                progressed = true;
            }
        }
        if (!progressed) break;
    }
    return .{ .params = params.items, .ret = ret };
}

fn isPtrOrSlice(ty: []const u8) bool {
    const t = trim(ty);
    const prefixes = [_][]const u8{ "*", "[]", "[*", "?*", "?[]", "?[*" };
    for (prefixes) |p| if (startsWith(t, p)) return true;
    return false;
}

/// 取 decl 之上连续的 `///` 文档注释，拼接为一段文本。
fn docAbove(a: Allocator, lines: []const []const u8, line: usize) ![]const u8 {
    var collected: List([]const u8) = .empty;
    var i: usize = line -| 1; // 声明所在行的 0 基下标为 line-1，上一行为 line-2
    while (i > 0) {
        i -= 1;
        const t = std.mem.trimStart(u8, lines[i], " \t");
        if (!startsWith(t, "///")) break;
        try collected.append(a, t);
    }
    std.mem.reverse([]const u8, collected.items);
    return std.mem.join(a, "\n", collected.items);
}

const Parsed = struct {
    file: File,
    lines: []const []const u8,
    lex: []const Lexed,
    decls: []const Decl,
};

fn parseFile(a: Allocator, f: File) !Parsed {
    const lines = try splitLines(a, f.text);
    const lex = try a.alloc(Lexed, lines.len);
    for (lines, 0..) |l, i| lex[i] = try lexLine(a, l);
    return .{ .file = f, .lines = lines, .lex = lex, .decls = try parseDecls(a, lex) };
}

fn isZig(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".zig");
}

fn inDir(path: []const u8, dir: []const u8) bool {
    return startsWith(path, dir) and path.len > dir.len and path[dir.len] == '/';
}

// ---------------------------------------------------------------------------
// 模块表与依赖（docs/02 的 3.1 节、REQ-ARCH-001/006）
// ---------------------------------------------------------------------------

const Mod = struct { name: []const u8, level: u8, order: u8 };

/// 层级自下而上：core(0) < platform(1) < gfx、text(2) < theme、layout、input、ui(3) < widgets、app(4)；
/// 同层按 order 递增，只能由后者依赖前者（REQ-ARCH-001）。
const modules = [_]Mod{
    .{ .name = "core", .level = 0, .order = 0 },
    .{ .name = "platform", .level = 1, .order = 0 },
    .{ .name = "gfx", .level = 2, .order = 0 },
    .{ .name = "text", .level = 2, .order = 1 },
    .{ .name = "theme", .level = 3, .order = 0 },
    .{ .name = "layout", .level = 3, .order = 1 },
    .{ .name = "input", .level = 3, .order = 2 },
    .{ .name = "ui", .level = 3, .order = 3 },
    .{ .name = "widgets", .level = 4, .order = 0 },
    .{ .name = "app", .level = 4, .order = 1 },
};

fn findMod(name: []const u8) ?Mod {
    for (modules) |m| if (std.mem.eql(u8, m.name, name)) return m;
    return null;
}

fn depAllowed(from: Mod, to: Mod) bool {
    return to.level < from.level or (to.level == from.level and to.order < from.order);
}

/// 文件所属模块名。REQ-ARCH-006：命令系统与设置持久化属于 app，UI 自动化桥接属于 platform。
fn moduleOf(path: []const u8) ?[]const u8 {
    if (!startsWith(path, "src/")) return null;
    const rel = path["src/".len..];
    if (std.mem.indexOfScalar(u8, rel, '/')) |slash| return rel[0..slash];
    const base = rel[0 .. rel.len - ".zig".len];
    if (findMod(base) != null) return base;
    if (std.mem.eql(u8, base, "commands") or std.mem.eql(u8, base, "settings")) return "app";
    if (std.mem.eql(u8, base, "uia")) return "platform";
    return null;
}

fn isEntryOf(path: []const u8, module: []const u8) bool {
    var buf: [128]u8 = undefined;
    const a1 = std.fmt.bufPrint(&buf, "src/{s}.zig", .{module}) catch return false;
    if (std.mem.eql(u8, path, a1)) return true;
    var buf2: [128]u8 = undefined;
    const a2 = std.fmt.bufPrint(&buf2, "src/{s}/root.zig", .{module}) catch return false;
    return std.mem.eql(u8, path, a2);
}

const Import = struct { line: usize, spec: []const u8 };

fn importsOf(a: Allocator, p: Parsed) ![]const Import {
    var out: List(Import) = .empty;
    for (p.lex, 0..) |lx, i| {
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, lx.raw, pos, "@import(\"")) |at| {
            const s = at + "@import(\"".len;
            const e = std.mem.indexOfScalarPos(u8, lx.raw, s, '"') orelse break;
            try out.append(a, .{ .line = i + 1, .spec = lx.raw[s..e] });
            pos = e;
        }
    }
    return out.items;
}

fn isStdImport(spec: []const u8) bool {
    return std.mem.eql(u8, spec, "std") or std.mem.eql(u8, spec, "builtin") or std.mem.eql(u8, spec, "build_options");
}

/// core 不得依赖操作系统 API（REQ-ARCH-002）：时钟、文件、进程、原始系统调用的 std 入口。
const core_os_tokens = [_][]const u8{
    "std.os.",            "std.posix.",     "std.fs.",                "std.process.",
    "std.Io.Dir",         "std.Io.File",    "std.Io.Clock",           "std.Io.Threaded",
    "std.time.Instant",   "std.time.Timer", "std.time.nanoTimestamp", "std.time.milliTimestamp",
    "std.time.timestamp",
};

/// AC-ARCH-001、AC-CONV-004：`@import` 依赖方向与 core 的独立性（REQ-ARCH-001/002、REQ-CONV-004）。
pub fn scanDeps(a: Allocator, files: []const File, rep: *Report) !void {
    for (files) |f| {
        if (!isZig(f.path) or !startsWith(f.path, "src/")) continue;
        if (std.mem.eql(u8, f.path, "src/nano_gui.zig")) continue; // 库根，导入全部模块
        const p = try parseFile(a, f);
        const my = moduleOf(f.path) orelse continue;
        const my_mod = findMod(my);
        const dir = std.fs.path.dirnamePosix(f.path) orelse "";
        for (try importsOf(a, p)) |imp| {
            if (isStdImport(imp.spec)) continue;
            if (!std.mem.endsWith(u8, imp.spec, ".zig")) {
                if (std.mem.eql(u8, my, "core")) rep.add(f.path, imp.line, "core 导入了模块外的命名模块 \"{s}\"（REQ-ARCH-002）", .{imp.spec});
                continue;
            }
            const target = try joinNorm(a, dir, imp.spec);
            const tm = moduleOf(target) orelse {
                rep.add(f.path, imp.line, "导入 \"{s}\"（{s}）不属于 src/ 下的任何模块", .{ imp.spec, target });
                continue;
            };
            if (std.mem.eql(u8, tm, my)) continue;
            if (std.mem.eql(u8, my, "core")) {
                rep.add(f.path, imp.line, "core 导入了其他模块 {s}（REQ-ARCH-002）", .{tm});
                continue;
            }
            const to_mod = findMod(tm) orelse continue;
            if (my_mod) |fm| {
                if (!depAllowed(fm, to_mod)) {
                    rep.add(f.path, imp.line, "依赖方向违规：{s} 不得导入 {s}（REQ-ARCH-001）", .{ my, tm });
                }
            }
        }
        if (std.mem.eql(u8, my, "core")) {
            for (p.lex, 0..) |lx, i| {
                for (core_os_tokens) |tok| {
                    if (contains(lx.code, tok)) {
                        rep.add(f.path, i + 1, "core 引用了操作系统 API `{s}`（REQ-ARCH-002）", .{tok});
                        break;
                    }
                }
            }
        }
    }
}

const SymCat = enum { nvg_gl, glfw, win32 };

const SymHit = struct { cat: SymCat, tok: []const u8 };

fn symCatName(c: SymCat) []const u8 {
    return switch (c) {
        .nvg_gl => "NanoVG/GL",
        .glfw => "GLFW",
        .win32 => "Win32",
    };
}

fn symAllowed(cat: SymCat, path: []const u8) bool {
    switch (cat) {
        // 仅 gfx 与 text 的后端实现文件（入口文件之外、位于 src/<模块>/ 下）。
        .nvg_gl => return inDir(path, "src/gfx") or inDir(path, "src/text"),
        // 仅 platform 的 glfw 后端。
        .glfw => return inDir(path, "src/platform") and contains(path, "glfw"),
        // 仅 platform 的 win32 后端与 text 的 DirectWrite 后端。
        .win32 => return (inDir(path, "src/platform") and contains(path, "win32")) or
            (inDir(path, "src/text") and contains(path, "directwrite")),
    }
}

const win32_exact = [_][]const u8{
    "HWND",                  "HDC",     "HINSTANCE", "HGLRC",   "LPARAM", "WPARAM",
    "LRESULT",               "HMODULE", "HICON",     "HCURSOR", "HBRUSH", "WNDCLASSEXW",
    "PIXELFORMATDESCRIPTOR",
};
const win32_prefix = [_][]const u8{ "WM_", "VK_", "WS_", "CS_", "IDC_", "SW_", "MK_", "PM_" };
const win32_libs = [_][]const u8{ "user32", "kernel32", "gdi32", "opengl32", "shell32", "ole32", "dwrite", "imm32", "dwmapi", "comdlg32", "advapi32", "shcore", "uxtheme", "oleaut32", "d2d1", "d3d11", "dxgi", "uiautomationcore" };

fn classifyToken(tok: []const u8) ?SymCat {
    if (tok.len > 3 and startsWith(tok, "nvg") and std.ascii.isUpper(tok[3])) return .nvg_gl;
    if (startsWith(tok, "NVG")) return .nvg_gl;
    if (tok.len > 2 and startsWith(tok, "gl") and std.ascii.isUpper(tok[2])) return .nvg_gl;
    if (startsWith(tok, "GL_") or startsWith(tok, "GLEW") or startsWith(tok, "glew")) return .nvg_gl;
    if (tok.len > 4 and startsWith(tok, "glfw") and std.ascii.isUpper(tok[4])) return .glfw;
    if (startsWith(tok, "GLFW")) return .glfw;
    for (win32_prefix) |p| if (startsWith(tok, p)) return .win32;
    for (win32_exact) |e| if (std.mem.eql(u8, tok, e)) return .win32;
    return null;
}

/// 扫描一行代码里的外部库符号，返回命中的类别与记号（每类每行只报一次由调用方去重）。
fn lineSymbols(a: Allocator, lx: Lexed, hits: *List(SymHit)) !void {
    var i: usize = 0;
    const code = lx.code;
    while (i < code.len) {
        if (!isIdent(code[i])) {
            i += 1;
            continue;
        }
        var j = i;
        while (j < code.len and isIdent(code[j])) j += 1;
        if (classifyToken(code[i..j])) |c| try hits.append(a, .{ .cat = c, .tok = code[i..j] });
        i = j;
    }
    if (contains(code, "callconv(.winapi)")) try hits.append(a, .{ .cat = .win32, .tok = "callconv(.winapi)" });
    if (contains(code, "std.os.windows")) try hits.append(a, .{ .cat = .win32, .tok = "std.os.windows" });
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, lx.raw, pos, "extern \"")) |at| {
        const s = at + "extern \"".len;
        const e = std.mem.indexOfScalarPos(u8, lx.raw, s, '"') orelse break;
        for (win32_libs) |lib| {
            if (std.ascii.eqlIgnoreCase(lx.raw[s..e], lib)) {
                try hits.append(a, .{ .cat = .win32, .tok = lx.raw[at..e] });
                break;
            }
        }
        pos = e;
    }
    pos = 0;
    while (std.mem.indexOfPos(u8, lx.raw, pos, "@import(\"")) |at| {
        const s = at + "@import(\"".len;
        const e = std.mem.indexOfScalarPos(u8, lx.raw, s, '"') orelse break;
        const spec = lx.raw[s..e];
        pos = e;
        if (isStdImport(spec) or std.mem.endsWith(u8, spec, ".zig")) continue;
        if (contains(spec, "glfw")) {
            try hits.append(a, .{ .cat = .glfw, .tok = spec });
        } else if (contains(spec, "nanovg") or contains(spec, "fontstash") or startsWith(spec, "gl")) {
            try hits.append(a, .{ .cat = .nvg_gl, .tok = spec });
        }
    }
}

/// AC-ARCH-001、AC-CONV-004：NanoVG/GL/Win32/GLFW 符号只出现在允许的后端文件（REQ-ARCH-003、REQ-CONV-004）。
pub fn scanSymbols(a: Allocator, files: []const File, rep: *Report) !void {
    for (files) |f| {
        if (!isZig(f.path) or !startsWith(f.path, "src/")) continue;
        const p = try parseFile(a, f);
        for (p.lex, 0..) |lx, i| {
            var hits: List(SymHit) = .empty;
            try lineSymbols(a, lx, &hits);
            var seen: [3]bool = @splat(false);
            for (hits.items) |h| {
                if (seen[@backingInt(h.cat)] or symAllowed(h.cat, f.path)) continue;
                seen[@backingInt(h.cat)] = true;
                rep.add(f.path, i + 1, "{s} 符号 `{s}` 出现在非后端文件（REQ-ARCH-003）", .{ symCatName(h.cat), h.tok });
            }
        }
    }
}

/// AC-CONV-003（及 AC-ARCH-001 对 REQ-ARCH-006 的覆盖）：模块目录与入口约定、跨模块只导入入口文件。
pub fn scanLayout(a: Allocator, files: []const File, rep: *Report) !void {
    var dirs = std.StringHashMapUnmanaged(void).empty;
    var have = std.StringHashMapUnmanaged(void).empty;
    for (files) |f| {
        if (!startsWith(f.path, "src/")) continue;
        try have.put(a, f.path, {});
        const rel = f.path["src/".len..];
        if (std.mem.indexOfScalar(u8, rel, '/')) |slash| {
            try dirs.put(a, rel[0..slash], {});
        } else if (isZig(rel)) {
            const base = rel[0 .. rel.len - ".zig".len];
            if (findMod(base) == null and !std.mem.eql(u8, base, "nano_gui")) {
                rep.add(f.path, 1, "src/ 顶层文件 `{s}` 不是 02 模块表中的模块入口（REQ-ARCH-006/REQ-CONV-003）", .{rel});
            }
        }
    }
    var dit = dirs.keyIterator();
    while (dit.next()) |k| {
        const d = k.*;
        const e1 = try std.fmt.allocPrint(a, "src/{s}.zig", .{d});
        const e2 = try std.fmt.allocPrint(a, "src/{s}/root.zig", .{d});
        const h1 = have.contains(e1);
        const h2 = have.contains(e2);
        const dpath = try std.fmt.allocPrint(a, "src/{s}", .{d});
        if (findMod(d) == null) rep.add(dpath, 1, "目录 `{s}` 不是 02 模块表中的模块", .{d});
        if (!h1 and !h2) rep.add(dpath, 1, "模块目录 `{s}` 缺少入口文件 {s} 或 {s}", .{ d, e1, e2 });
        if (h1 and h2) rep.add(dpath, 1, "模块 `{s}` 同时存在 {s} 与 {s}，入口必须有且仅有一个", .{ d, e1, e2 });
    }
    for (files) |f| {
        if (!isZig(f.path) or !startsWith(f.path, "src/")) continue;
        if (std.mem.eql(u8, f.path, "src/nano_gui.zig")) continue;
        const my = moduleOf(f.path) orelse continue;
        const p = try parseFile(a, f);
        const dir = std.fs.path.dirnamePosix(f.path) orelse "";
        for (try importsOf(a, p)) |imp| {
            if (!std.mem.endsWith(u8, imp.spec, ".zig")) continue;
            const target = try joinNorm(a, dir, imp.spec);
            const tm = moduleOf(target) orelse continue;
            if (std.mem.eql(u8, tm, my)) continue;
            if (!isEntryOf(target, tm)) {
                rep.add(f.path, imp.line, "跨模块导入了 {s} 的非入口文件 {s}（REQ-ARCH-006）", .{ tm, target });
            }
        }
    }
}

/// AC-PLAT-018：platform 的 Win32 后端不得引用触摸/指针/手势消息（REQ-PLAT-030）。
/// 范围：属于 platform 模块的全部源文件（含 UIA 桥接）；只看代码，不看注释。
pub fn scanNoTouch(a: Allocator, files: []const File, rep: *Report) !void {
    const banned = [_][]const u8{ "RegisterTouchWindow", "WM_TOUCH", "WM_POINTER", "WM_GESTURE" };
    for (files) |f| {
        if (!isZig(f.path)) continue;
        const m = moduleOf(f.path) orelse continue;
        if (!std.mem.eql(u8, m, "platform")) continue;
        const p = try parseFile(a, f);
        for (p.lex, 0..) |lx, i| {
            for (banned) |b| {
                if (contains(lx.raw, b)) rep.add(f.path, i + 1, "引用了 `{s}`（REQ-PLAT-030 要求按鼠标语义，不处理触摸）", .{b});
            }
        }
    }
}

// ---------------------------------------------------------------------------
// AC-CONV-005 命名：目录与文件名
// ---------------------------------------------------------------------------

/// AC-CONV-005：`src/` 与 `tests/` 下除扩展名 `.zig` 外，每个名字匹配 `^[a-z][a-z0-9_]*$`。
/// 字面执行：其他扩展名（如 `.png`）不豁免。
pub fn scanFileNames(a: Allocator, files: []const File, rep: *Report) !void {
    var seen = std.StringHashMapUnmanaged(void).empty;
    for (files) |f| {
        if (!startsWith(f.path, "src/") and !startsWith(f.path, "tests/")) continue;
        var it = std.mem.splitScalar(u8, f.path, '/');
        var prefix_end: usize = 0;
        while (it.next()) |comp| {
            prefix_end += comp.len;
            const last = prefix_end == f.path.len;
            const prefix = f.path[0..prefix_end];
            prefix_end += 1;
            var name = comp;
            if (last and std.mem.endsWith(u8, name, ".zig")) name = name[0 .. name.len - 4];
            if (seen.contains(prefix)) continue;
            try seen.put(a, prefix, {});
            if (!isSnake(name)) rep.add(prefix, 1, "名字 `{s}` 不匹配 ^[a-z][a-z0-9_]*$（REQ-CONV-005）", .{comp});
        }
    }
}

// ---------------------------------------------------------------------------
// 绑定文件（REQ-CONV-018/019）
// ---------------------------------------------------------------------------

/// 文档未定义绑定文件的命名，这里约定：`src/<模块>/` 下 `bindings.zig` 或 `*_bindings.zig`。
fn isBindingFile(path: []const u8) bool {
    if (!startsWith(path, "src/")) return false;
    const rel = path["src/".len..];
    if (std.mem.indexOfScalar(u8, rel, '/') == null) return false;
    const base = std.fs.path.basenamePosix(path);
    return std.mem.eql(u8, base, "bindings.zig") or std.mem.endsWith(u8, base, "_bindings.zig");
}

fn isWin32Binding(path: []const u8) bool {
    return isBindingFile(path) and (contains(path, "win32") or contains(path, "directwrite"));
}

/// AC-CONV-018：`extern` 声明与 `@cImport` 只能在绑定文件（REQ-CONV-018）。
pub fn scanExternPlacement(a: Allocator, files: []const File, rep: *Report) !void {
    for (files) |f| {
        if (!isZig(f.path) or !startsWith(f.path, "src/") or isBindingFile(f.path)) continue;
        const p = try parseFile(a, f);
        for (p.lex, 0..) |lx, i| {
            const code = lx.code;
            if (contains(code, "@cImport")) rep.add(f.path, i + 1, "`@cImport` 出现在非绑定文件", .{});
            if (contains(code, "@extern")) rep.add(f.path, i + 1, "`@extern` 出现在非绑定文件", .{});
            var pos: usize = 0;
            while (wordIndex(code, "extern", pos)) |at| {
                pos = at + 1;
                const rest = std.mem.trimStart(u8, code[at + "extern".len ..], " \t");
                const layout_words = [_][]const u8{ "struct", "union", "enum", "opaque" };
                var is_layout = false;
                for (layout_words) |w| {
                    if (startsWith(rest, w) and (rest.len == w.len or !isIdent(rest[w.len]))) is_layout = true;
                }
                if (!is_layout) {
                    rep.add(f.path, i + 1, "外部声明 `extern` 出现在非绑定文件", .{});
                    break;
                }
            }
        }
    }
}

/// 常量右侧是否像类型表达式（Win32 的类型别名、PascalCase 的类型常量）。
fn looksLikeType(rhs_in: []const u8) bool {
    const rhs = trim(rhs_in);
    if (rhsIsTypeDecl(rhs)) return true;
    const t_prefix = [_][]const u8{ "@Type", "@Vector", "@TypeOf", "@This", "@FieldType", "?", "*", "[", "fn", "type" };
    for (t_prefix) |p| if (startsWith(rhs, p)) return true;
    var n: usize = 0;
    while (n < rhs.len and (isIdent(rhs[n]) or rhs[n] == '.')) n += 1;
    const path = rhs[0..n];
    if (path.len == 0) return false;
    const last_dot = std.mem.lastIndexOfScalar(u8, path, '.');
    const seg = if (last_dot) |d| path[d + 1 ..] else path;
    if (seg.len == 0) return false;
    const prims = [_][]const u8{ "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64", "f32", "f64", "usize", "isize", "bool", "void", "anyopaque", "c_int", "c_uint", "c_long", "c_ulong" };
    for (prims) |pm| if (std.mem.eql(u8, seg, pm)) return true;
    if (std.ascii.isUpper(seg[0])) {
        for (seg) |c| if (std.ascii.isLower(c)) return true;
    }
    return false;
}

/// AC-CONV-019：Win32 绑定文件里的名字保持 Win32 原名，包装函数不在绑定文件中（REQ-CONV-019）。
/// 静态判定：函数/类型为 PascalCase 且不得出现 snake_case 或小写开头；常量为全大写；
/// 绑定文件中不得有带函数体的 fn（包装函数属于非绑定文件）。
pub fn scanWin32Names(a: Allocator, files: []const File, rep: *Report) !void {
    for (files) |f| {
        if (!isZig(f.path) or !isWin32Binding(f.path)) continue;
        const p = try parseFile(a, f);
        for (p.decls) |d| {
            if (d.frame_kind == .block) continue;
            switch (d.kind) {
                .fn_decl => {
                    if (d.has_body) {
                        rep.add(f.path, d.line, "绑定文件中出现带函数体的包装函数 `{s}`，应放在非绑定文件", .{d.name});
                    } else if (!isPascal(d.name)) {
                        rep.add(f.path, d.line, "Win32 函数 `{s}` 不是 Win32 原名形式（PascalCase）", .{d.name});
                    }
                },
                .const_decl => {
                    if (d.is_type_decl or looksLikeType(d.rhs)) {
                        if (!(isPascal(d.name) or isUpperSnake(d.name))) {
                            rep.add(f.path, d.line, "Win32 类型 `{s}` 不是 Win32 原名形式", .{d.name});
                        }
                    } else if (!isUpperSnake(d.name)) {
                        rep.add(f.path, d.line, "Win32 常量 `{s}` 不是原全大写名", .{d.name});
                    }
                },
                else => {},
            }
        }
    }
}

// ---------------------------------------------------------------------------
// AC-CONV-006 命名规则
// ---------------------------------------------------------------------------

/// AC-CONV-006：类型 PascalCase；函数（不含返回 type 者）camelCase；枚举成员 snake_case；
/// 非 Win32 绑定文件中的容器级常量 snake_case（类型别名按类型处理）。
pub fn scanNaming(a: Allocator, files: []const File, rep: *Report) !void {
    for (files) |f| {
        if (!isZig(f.path) or !startsWith(f.path, "src/")) continue;
        const win32 = isWin32Binding(f.path);
        const p = try parseFile(a, f);
        for (p.decls) |d| {
            if (startsWith(d.name, "@\"")) continue;
            switch (d.kind) {
                .enum_member => if (!isSnake(d.name)) rep.add(f.path, d.line, "枚举成员 `{s}` 应为 snake_case", .{d.name}),
                .fn_decl => {
                    if (win32 and (d.is_extern or !d.has_body)) continue;
                    const sig = try parseSig(a, d.sig);
                    const returns_type = if (sig) |s| std.mem.eql(u8, s.ret, "type") else false;
                    if (returns_type) continue;
                    if (!isCamel(d.name)) rep.add(f.path, d.line, "函数 `{s}` 应为 camelCase", .{d.name});
                },
                .const_decl => {
                    if (d.is_type_decl) {
                        if (!win32 and !isPascal(d.name)) rep.add(f.path, d.line, "类型 `{s}` 应为 PascalCase", .{d.name});
                    } else if (d.frame_kind != .block and !win32) {
                        if (looksLikeType(d.rhs)) continue;
                        if (!isSnake(d.name)) rep.add(f.path, d.line, "常量 `{s}` 应为 snake_case", .{d.name});
                    }
                },
                .var_decl => {},
            }
        }
    }
}

// ---------------------------------------------------------------------------
// AC-CONV-011 / AC-CONV-021 文档注释
// ---------------------------------------------------------------------------

const ownership_phrases = [_][]const u8{ "框架复制", "调用方须保证存活至", "借用至本帧结束" };

fn hasOwnershipPhrase(doc: []const u8) bool {
    for (ownership_phrases) |p| if (contains(doc, p)) return true;
    return false;
}

/// 接收者形参（`self`）不是数据所有权问题，不计入；其余指针/切片形参都计入（含 `ui: *Ui`）。
fn ptrParamName(a: Allocator, sig: []const u8) !?[]const u8 {
    const s = (try parseSig(a, sig)) orelse return null;
    for (s.params) |pr| {
        if (std.mem.eql(u8, pr.name, "self")) continue;
        if (isPtrOrSlice(pr.ty)) return pr.name;
    }
    return null;
}

fn isPublicApi(d: Decl) bool {
    return d.is_pub and d.frame_pub and d.frame_kind != .block;
}

/// AC-CONV-011：公开 API 中的指针与切片参数须在文档注释写明所有权（REQ-CONV-011）。
pub fn scanOwnership(a: Allocator, files: []const File, rep: *Report) !void {
    for (files) |f| {
        if (!isZig(f.path) or !startsWith(f.path, "src/")) continue;
        const p = try parseFile(a, f);
        for (p.decls) |d| {
            if (d.kind != .fn_decl or !isPublicApi(d)) continue;
            const pn = (try ptrParamName(a, d.sig)) orelse continue;
            const doc = try docAbove(a, p.lines, d.line);
            if (!hasOwnershipPhrase(doc)) {
                rep.add(f.path, d.line, "公开函数 `{s}` 的指针/切片参数 `{s}` 未在文档注释写明所有权", .{ d.name, pn });
            }
        }
    }
}

fn distinctive(tok: []const u8) bool {
    if (tok.len < 6) return false;
    var lower = false;
    var upper_inner = false;
    var under = false;
    for (tok, 0..) |c, i| {
        if (std.ascii.isLower(c)) lower = true;
        if (std.ascii.isUpper(c) and i > 0) upper_inner = true;
        if (c == '_') under = true;
    }
    return lower and (upper_inner or under or std.ascii.isUpper(tok[0]));
}

/// 从 docs/ 的 REQ 段落中收集以反引号标出的特征标识符，用于判断“有对应规范条款”（启发式）。
fn specIdentifiers(a: Allocator, files: []const File) !std.StringHashMapUnmanaged(void) {
    var set = std.StringHashMapUnmanaged(void).empty;
    for (files) |f| {
        if (!startsWith(f.path, "docs/") or !std.mem.endsWith(u8, f.path, ".md")) continue;
        var it = std.mem.splitScalar(u8, f.text, '\n');
        while (it.next()) |l| {
            if (!startsWith(l, "**REQ-")) continue;
            var parts = std.mem.splitScalar(u8, l, '`');
            var idx: usize = 0;
            while (parts.next()) |seg| : (idx += 1) {
                if (idx % 2 == 0) continue;
                var tokstart: usize = 0;
                var k: usize = 0;
                while (k <= seg.len) : (k += 1) {
                    if (k == seg.len or !isIdent(seg[k])) {
                        const tok = seg[tokstart..k];
                        if (distinctive(tok)) try set.put(a, tok, {});
                        tokstart = k + 1;
                    }
                }
            }
        }
    }
    return set;
}

/// AC-CONV-021：公开 `pub fn`/`pub const` 的文档注释含线程要求；有对应规范条款者含 `REQ-`；
/// 涉及所有权者含 REQ-CONV-011 三种表述之一。
/// “有对应规范条款”无法精确判定，这里用启发式：该名字作为特征标识符（长度 ≥ 6 且为驼峰/帕斯卡/含下划线）
/// 出现在 docs/ 某条 REQ 段落的反引号中。
pub fn scanDocComments(a: Allocator, files: []const File, rep: *Report) !void {
    const spec = try specIdentifiers(a, files);
    for (files) |f| {
        if (!isZig(f.path) or !startsWith(f.path, "src/")) continue;
        const p = try parseFile(a, f);
        for (p.decls) |d| {
            if (!isPublicApi(d) or (d.kind != .fn_decl and d.kind != .const_decl)) continue;
            const doc = try docAbove(a, p.lines, d.line);
            if (doc.len == 0) {
                rep.add(f.path, d.line, "公开声明 `{s}` 缺少文档注释（REQ-CONV-021）", .{d.name});
                continue;
            }
            if (!contains(doc, "界面线程") and !contains(doc, "线程安全")) {
                rep.add(f.path, d.line, "`{s}` 的文档注释未写线程要求（界面线程/线程安全）", .{d.name});
            }
            if (spec.contains(d.name) and !contains(doc, "REQ-")) {
                rep.add(f.path, d.line, "`{s}` 在规范中有对应条款，但文档注释未含 REQ- 编号", .{d.name});
            }
            if (d.kind == .fn_decl) {
                if (try ptrParamName(a, d.sig)) |pn| {
                    if (!hasOwnershipPhrase(doc)) {
                        rep.add(f.path, d.line, "`{s}` 的指针/切片参数 `{s}` 未写明所有权表述", .{ d.name, pn });
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// AC-CONV-012 / 014 / 015
// ---------------------------------------------------------------------------

fn isWidgetsFile(path: []const u8) bool {
    return std.mem.eql(u8, path, "src/widgets.zig") or inDir(path, "src/widgets");
}

/// AC-CONV-012：`src/` 中无 `anyerror`；widgets 的控件函数（公开、首参为 `ui` 指针）返回类型不含 `!`。
pub fn scanErrors(a: Allocator, files: []const File, rep: *Report) !void {
    for (files) |f| {
        if (!isZig(f.path) or !startsWith(f.path, "src/")) continue;
        const p = try parseFile(a, f);
        for (p.lex, 0..) |lx, i| {
            if (hasWord(lx.code, "anyerror")) rep.add(f.path, i + 1, "出现 `anyerror`（REQ-CONV-012）", .{});
        }
        if (!isWidgetsFile(f.path)) continue;
        for (p.decls) |d| {
            if (d.kind != .fn_decl or !isPublicApi(d)) continue;
            const s = (try parseSig(a, d.sig)) orelse continue;
            if (s.params.len == 0 or !std.mem.eql(u8, s.params[0].name, "ui") or !startsWith(s.params[0].ty, "*")) continue;
            if (contains(s.ret, "!")) rep.add(f.path, d.line, "控件函数 `{s}` 返回错误联合 `{s}`（REQ-ARCH-018）", .{ d.name, s.ret });
        }
    }
}

/// REQ-CONV-014 允许的全局可变状态所在文件：日志接收器与统计计数器（均在 core）。
fn isGlobalStateExempt(path: []const u8) bool {
    return std.mem.eql(u8, path, "src/core.zig") or std.mem.eql(u8, path, "src/core/log.zig") or
        std.mem.eql(u8, path, "src/core/stats.zig");
}

/// AC-CONV-014：`src/` 容器级 `var`（含 threadlocal），排除日志接收器与统计计数器所在文件。
pub fn scanGlobalVars(a: Allocator, files: []const File, rep: *Report) !void {
    for (files) |f| {
        if (!isZig(f.path) or !startsWith(f.path, "src/") or isGlobalStateExempt(f.path)) continue;
        const p = try parseFile(a, f);
        for (p.decls) |d| {
            if (d.kind == .var_decl and d.frame_kind != .block) {
                rep.add(f.path, d.line, "容器级 var `{s}`（REQ-CONV-014 禁止全局可变状态）", .{d.name});
            }
        }
    }
}

/// AC-CONV-015：`src/` 与 `tests/` 中无 `usingnamespace`。
pub fn scanUsingnamespace(a: Allocator, files: []const File, rep: *Report) !void {
    for (files) |f| {
        if (!isZig(f.path) or (!startsWith(f.path, "src/") and !startsWith(f.path, "tests/"))) continue;
        const p = try parseFile(a, f);
        for (p.lex, 0..) |lx, i| {
            if (hasWord(lx.code, "usingnamespace")) rep.add(f.path, i + 1, "出现 `usingnamespace`（REQ-CONV-015）", .{});
        }
    }
}

// ---------------------------------------------------------------------------
// AC-CONV-022 注释与标识符语言；AC-CONV-028 行数
// ---------------------------------------------------------------------------

/// AC-CONV-022：注释须含中文字符；标识符（代码中字符串之外）不得含非 ASCII 字符。
/// 无任何字母数字的注释（空的 `///` 段落分隔线、`// ----` 分隔线）视为无内容，不要求含中文。
pub fn scanLanguage(a: Allocator, files: []const File, rep: *Report) !void {
    for (files) |f| {
        if (!isZig(f.path) or !startsWith(f.path, "src/")) continue;
        const p = try parseFile(a, f);
        for (p.lex, 0..) |lx, i| {
            if (lx.comment) |c| {
                if (hasLetterOrDigit(c) and !hasHan(c)) rep.add(f.path, i + 1, "注释不含中文（REQ-CONV-022）", .{});
            }
            for (lx.code) |b| {
                if (b >= 0x80) {
                    rep.add(f.path, i + 1, "标识符含非 ASCII 字符（REQ-CONV-022）", .{});
                    break;
                }
            }
        }
    }
}

pub const loc_limit: usize = 30_000;

/// 非空、非注释行数（多行字符串行计为代码）。
pub fn countCodeLines(a: Allocator, files: []const File) !usize {
    var n: usize = 0;
    for (files) |f| {
        if (!isZig(f.path) or !startsWith(f.path, "src/")) continue;
        const p = try parseFile(a, f);
        for (p.lex) |lx| {
            if (trim(lx.raw).len > 0) n += 1;
        }
    }
    return n;
}

/// AC-CONV-028：`src/` 代码行数 ≤ 30 000；超过时路线图须有精简计划。
pub fn scanLoc(a: Allocator, files: []const File, rep: *Report) !void {
    const n = try countCodeLines(a, files);
    if (n <= loc_limit) return;
    for (files) |f| {
        if (std.mem.eql(u8, f.path, "docs/14-roadmap.md") and contains(f.text, "精简")) return;
    }
    rep.add("src", 1, "代码行数 {d} > {d}，且 docs/14-roadmap.md 中没有精简计划（REQ-CONV-028）", .{ n, loc_limit });
}

// ---------------------------------------------------------------------------
// third_party：AC-CONV-017、AC-CONV-029、AC-CONV-030
// ---------------------------------------------------------------------------

fn thirdPartyLibs(a: Allocator, files: []const File) ![]const []const u8 {
    var set = std.StringHashMapUnmanaged(void).empty;
    var out: List([]const u8) = .empty;
    for (files) |f| {
        if (!inDir(f.path, "third_party")) continue;
        const rel = f.path["third_party/".len..];
        const slash = std.mem.indexOfScalar(u8, rel, '/') orelse continue;
        if (set.contains(rel[0..slash])) continue;
        try set.put(a, rel[0..slash], {});
        try out.append(a, rel[0..slash]);
    }
    return out.items;
}

fn findFile(files: []const File, path: []const u8) ?File {
    for (files) |f| if (std.mem.eql(u8, f.path, path)) return f;
    return null;
}

fn isHex64(s: []const u8) bool {
    if (s.len != 64) return false;
    for (s) |c| if (!std.ascii.isHex(c)) return false;
    return true;
}

fn keyedValue(line: []const u8, keys: []const []const u8) ?[]const u8 {
    var l = trim(line);
    while (l.len > 0 and (l[0] == '-' or l[0] == '*' or l[0] == ' ')) l = l[1..];
    l = std.mem.trim(u8, l, "*");
    const colon = std.mem.indexOfAny(u8, l, ":") orelse blk: {
        const fw = std.mem.indexOf(u8, l, "：") orelse return null;
        break :blk fw;
    };
    const key = trim(std.mem.trim(u8, l[0..colon], "*"));
    var vstart = colon + 1;
    if (startsWith(l[colon..], "：")) vstart = colon + "：".len;
    for (keys) |k| {
        if (std.ascii.eqlIgnoreCase(key, k)) return std.mem.trim(u8, trim(l[vstart..]), "`* ");
    }
    return null;
}

/// AC-CONV-017：第三方 C 源码只在 `third_party/<库>/`、PATCHES.md 头部记录上游版本与校验和、每处差异有登记。
/// PATCHES.md 格式（文档未规定，本脚本约定）：
///   头部（第一个 `## ` 标题之前）含 `Upstream: <地址与版本>` 行，并为每个 C 源文件给出 `<sha256十六进制>  <文件名>` 行；
///   每处补丁为一个 `## <标题>` 小节，含 `目的:`/`Purpose:`、`文件:`/`Files:`、`上游版本:`/`Version:` 三个字段。
pub fn scanThirdPartySource(a: Allocator, files: []const File, rep: *Report) !void {
    for (files) |f| {
        if (!inDir(f.path, "third_party")) continue;
        if (std.mem.indexOfScalar(u8, f.path["third_party/".len..], '/') == null) {
            rep.add(f.path, 1, "第三方文件直接放在 third_party/ 顶层；第三方源码只能放在 third_party/<库>/ 下（REQ-CONV-017）", .{});
        }
    }
    for (try thirdPartyLibs(a, files)) |lib| {
        const dir = try std.fmt.allocPrint(a, "third_party/{s}", .{lib});
        const patches_path = try std.fmt.allocPrint(a, "{s}/PATCHES.md", .{dir});
        const patches = findFile(files, patches_path);
        if (patches == null) rep.add(dir, 1, "缺少 PATCHES.md（REQ-CONV-017）", .{});
        // 头部与登记项
        var header_has_upstream = false;
        var recorded = std.StringHashMapUnmanaged([]const u8).empty; // 文件名 -> sha256
        var registered = std.StringHashMapUnmanaged(void).empty;
        if (patches) |pf| {
            var in_header = true;
            var entry_start: usize = 0;
            var entry_files = false;
            var entry_purpose = false;
            var entry_version = false;
            var in_entry = false;
            var ln: usize = 0;
            var it = std.mem.splitScalar(u8, pf.text, '\n');
            while (it.next()) |raw_line| {
                ln += 1;
                const l = std.mem.trimEnd(u8, raw_line, "\r");
                if (startsWith(l, "## ")) {
                    if (in_entry and !(entry_files and entry_purpose and entry_version)) {
                        rep.add(patches_path, entry_start, "补丁登记缺少目的、文件或上游版本字段（REQ-CONV-017）", .{});
                    }
                    in_header = false;
                    in_entry = true;
                    entry_start = ln;
                    entry_files = false;
                    entry_purpose = false;
                    entry_version = false;
                    continue;
                }
                if (in_header) {
                    if (keyedValue(l, &.{ "Upstream", "上游" }) != null) header_has_upstream = true;
                    var toks = std.mem.tokenizeAny(u8, l, " \t`");
                    if (toks.next()) |first| {
                        if (isHex64(first)) {
                            if (toks.next()) |name| try recorded.put(a, std.mem.trim(u8, name, "*"), first);
                        }
                    }
                } else {
                    if (keyedValue(l, &.{ "目的", "Purpose" }) != null) entry_purpose = true;
                    if (keyedValue(l, &.{ "上游版本", "Version", "Upstream" }) != null) entry_version = true;
                    if (keyedValue(l, &.{ "文件", "Files", "File" })) |v| {
                        entry_files = true;
                        var ft = std.mem.tokenizeAny(u8, v, ", `");
                        while (ft.next()) |name| try registered.put(a, name, {});
                    }
                }
            }
            if (in_entry and !(entry_files and entry_purpose and entry_version)) {
                rep.add(patches_path, entry_start, "补丁登记缺少目的、文件或上游版本字段（REQ-CONV-017）", .{});
            }
            if (!header_has_upstream) rep.add(patches_path, 1, "PATCHES.md 头部缺少 `Upstream:` 上游版本记录", .{});
        }
        for (files) |f| {
            if (!inDir(f.path, dir)) continue;
            const base = std.fs.path.basenamePosix(f.path);
            const ext = extOf(base);
            const is_c = std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h");
            const allowed_other = std.mem.eql(u8, ext, ".md") or std.mem.eql(u8, ext, ".txt") or ext.len == 0 or
                std.mem.eql(u8, ext, ".ttf") or std.mem.eql(u8, ext, ".otf");
            if (!is_c and !allowed_other) {
                rep.add(f.path, 1, "third_party 中含非 C 源码文件 `{s}`（REQ-CONV-017）", .{base});
                continue;
            }
            if (!is_c) continue;
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(f.text, &digest, .{});
            const hex = std.fmt.bytesToHex(digest, .lower);
            if (recorded.get(base)) |want| {
                if (!std.ascii.eqlIgnoreCase(want, &hex) and !registered.contains(base)) {
                    rep.add(f.path, 1, "与记录的上游校验和不符，但 PATCHES.md 没有该文件的补丁登记（REQ-CONV-017）", .{});
                }
            } else {
                rep.add(f.path, 1, "PATCHES.md 头部没有记录 `{s}` 的上游 sha256 校验和", .{base});
            }
        }
    }
}

const binary_exts = [_][]const u8{ ".lib", ".dll", ".a", ".so", ".dylib", ".o", ".obj", ".exe", ".pdb", ".exp", ".pyd" };
const pkg_artifacts = [_][]const u8{ "package.json", "package-lock.json", "node_modules", "Cargo.toml", "Cargo.lock", "go.mod", "vcpkg.json", "conanfile.txt", "conanfile.py", "requirements.txt", "build.zig.zon", ".gitmodules" };

/// AC-CONV-029（可静态判定的部分）：`third_party/` 不含预编译二进制与包管理器产物；`build.zig.zon` 的依赖为空。
/// “新增库目录须同一合入请求新增 ADR”需要合入请求信息，不在此判定。
pub fn scanNoBinaries(a: Allocator, files: []const File, rep: *Report) !void {
    _ = a;
    for (files) |f| {
        if (inDir(f.path, "third_party")) {
            const ext = extOf(f.path);
            for (binary_exts) |b| {
                if (std.ascii.eqlIgnoreCase(ext, b)) rep.add(f.path, 1, "third_party 含预编译二进制 `{s}`（REQ-CONV-029）", .{ext});
            }
            var it = std.mem.splitScalar(u8, f.path, '/');
            while (it.next()) |comp| {
                for (pkg_artifacts) |pa| {
                    if (std.mem.eql(u8, comp, pa)) rep.add(f.path, 1, "third_party 含包管理器产物 `{s}`（REQ-CONV-029）", .{comp});
                }
            }
        }
        if (std.mem.eql(u8, f.path, "build.zig.zon")) {
            const at = std.mem.indexOf(u8, f.text, ".dependencies") orelse continue;
            const open = std.mem.indexOfScalarPos(u8, f.text, at, '{') orelse continue;
            const close = std.mem.indexOfScalarPos(u8, f.text, open, '}') orelse continue;
            if (trim(f.text[open + 1 .. close]).len != 0) {
                var line: usize = 1;
                for (f.text[0..at]) |c| if (c == '\n') {
                    line += 1;
                };
                rep.add(f.path, line, "build.zig.zon 声明了包管理器依赖（REQ-CONV-029 禁止）", .{});
            }
        }
    }
}

const mit_text =
    \\MIT License
    \\
    \\Copyright (c) 2026 orangepro2001
    \\
    \\Permission is hereby granted, free of charge, to any person obtaining a copy
    \\of this software and associated documentation files (the "Software"), to deal
    \\in the Software without restriction, including without limitation the rights
    \\to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    \\copies of the Software, and to permit persons to whom the Software is
    \\furnished to do so, subject to the following conditions:
    \\
    \\The above copyright notice and this permission notice shall be included in all
    \\copies or substantial portions of the Software.
    \\
    \\THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    \\IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    \\FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    \\AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    \\LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    \\OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    \\SOFTWARE.
;

const spdx_allowed = [_][]const u8{ "MIT", "BSD-2-Clause", "BSD-3-Clause", "ISC", "Zlib", "Unlicense", "CC0-1.0" };

fn isFontFile(path: []const u8) bool {
    const e = extOf(path);
    return std.ascii.eqlIgnoreCase(e, ".ttf") or std.ascii.eqlIgnoreCase(e, ".otf") or
        std.ascii.eqlIgnoreCase(e, ".woff") or std.ascii.eqlIgnoreCase(e, ".woff2") or std.ascii.eqlIgnoreCase(e, ".ttc");
}

const Notice = struct {
    name: []const u8,
    line: usize,
    path: []const u8 = "",
    upstream: []const u8 = "",
    version: []const u8 = "",
    spdx: []const u8 = "",
    license_file: []const u8 = "",
    font_name: []const u8 = "",
    subset: []const u8 = "",
};

/// THIRD_PARTY_NOTICES.md 的条目格式（文档未规定，本脚本约定）：每项一个 `## <名称>` 小节，
/// 其下用 `- 路径:`、`- 上游地址:`、`- 版本:`、`- SPDX:`、`- 许可文本:` 登记（字体另加 `- 来源字体:`、`- 子集化范围:`），
/// 键名也接受英文 Path/Upstream/Version/License/License-File/Source-Font/Subset。
fn parseNotices(a: Allocator, text: []const u8) ![]Notice {
    var out: List(Notice) = .empty;
    var it = std.mem.splitScalar(u8, text, '\n');
    var ln: usize = 0;
    while (it.next()) |raw_line| {
        ln += 1;
        const l = std.mem.trimEnd(u8, raw_line, "\r");
        if (startsWith(l, "## ")) {
            try out.append(a, .{ .name = trim(l[3..]), .line = ln });
            continue;
        }
        if (out.items.len == 0) continue;
        const n = &out.items[out.items.len - 1];
        if (keyedValue(l, &.{ "路径", "Path" })) |v| n.path = std.mem.trimEnd(u8, v, "/");
        if (keyedValue(l, &.{ "上游地址", "Upstream" })) |v| n.upstream = v;
        if (keyedValue(l, &.{ "版本", "Version" })) |v| n.version = v;
        if (keyedValue(l, &.{ "SPDX", "许可证", "License" })) |v| n.spdx = v;
        if (keyedValue(l, &.{ "许可文本", "License-File" })) |v| n.license_file = v;
        if (keyedValue(l, &.{ "来源字体", "Source-Font" })) |v| n.font_name = v;
        if (keyedValue(l, &.{ "子集化范围", "Subset" })) |v| n.subset = v;
    }
    return out.items;
}

/// AC-CONV-030：许可检查（REQ-CONV-030/031/032）。
pub fn scanLicenses(a: Allocator, files: []const File, rep: *Report) !void {
    // (1) LICENSE
    if (findFile(files, "LICENSE")) |lf| {
        const norm = try std.mem.replaceOwned(u8, a, lf.text, "\r\n", "\n");
        if (!std.mem.eql(u8, trim(norm), mit_text)) rep.add("LICENSE", 1, "内容与 MIT 标准文本（版权行 Copyright (c) 2026 orangepro2001）不逐字一致", .{});
    } else rep.add("LICENSE", 1, "缺少 LICENSE 文件", .{});

    // (2)(3) THIRD_PARTY_NOTICES.md
    const notices_file = findFile(files, "THIRD_PARTY_NOTICES.md");
    var notices: []Notice = &.{};
    if (notices_file) |nf| notices = try parseNotices(a, nf.text) else rep.add("THIRD_PARTY_NOTICES.md", 1, "缺少 THIRD_PARTY_NOTICES.md", .{});
    const np = "THIRD_PARTY_NOTICES.md";
    var targets: List([]const u8) = .empty; // 应有登记的路径
    for (try thirdPartyLibs(a, files)) |lib| {
        try targets.append(a, try std.fmt.allocPrint(a, "third_party/{s}", .{lib}));
        // REQ-CONV-032：库目录原样保留许可文本
        var has_license = false;
        for (files) |f| {
            if (!inDir(f.path, targets.items[targets.items.len - 1])) continue;
            const b = std.fs.path.basenamePosix(f.path);
            if (startsWith(b, "LICENSE") or startsWith(b, "COPYING") or startsWith(b, "license") or startsWith(b, "COPYRIGHT")) has_license = true;
        }
        if (!has_license) rep.add(targets.items[targets.items.len - 1], 1, "库目录缺少上游许可文本文件（REQ-CONV-032）", .{});
    }
    for (files) |f| {
        if (inDir(f.path, "tests/fonts") and isFontFile(f.path)) try targets.append(a, f.path);
    }
    for (targets.items) |t| {
        var count: usize = 0;
        for (notices) |n| if (std.mem.eql(u8, n.path, t)) {
            count += 1;
        };
        if (count != 1) rep.add(np, 1, "`{s}` 在 THIRD_PARTY_NOTICES.md 中应恰有一项，实际 {d} 项", .{ t, count });
    }
    for (notices) |n| {
        var exists = false;
        for (targets.items) |t| if (std.mem.eql(u8, t, n.path)) {
            exists = true;
        };
        if (!exists) rep.add(np, n.line, "条目“{s}”的路径“{s}”不对应实际存在的第三方目录或测试字体", .{ n.name, n.path });
        const is_font = startsWith(n.path, "tests/fonts/");
        if (n.name.len == 0 or n.path.len == 0 or n.upstream.len == 0 or n.version.len == 0 or n.spdx.len == 0 or n.license_file.len == 0) {
            rep.add(np, n.line, "条目“{s}”必填字段不齐（名称、路径、上游地址、版本、SPDX、许可文本）", .{n.name});
        }
        if (is_font and (n.font_name.len == 0 or n.subset.len == 0)) {
            rep.add(np, n.line, "字体条目“{s}”缺少来源字体名或子集化范围", .{n.name});
        }
        if (n.license_file.len > 0 and findFile(files, n.license_file) == null) {
            rep.add(np, n.line, "条目“{s}”登记的许可文本路径“{s}”不存在", .{ n.name, n.license_file });
        }
        if (n.spdx.len > 0) {
            var ok = false;
            var has_ofl = false;
            var alts = std.mem.splitSequence(u8, n.spdx, " OR ");
            while (alts.next()) |alt| {
                const id = trim(std.mem.trim(u8, alt, "()"));
                if (std.mem.eql(u8, id, "OFL-1.1")) has_ofl = true;
                for (spdx_allowed) |s| if (std.mem.eql(u8, s, id)) {
                    ok = true;
                };
            }
            if (has_ofl and !is_font) {
                rep.add(np, n.line, "条目“{s}”使用 OFL-1.1，但它只允许用于 tests/fonts/", .{n.name});
            } else if (!ok and !(has_ofl and is_font)) {
                rep.add(np, n.line, "条目“{s}”的 SPDX 标识“{s}”不在允许清单内", .{ n.name, n.spdx });
            }
        }
    }

    // (4) PATCHES.md 登记的被修改文件须有修改标注
    for (files) |pf| {
        if (!std.mem.eql(u8, std.fs.path.basenamePosix(pf.path), "PATCHES.md") or !inDir(pf.path, "third_party")) continue;
        const dir = std.fs.path.dirnamePosix(pf.path).?;
        var it = std.mem.splitScalar(u8, pf.text, '\n');
        var in_entries = false;
        while (it.next()) |l| {
            if (startsWith(l, "## ")) in_entries = true;
            if (!in_entries) continue;
            const v = keyedValue(l, &.{ "文件", "Files", "File" }) orelse continue;
            var ft = std.mem.tokenizeAny(u8, v, ", `");
            while (ft.next()) |name| {
                const full = try std.fmt.allocPrint(a, "{s}/{s}", .{ dir, name });
                const tf = findFile(files, full) orelse {
                    rep.add(pf.path, 1, "登记的被修改文件 `{s}` 不存在", .{name});
                    continue;
                };
                var first: []const u8 = "";
                var lit = std.mem.splitScalar(u8, tf.text, '\n');
                while (lit.next()) |fl| {
                    if (trim(fl).len > 0) {
                        first = trim(fl);
                        break;
                    }
                }
                const is_comment = startsWith(first, "//") or startsWith(first, "/*");
                if (!(is_comment and contains(first, "PATCHES.md") and (contains(first, "modif") or contains(first, "修改")))) {
                    rep.add(full, 1, "被补丁修改的文件开头缺少指向 PATCHES.md 的修改标注注释（REQ-CONV-032）", .{});
                }
            }
        }
    }

    // (5) 发布产物与安装目录不含 tests/fonts 字体
    for (files) |f| {
        if (!(inDir(f.path, "tests/fonts") and isFontFile(f.path))) continue;
        const base = std.fs.path.basenamePosix(f.path);
        for (files) |g| {
            if (inDir(g.path, "zig-out") and std.mem.eql(u8, std.fs.path.basenamePosix(g.path), base)) {
                rep.add(g.path, 1, "安装目录含测试字体 `{s}`（REQ-CONV-031）", .{base});
            }
        }
    }
    for (files) |f| {
        if (isZig(f.path) and startsWith(f.path, "src/") or std.mem.eql(u8, f.path, "build.zig")) {
            const p = try parseFile(a, f);
            for (p.lex, 0..) |lx, i| {
                if (!contains(lx.raw, "tests/fonts")) continue;
                if (startsWith(f.path, "src/") or contains(lx.raw, "install") or contains(lx.raw, "embed")) {
                    rep.add(f.path, i + 1, "代码或构建脚本引用 tests/fonts，可能编进库或随产物分发（REQ-CONV-031）", .{});
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// AC-CONV-001 / AC-CONV-002：版本与 fmt
// ---------------------------------------------------------------------------

pub const required_zig = "0.17.1";

fn bumpCommitPathAllowed(path: []const u8) bool {
    return std.mem.eql(u8, path, "build.zig.zon") or startsWith(path, ".github/");
}

/// 升级最低版本字段的提交只允许改 build.zig.zon 与 CI 配置。
fn checkBumpCommit(c: Commit, rep: *Report, ac_note: []const u8) void {
    for (c.files) |p| {
        if (!bumpCommitPathAllowed(p)) {
            rep.add(p, 1, "修改 minimum_zig_version 的提交 {s} 同时改动了无关路径（{s}）", .{ c.hash[0..@min(c.hash.len, 8)], ac_note });
        }
    }
}

/// AC-CONV-001：`build.zig.zon` 最低版本与 CI 中的 Zig 版本均为 0.17.1；最近一次修改该字段的提交不含其他功能性改动。
pub fn scanZigVersion(files: []const File, bump_commits: []const Commit, rep: *Report) void {
    if (findFile(files, "build.zig.zon")) |z| {
        const key = "minimum_zig_version = \"";
        if (std.mem.indexOf(u8, z.text, key)) |at| {
            const s = at + key.len;
            const e = std.mem.indexOfScalarPos(u8, z.text, s, '"') orelse z.text.len;
            if (!std.mem.eql(u8, z.text[s..e], required_zig)) {
                rep.add("build.zig.zon", 1, "minimum_zig_version 为 {s}，应为 {s}", .{ z.text[s..e], required_zig });
            }
        } else rep.add("build.zig.zon", 1, "缺少 minimum_zig_version 字段", .{});
    } else rep.add("build.zig.zon", 1, "缺少 build.zig.zon", .{});

    var ci_found = false;
    for (files) |f| {
        if (!startsWith(f.path, ".github/workflows/") or !contains(f.text, "zig")) continue;
        ci_found = true;
        var it = std.mem.splitScalar(u8, f.text, '\n');
        var ln: usize = 0;
        while (it.next()) |l| {
            ln += 1;
            if (!contains(l, "ziglang.org") and !contains(l, "zig-") and !contains(l, "zig version")) continue;
            // 提取形如 x.y.z 的版本号
            var i: usize = 0;
            while (i < l.len) : (i += 1) {
                if (!std.ascii.isDigit(l[i]) or (i > 0 and (std.ascii.isDigit(l[i - 1]) or l[i - 1] == '.'))) continue;
                var j = i;
                while (j < l.len and (std.ascii.isDigit(l[j]) or l[j] == '.')) : (j += 1) {}
                var e = j;
                while (e > i and l[e - 1] == '.') e -= 1;
                const dots = std.mem.count(u8, l[i..e], ".");
                if (dots == 2) {
                    if (!std.mem.eql(u8, l[i..e], required_zig)) {
                        rep.add(f.path, ln, "CI 中的 Zig 版本 {s} 与 {s} 不一致", .{ l[i..e], required_zig });
                    }
                }
                i = j;
            }
        }
    }
    if (!ci_found) rep.add(".github/workflows", 1, "未找到引用 Zig 的 CI 配置", .{});
    if (bump_commits.len > 0) checkBumpCommit(bump_commits[0], rep, "AC-CONV-001");
}

/// AC-CONV-002（CI 部分）：CI 配置中存在 `zig fmt --check src … build.zig` 步骤且失败时任务失败。
/// `zig fmt` 本身的退出码由 `runFmtCheck` 执行。
pub fn scanCiFmtStep(files: []const File, rep: *Report) void {
    var found = false;
    for (files) |f| {
        if (!startsWith(f.path, ".github/workflows/")) continue;
        var it = std.mem.splitScalar(u8, f.text, '\n');
        var ln: usize = 0;
        var step_start: usize = 0;
        var lines: [4096][]const u8 = undefined;
        var n: usize = 0;
        while (it.next()) |l| {
            ln += 1;
            if (n < lines.len) {
                lines[n] = l;
                n += 1;
            }
            if (std.mem.indexOf(u8, l, "- name:") != null or std.mem.indexOf(u8, l, "- uses:") != null) step_start = n - 1;
            if (contains(l, "zig fmt --check") and contains(l, "src") and contains(l, "build.zig")) {
                found = true;
                // 在同一步骤内查找“失败不致任务失败”的写法
                var k = step_start;
                while (k < n) : (k += 1) {
                    if (contains(lines[k], "continue-on-error: true") or contains(lines[k], "|| true")) {
                        rep.add(f.path, ln, "fmt 检查步骤失败不会使任务失败（{s}）", .{trim(lines[k])});
                    }
                }
                if (std.mem.indexOf(u8, l, "|| true") != null) {}
            }
        }
    }
    if (!found) rep.add(".github/workflows/ci.yml", 1, "CI 中没有 `zig fmt --check src … build.zig` 步骤（REQ-CONV-002）", .{});
}

// ---------------------------------------------------------------------------
// 提交历史：AC-CONV-023 / 024 / 025
// ---------------------------------------------------------------------------

const commit_types = [_][]const u8{ "feat", "fix", "docs", "refactor", "test", "perf", "build", "chore" };

/// 等价于正则 `^(feat|fix|docs|refactor|test|perf|build|chore)(\([^)]+\))?!?: .*[一-鿿]`。
pub fn subjectOk(s: []const u8) bool {
    var rest: []const u8 = "";
    var matched = false;
    for (commit_types) |t| {
        if (startsWith(s, t)) {
            rest = s[t.len..];
            matched = true;
            break;
        }
    }
    if (!matched) return false;
    if (startsWith(rest, "(")) {
        const close = std.mem.indexOfScalar(u8, rest, ')') orelse return false;
        if (close == 1) return false;
        rest = rest[close + 1 ..];
    }
    if (startsWith(rest, "!")) rest = rest[1..];
    if (!startsWith(rest, ": ")) return false;
    rest = rest[2..];
    var i: usize = 0;
    while (i + 2 < rest.len) : (i += 1) {
        const b = rest[i];
        if (b >= 0xE4 and b <= 0xE9 and (rest[i + 1] & 0xC0) == 0x80 and (rest[i + 2] & 0xC0) == 0x80) {
            const cp: u32 = (@as(u32, b & 0x0F) << 12) | (@as(u32, rest[i + 1] & 0x3F) << 6) | (rest[i + 2] & 0x3F);
            if (cp >= 0x4E00 and cp <= 0x9FFF) return true;
        }
    }
    return false;
}

/// AC-CONV-023：最近 200 个提交的第一行符合约定式提交格式并含汉字。`commits` 为新到旧。
pub fn scanCommitSubjects(commits: []const Commit, rep: *Report) void {
    for (commits[0..@min(commits.len, 200)]) |c| {
        if (!subjectOk(c.subject)) rep.add(c.hash[0..@min(c.hash.len, 8)], 1, "提交标题不符合约定式提交格式或不含中文：{s}", .{c.subject});
    }
}

fn touchesDir(c: Commit, dir: []const u8) bool {
    for (c.files) |f| if (inDir(f, dir)) return true;
    return false;
}

/// 取 `AC-<域>-nnn` 记号（域为字母数字与连字符）。
fn takeAcTok(s: []const u8, at: usize) []const u8 {
    var e = at;
    while (e < s.len and (std.ascii.isAlphanumeric(s[e]) or s[e] == '-')) e += 1;
    return s[at..e];
}

fn acExists(files: []const File, id: []const u8) bool {
    for (files) |f| {
        if (!inDir(f.path, "docs/acceptance")) continue;
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, f.text, pos, id)) |at| {
            const end = at + id.len;
            if (end >= f.text.len or !(std.ascii.isAlphanumeric(f.text[end]) or f.text[end] == '-')) return true;
            pos = at + 1;
        }
    }
    return false;
}

/// AC-CONV-024：修改了 `src/` 的提交，正文含 `AC: AC-…` 行，且每个编号在 docs/acceptance/ 中存在。
pub fn scanCommitAcLines(files: []const File, commits: []const Commit, rep: *Report) void {
    for (commits) |c| {
        if (!touchesDir(c, "src")) continue;
        const short = c.hash[0..@min(c.hash.len, 8)];
        var any = false;
        var it = std.mem.splitScalar(u8, c.body, '\n');
        while (it.next()) |l| {
            const t = trim(l);
            if (!startsWith(t, "AC:")) continue;
            var pos: usize = 0;
            while (std.mem.indexOfPos(u8, t, pos, "AC-")) |at| {
                const tok = takeAcTok(t, at);
                pos = at + tok.len;
                any = true;
                if (!acExists(files, tok)) rep.add(short, 1, "提交（{s}）引用的 {s} 在 docs/acceptance/ 中不存在", .{ c.subject, tok });
            }
        }
        if (!any) rep.add(short, 1, "修改了 src/ 的提交缺少 `AC: AC-…` 行：{s}", .{c.subject});
    }
}

/// AC-CONV-025：提交粒度。`bump_hashes` 为修改过 minimum_zig_version 的提交哈希。
pub fn scanCommitGranularity(commits: []const Commit, bump_hashes: []const []const u8, rep: *Report) void {
    for (commits) |c| {
        const short = c.hash[0..@min(c.hash.len, 8)];
        if (touchesDir(c, "docs") and touchesDir(c, "src")) {
            rep.add(short, 1, "提交同时修改 docs/ 与 src/：{s}", .{c.subject});
        }
        if (touchesDir(c, "tests/golden")) {
            for (c.files) |p| {
                if (!inDir(p, "tests/golden")) {
                    rep.add(short, 1, "修改 tests/golden/ 的提交同时修改了 {s}：{s}", .{ p, c.subject });
                    break;
                }
            }
        }
        for (bump_hashes) |h| {
            if (std.mem.eql(u8, h, c.hash)) checkBumpCommit(c, rep, "AC-CONV-025");
        }
    }
}

fn runGit(a: Allocator, io: std.Io, args: []const []const u8) ![]const u8 {
    var argv: List([]const u8) = .empty;
    try argv.append(a, "git");
    try argv.appendSlice(a, args);
    const r = try std.process.run(a, io, .{ .argv = argv.items });
    if (!r.term.success()) return error.GitFailed;
    return r.stdout;
}

pub fn loadCommits(a: Allocator, io: std.Io, limit: ?usize) ![]Commit {
    var args: List([]const u8) = .empty;
    try args.appendSlice(a, &.{ "log", "--name-only", "--format=%x1e%H%x1f%s%x1f%b%x1f" });
    if (limit) |n| try args.append(a, try std.fmt.allocPrint(a, "-n{d}", .{n}));
    const out = try runGit(a, io, args.items);
    var commits: List(Commit) = .empty;
    var recs = std.mem.splitScalar(u8, out, 0x1e);
    while (recs.next()) |rec| {
        if (trim(rec).len == 0) continue;
        var f = std.mem.splitScalar(u8, rec, 0x1f);
        const hash = trim(f.next() orelse continue);
        const subject = f.next() orelse "";
        const body = f.next() orelse "";
        const names = f.next() orelse "";
        var fl: List([]const u8) = .empty;
        var nl = std.mem.splitScalar(u8, names, '\n');
        while (nl.next()) |n| if (trim(n).len > 0) try fl.append(a, trim(n));
        try commits.append(a, .{ .hash = hash, .subject = trim(subject), .body = body, .files = fl.items });
    }
    return commits.items;
}

pub fn loadBumpHashes(a: Allocator, io: std.Io) ![]const []const u8 {
    const out = try runGit(a, io, &.{ "log", "-G", "minimum_zig_version", "--format=%H", "--", "build.zig.zon" });
    var list: List([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, out, '\n');
    while (it.next()) |l| if (trim(l).len > 0) try list.append(a, trim(l));
    return list.items;
}

// ---------------------------------------------------------------------------
// 仓库加载与检查表
// ---------------------------------------------------------------------------

pub fn loadRepo(a: Allocator, io: std.Io) ![]File {
    var files: List(File) = .empty;
    const cwd = std.Io.Dir.cwd();
    const roots = [_][]const u8{ "src", "tests", "third_party", ".github", "docs", "zig-out" };
    for (roots) |root| {
        var dir = cwd.openDir(io, root, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        var w = try dir.walk(a);
        while (try w.next(io)) |e| {
            if (e.kind != .file) continue;
            const full = try std.fmt.allocPrint(a, "{s}/{s}", .{ root, e.path });
            const skip_text = std.mem.eql(u8, root, "zig-out") or (std.mem.eql(u8, root, "tests") and !isZig(e.path));
            const text: []const u8 = if (skip_text) "" else dir.readFileAlloc(io, e.path, a, .unlimited) catch "";
            try files.append(a, .{ .path = full, .text = text });
        }
    }
    for ([_][]const u8{ "LICENSE", "THIRD_PARTY_NOTICES.md", "build.zig", "build.zig.zon" }) |name| {
        const text = cwd.readFileAlloc(io, name, a, .unlimited) catch continue;
        try files.append(a, .{ .path = name, .text = text });
    }
    return files.items;
}

pub fn runFmtCheck(a: Allocator, io: std.Io, zig_exe: []const u8, rep: *Report) !void {
    const r = try std.process.run(a, io, .{ .argv = &.{ zig_exe, "fmt", "--check", "src", "build.zig" } });
    if (!r.term.success()) {
        var it = std.mem.splitScalar(u8, r.stdout, '\n');
        var n: usize = 0;
        while (it.next()) |l| if (trim(l).len > 0) {
            rep.add(trim(l), 1, "zig fmt --check 报告需要格式化", .{});
            n += 1;
        };
        if (n == 0) rep.add("src", 1, "zig fmt --check 失败：{s}", .{trim(r.stderr)});
    }
}

pub const Env = struct {
    a: Allocator,
    io: std.Io,
    files: []const File,
    zig_exe: []const u8,
};

pub const check_ids = [_][]const u8{
    "AC-ARCH-001", "AC-PLAT-018", "AC-CONV-001", "AC-CONV-002", "AC-CONV-003", "AC-CONV-004",
    "AC-CONV-005", "AC-CONV-006", "AC-CONV-011", "AC-CONV-012", "AC-CONV-014", "AC-CONV-015",
    "AC-CONV-017", "AC-CONV-018", "AC-CONV-019", "AC-CONV-021", "AC-CONV-022", "AC-CONV-023",
    "AC-CONV-024", "AC-CONV-025", "AC-CONV-028", "AC-CONV-029", "AC-CONV-030",
};

/// 对真实仓库运行一条 AC 对应的全部扫描。
pub fn runCheck(env: Env, id: []const u8, rep: *Report) !void {
    const a = env.a;
    const f = env.files;
    const eq = std.mem.eql;
    if (eq(u8, id, "AC-ARCH-001")) {
        try scanDeps(a, f, rep);
        try scanSymbols(a, f, rep);
        try scanLayout(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-004")) {
        try scanDeps(a, f, rep);
        try scanSymbols(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-003")) {
        try scanLayout(a, f, rep);
    } else if (eq(u8, id, "AC-PLAT-018")) {
        try scanNoTouch(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-001")) {
        const bumps = try loadBumpHashes(a, env.io);
        const all = try loadCommits(a, env.io, null);
        var picked: List(Commit) = .empty;
        for (bumps) |h| for (all) |c| if (eq(u8, c.hash, h)) try picked.append(a, c);
        scanZigVersion(f, picked.items, rep);
    } else if (eq(u8, id, "AC-CONV-002")) {
        scanCiFmtStep(f, rep);
        try runFmtCheck(a, env.io, env.zig_exe, rep);
    } else if (eq(u8, id, "AC-CONV-005")) {
        try scanFileNames(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-006")) {
        try scanNaming(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-011")) {
        try scanOwnership(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-012")) {
        try scanErrors(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-014")) {
        try scanGlobalVars(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-015")) {
        try scanUsingnamespace(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-017")) {
        try scanThirdPartySource(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-018")) {
        try scanExternPlacement(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-019")) {
        try scanWin32Names(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-021")) {
        try scanDocComments(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-022")) {
        try scanLanguage(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-023")) {
        scanCommitSubjects(try loadCommits(a, env.io, 200), rep);
    } else if (eq(u8, id, "AC-CONV-024")) {
        scanCommitAcLines(f, try loadCommits(a, env.io, null), rep);
    } else if (eq(u8, id, "AC-CONV-025")) {
        scanCommitGranularity(try loadCommits(a, env.io, null), try loadBumpHashes(a, env.io), rep);
    } else if (eq(u8, id, "AC-CONV-028")) {
        try scanLoc(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-029")) {
        try scanNoBinaries(a, f, rep);
    } else if (eq(u8, id, "AC-CONV-030")) {
        try scanLicenses(a, f, rep);
    } else return error.UnknownCheck;
}

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    var zig_exe: []const u8 = build_options.zig_exe;
    var args = try init.minimal.args.iterateAllocator(a);
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--zig")) zig_exe = args.next() orelse zig_exe;
    }
    const files = try loadRepo(a, io);
    const env: Env = .{ .a = a, .io = io, .files = files, .zig_exe = zig_exe };
    var total: usize = 0;
    var failing: usize = 0;
    for (check_ids) |id| {
        var rep: Report = .{ .a = a };
        runCheck(env, id, &rep) catch |e| rep.add("check-code", 0, "检查自身出错：{t}", .{e});
        if (rep.items.items.len == 0) {
            std.debug.print("{s}: 通过\n", .{id});
            continue;
        }
        failing += 1;
        total += rep.items.items.len;
        std.debug.print("{s}: {d} 处违规\n", .{ id, rep.items.items.len });
        for (rep.items.items) |v| std.debug.print("  {s}:{d}: {s}\n", .{ v.path, v.line, v.msg });
    }
    std.debug.print("check-code: {d} 条 AC 有违规，共 {d} 处\n", .{ failing, total });
    if (failing > 0) std.process.exit(1);
}

// ---------------------------------------------------------------------------
// 测试：真实仓库（允许失败，违规清零前不接入 `zig build test`）与植入缺陷样本
// ---------------------------------------------------------------------------

fn expectClean(id: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = try loadRepo(a, std.testing.io);
    var rep: Report = .{ .a = a };
    try runCheck(.{ .a = a, .io = std.testing.io, .files = files, .zig_exe = build_options.zig_exe }, id, &rep);
    if (rep.items.items.len > 0) {
        std.debug.print("{s}: {d} 处违规\n", .{ id, rep.items.items.len });
        for (rep.items.items[0..@min(rep.items.items.len, 50)]) |v| std.debug.print("  {s}:{d}: {s}\n", .{ v.path, v.line, v.msg });
        return error.ViolationsFound;
    }
}

fn countViolations(comptime scan: anytype, files: []const File) !usize {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var rep: Report = .{ .a = arena.allocator() };
    try scan(arena.allocator(), files, &rep);
    return rep.items.items.len;
}

fn expectCount(comptime scan: anytype, files: []const File, want: usize) !void {
    try std.testing.expectEqual(want, try countViolations(scan, files));
}

// ---- 真实仓库 ----

test "AC-ARCH-001 导入检查：依赖方向、符号位置与模块布局" {
    try expectClean("AC-ARCH-001");
}
test "AC-PLAT-018 platform 不引用触摸/指针/手势消息" {
    try expectClean("AC-PLAT-018");
}
test "AC-CONV-001 Zig 版本固定且版本提交独立" {
    try expectClean("AC-CONV-001");
}
test "AC-CONV-002 zig fmt 检查与 CI 步骤" {
    try expectClean("AC-CONV-002");
}
test "AC-CONV-003 模块目录与入口约定" {
    try expectClean("AC-CONV-003");
}
test "AC-CONV-004 模块依赖图与外部库符号位置" {
    try expectClean("AC-CONV-004");
}
test "AC-CONV-005 目录与文件名为 snake_case" {
    try expectClean("AC-CONV-005");
}
test "AC-CONV-006 命名规则" {
    try expectClean("AC-CONV-006");
}
test "AC-CONV-011 公开 API 指针与切片参数写明所有权" {
    try expectClean("AC-CONV-011");
}
test "AC-CONV-012 无 anyerror 且控件函数不返回错误联合" {
    try expectClean("AC-CONV-012");
}
test "AC-CONV-014 无全局可变状态" {
    try expectClean("AC-CONV-014");
}
test "AC-CONV-015 无 usingnamespace" {
    try expectClean("AC-CONV-015");
}
test "AC-CONV-017 第三方源码 vendoring 与补丁登记" {
    try expectClean("AC-CONV-017");
}
test "AC-CONV-018 extern 与 @cImport 只在绑定文件" {
    try expectClean("AC-CONV-018");
}
test "AC-CONV-019 Win32 绑定保持原名" {
    try expectClean("AC-CONV-019");
}
test "AC-CONV-021 公开 API 文档注释含线程要求" {
    try expectClean("AC-CONV-021");
}
test "AC-CONV-022 注释为中文且标识符为英文" {
    try expectClean("AC-CONV-022");
}
test "AC-CONV-023 最近 200 个提交标题格式" {
    try expectClean("AC-CONV-023");
}
test "AC-CONV-024 实现类提交含 AC 行" {
    try expectClean("AC-CONV-024");
}
test "AC-CONV-025 提交粒度" {
    try expectClean("AC-CONV-025");
}
test "AC-CONV-028 src 代码行数不超过 30000" {
    try expectClean("AC-CONV-028");
}
test "AC-CONV-029 third_party 不含预编译二进制与包管理器产物" {
    try expectClean("AC-CONV-029");
}
test "AC-CONV-030 许可检查" {
    try expectClean("AC-CONV-030");
}

// ---- 植入缺陷样本：证明扫描能抓到违规，且合规样本不误报 ----

test "AC-ARCH-001 植入缺陷：反向依赖、core 外部导入、符号越界、顶层多余文件" {
    const bad = [_]File{
        .{ .path = "src/core.zig", .text = "const ui = @import(\"ui.zig\");\nconst t = std.time.Instant;\n" },
        .{ .path = "src/gfx.zig", .text = "const text = @import(\"text.zig\");\n" },
        .{ .path = "src/ui.zig", .text = "const widgets = @import(\"widgets.zig\");\nextern \"user32\" fn GetDC() void;\n" },
        .{ .path = "src/widgets.zig", .text = "const x = glfwInit();\nconst y = nvgBeginFrame;\n" },
        .{ .path = "src/stray.zig", .text = "" },
    };
    // core 导入 ui；core 引用 std.time.Instant；gfx 导入 text（同层反向）；ui 导入 widgets（上行）；
    // ui 的 Win32 extern；widgets 的 GLFW 与 NanoVG 符号；顶层 stray.zig。
    try expectCount(scanDeps, &bad, 4);
    try expectCount(scanSymbols, &bad, 3);
    try expectCount(scanLayout, &bad, 1);
    const good = [_]File{
        .{ .path = "src/core.zig", .text = "const std = @import(\"std\");\n" },
        .{ .path = "src/ui.zig", .text = "const core = @import(\"core.zig\");\n" },
        .{ .path = "src/gfx/nanovg.zig", .text = "const x = nvgBeginFrame;\n" },
        .{ .path = "src/gfx.zig", .text = "const n = @import(\"gfx/nanovg.zig\");\n" },
    };
    try expectCount(scanDeps, &good, 0);
    try expectCount(scanSymbols, &good, 0);
    try expectCount(scanLayout, &good, 0);
}

test "AC-PLAT-018 植入缺陷：触摸与手势消息引用" {
    const bad = [_]File{
        .{ .path = "src/platform/win32.zig", .text = "const a = WM_TOUCH;\nfn f() void { RegisterTouchWindow(); }\n// WM_GESTURE 只在注释里\n" },
        .{ .path = "src/uia.zig", .text = "const b = WM_POINTERDOWN;\n" },
        .{ .path = "src/ui.zig", .text = "const c = WM_TOUCH;\n" },
    };
    try expectCount(scanNoTouch, &bad, 3);
}

test "AC-CONV-001 植入缺陷：版本不符与混合改动的版本提交" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var rep: Report = .{ .a = arena.allocator() };
    const files = [_]File{
        .{ .path = "build.zig.zon", .text = ".{ .minimum_zig_version = \"0.16.0\" }" },
        .{ .path = ".github/workflows/ci.yml", .text = "      - run: curl https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz\n" },
    };
    const commits = [_]Commit{.{ .hash = "abcdef0123", .subject = "chore: x", .body = "", .files = &.{ "build.zig.zon", "src/core.zig" } }};
    scanZigVersion(&files, &commits, &rep);
    try std.testing.expectEqual(@as(usize, 1 + 2 + 1), rep.items.items.len);
    var rep2: Report = .{ .a = arena.allocator() };
    const good = [_]File{
        .{ .path = "build.zig.zon", .text = ".{ .minimum_zig_version = \"0.17.1\" }" },
        .{ .path = ".github/workflows/ci.yml", .text = "      - run: curl https://ziglang.org/download/0.17.1/zig-x86_64-linux-0.17.1.tar.xz\n" },
    };
    const good_commit = [_]Commit{.{ .hash = "abcdef0123", .subject = "chore: x", .body = "", .files = &.{ "build.zig.zon", ".github/workflows/ci.yml" } }};
    scanZigVersion(&good, &good_commit, &rep2);
    try std.testing.expectEqual(@as(usize, 0), rep2.items.items.len);
}

test "AC-CONV-002 植入缺陷：CI 缺少 fmt 步骤、失败不致任务失败" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var rep: Report = .{ .a = arena.allocator() };
    scanCiFmtStep(&.{.{ .path = ".github/workflows/ci.yml", .text = "steps:\n  - name: build\n    run: zig build\n" }}, &rep);
    try std.testing.expectEqual(@as(usize, 1), rep.items.items.len);
    var rep2: Report = .{ .a = arena.allocator() };
    scanCiFmtStep(&.{.{ .path = ".github/workflows/ci.yml", .text = "steps:\n  - name: fmt\n    continue-on-error: true\n    run: zig fmt --check src build.zig\n" }}, &rep2);
    try std.testing.expectEqual(@as(usize, 1), rep2.items.items.len);
    var rep3: Report = .{ .a = arena.allocator() };
    scanCiFmtStep(&.{.{ .path = ".github/workflows/ci.yml", .text = "steps:\n  - name: fmt\n    run: zig fmt --check src tests build.zig\n" }}, &rep3);
    try std.testing.expectEqual(@as(usize, 0), rep3.items.items.len);
}

test "AC-CONV-003 植入缺陷：缺入口、双入口、顶层多余文件、跨模块导入非入口" {
    const bad = [_]File{
        .{ .path = "src/foo/a.zig", .text = "" }, // foo 无入口且不在模块表
        .{ .path = "src/gfx.zig", .text = "" },
        .{ .path = "src/gfx/root.zig", .text = "" }, // 双入口
        .{ .path = "src/gfx/impl.zig", .text = "" },
        .{ .path = "src/extra.zig", .text = "" }, // 顶层多余
        .{ .path = "src/ui.zig", .text = "const i = @import(\"gfx/impl.zig\");\n" }, // 非入口
    };
    // foo：不在模块表 + 缺入口；gfx：双入口；extra.zig；ui 导入 gfx/impl.zig。
    try expectCount(scanLayout, &bad, 5);
}

test "AC-CONV-004 植入缺陷：依赖图与符号位置" {
    const bad = [_]File{
        .{ .path = "src/theme.zig", .text = "const ui = @import(\"ui.zig\");\n" },
        .{ .path = "src/text.zig", .text = "const x = GL_TEXTURE_2D;\n" },
    };
    try expectCount(scanDeps, &bad, 1);
    try expectCount(scanSymbols, &bad, 1);
}

test "AC-CONV-005 植入缺陷：非 snake_case 名字" {
    const bad = [_]File{
        .{ .path = "src/Core.zig" },
        .{ .path = "src/my-dir/a.zig" },
        .{ .path = "tests/golden/basic.replay" },
        .{ .path = "tests/all.zig" },
    };
    // Core.zig、my-dir（目录只报一次，a.zig 合规）、basic.replay。
    try expectCount(scanFileNames, &bad, 3);
}

test "AC-CONV-006 植入缺陷：类型、函数、枚举成员、常量命名" {
    const src =
        \\const my_type = struct {};
        \\const Color = enum { Red, green_one };
        \\fn Do_it() void {}
        \\fn Generic(comptime T: type) type { return T; }
        \\pub const MaxCount = 5;
        \\pub const Alias = core.Vec2;
        \\const ok_name = 3;
        \\fn good() void {}
    ;
    // my_type；Red；Do_it；MaxCount。
    try expectCount(scanNaming, &.{.{ .path = "src/ui.zig", .text = src }}, 4);
    // Win32 绑定文件豁免常量与类型名。
    try expectCount(scanNaming, &.{.{ .path = "src/platform/win32_bindings.zig", .text = "pub const WM_PAINT = 15;\npub const RECT = extern struct {};\n" }}, 0);
}

test "AC-CONV-011 植入缺陷：未写所有权的指针与切片参数" {
    const src =
        \\/// 无所有权说明。
        \\pub fn bad(self: *Foo, name: []const u8) void {}
        \\/// 框架复制 name。
        \\pub fn ok(self: *Foo, name: []const u8) void {}
        \\pub fn noDoc(p: *u32) void {}
        \\fn private(p: *u32) void {}
        \\pub fn byValue(x: u32) void {}
    ;
    try expectCount(scanOwnership, &.{.{ .path = "src/ui.zig", .text = src }}, 2);
}

test "AC-CONV-012 植入缺陷：anyerror 与控件函数的错误联合" {
    const src =
        \\const E = anyerror;
        \\// 注释中的 anyerror 不计
        \\pub fn button(ui: *Ui, src: std.builtin.SourceLocation, opts: Options) !ButtonResult {}
        \\pub fn label(ui: *Ui, src: std.builtin.SourceLocation, opts: Options) LabelResult {}
    ;
    try expectCount(scanErrors, &.{.{ .path = "src/widgets.zig", .text = src }}, 2);
}

test "AC-CONV-014 植入缺陷：容器级 var" {
    const src =
        \\var counter: u32 = 0;
        \\pub threadlocal var tl: u32 = 0;
        \\const S = struct {
        \\    var inner: u32 = 0;
        \\    fn f() void {
        \\        var local: u32 = 0;
        \\        _ = &local;
        \\    }
        \\};
    ;
    try expectCount(scanGlobalVars, &.{.{ .path = "src/ui.zig", .text = src }}, 3);
    try expectCount(scanGlobalVars, &.{.{ .path = "src/core.zig", .text = src }}, 0); // 日志接收器与统计计数器所在文件
}

test "AC-CONV-015 植入缺陷：usingnamespace" {
    try expectCount(scanUsingnamespace, &.{
        .{ .path = "src/a.zig", .text = "pub usingnamespace @import(\"x.zig\");\n" },
        .{ .path = "tests/b.zig", .text = "usingnamespace foo;\n// usingnamespace 在注释里\n" },
    }, 2);
}

test "AC-CONV-017 植入缺陷：顶层文件、非 C 源码、缺校验和、未登记的差异" {
    const patched = "int x;\n";
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("int original;\n", &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    const patches = try std.fmt.allocPrint(std.testing.allocator, "# lib\nUpstream: x v1\n{s}  a.c\n", .{hex});
    defer std.testing.allocator.free(patches);
    const bad = [_]File{
        .{ .path = "third_party/loose.c" },
        .{ .path = "third_party/lib/a.c", .text = patched }, // 与记录的校验和不符且未登记
        .{ .path = "third_party/lib/b.c", .text = "" }, // 无校验和
        .{ .path = "third_party/lib/c.zig", .text = "" }, // 非 C 源码
        .{ .path = "third_party/lib/PATCHES.md", .text = patches },
    };
    try expectCount(scanThirdPartySource, &bad, 4);
}

test "AC-CONV-018 植入缺陷：绑定文件之外的外部声明" {
    const src =
        \\extern "user32" fn GetDC() void;
        \\const c = @cImport({});
        \\const L = extern struct { a: u32 };
    ;
    try expectCount(scanExternPlacement, &.{.{ .path = "src/ui.zig", .text = src }}, 2);
    try expectCount(scanExternPlacement, &.{.{ .path = "src/platform/win32_bindings.zig", .text = src }}, 0);
}

test "AC-CONV-019 植入缺陷：Win32 改名与绑定文件中的包装函数" {
    const src =
        \\pub extern "user32" fn createWindow() void;
        \\pub extern "user32" fn CreateWindowExW() void;
        \\pub const wm_paint = 15;
        \\pub const WM_PAINT = 15;
        \\pub const hwnd = ?*anyopaque;
        \\pub const HWND = ?*anyopaque;
        \\pub fn wrapper() void {}
    ;
    // createWindow、wm_paint、hwnd、wrapper。
    try expectCount(scanWin32Names, &.{.{ .path = "src/platform/win32_bindings.zig", .text = src }}, 4);
}

test "AC-CONV-021 植入缺陷：缺文档、缺线程要求、缺 REQ、缺所有权" {
    const docs_file = File{ .path = "docs/x.md", .text = "**REQ-X-001**　`beginSpecial` 必须有注释。\n" };
    const src =
        \\pub fn nodoc() void {}
        \\/// 没有线程要求。
        \\pub fn nothread() void {}
        \\/// 界面线程。
        \\pub fn beginSpecial() void {}
        \\/// 界面线程。
        \\pub fn withPtr(p: []const u8) void {}
        \\/// 界面线程。REQ-X-001。框架复制 p。
        \\pub fn fine(p: []const u8) void {}
    ;
    const files = [_]File{ docs_file, .{ .path = "src/ui.zig", .text = src } };
    try expectCount(scanDocComments, &files, 4);
}

test "AC-CONV-022 植入缺陷：英文注释与中文标识符" {
    const src =
        \\// 中文注释
        \\// english only
        \\/// 文档 ok
        \\///
        \\const 变量 = 1;
        \\const s = "中文字符串可以";
    ;
    try expectCount(scanLanguage, &.{.{ .path = "src/ui.zig", .text = src }}, 2);
}

test "AC-CONV-023 植入缺陷：不合格的提交标题" {
    try std.testing.expect(subjectOk("feat(core): 新增哈希"));
    try std.testing.expect(subjectOk("fix!: 修复崩溃"));
    try std.testing.expect(!subjectOk("feat: add hash"));
    try std.testing.expect(!subjectOk("update stuff 中文"));
    try std.testing.expect(!subjectOk("feat():中文"));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var rep: Report = .{ .a = arena.allocator() };
    scanCommitSubjects(&.{
        .{ .hash = "aaaaaaaa", .subject = "feat: english", .body = "", .files = &.{} },
        .{ .hash = "bbbbbbbb", .subject = "fix: 修复", .body = "", .files = &.{} },
    }, &rep);
    try std.testing.expectEqual(@as(usize, 1), rep.items.items.len);
}

test "AC-CONV-024 植入缺陷：实现类提交缺 AC 行或引用不存在的 AC" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var rep: Report = .{ .a = arena.allocator() };
    const files = [_]File{.{ .path = "docs/acceptance/M0.md", .text = "| AC-CORE-001 | x |\n" }};
    scanCommitAcLines(&files, &.{
        .{ .hash = "aaaaaaaa", .subject = "feat: 无 AC", .body = "正文\n", .files = &.{"src/core.zig"} },
        .{ .hash = "bbbbbbbb", .subject = "feat: 假 AC", .body = "AC: AC-CORE-999\n", .files = &.{"src/core.zig"} },
        .{ .hash = "cccccccc", .subject = "feat: 好", .body = "AC: AC-CORE-001\n", .files = &.{"src/core.zig"} },
        .{ .hash = "dddddddd", .subject = "docs: 非实现", .body = "", .files = &.{"docs/x.md"} },
    }, &rep);
    try std.testing.expectEqual(@as(usize, 2), rep.items.items.len);
}

test "AC-CONV-025 植入缺陷：混合提交" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var rep: Report = .{ .a = arena.allocator() };
    const bumps = [_][]const u8{"eeeeeeee"};
    scanCommitGranularity(&.{
        .{ .hash = "aaaaaaaa", .subject = "x", .body = "", .files = &.{ "docs/a.md", "src/a.zig" } },
        .{ .hash = "bbbbbbbb", .subject = "x", .body = "", .files = &.{ "tests/golden/a.png", "src/a.zig" } },
        .{ .hash = "cccccccc", .subject = "x", .body = "", .files = &.{ "tests/golden/a.png", "tests/golden/b.png" } },
        .{ .hash = "eeeeeeee", .subject = "x", .body = "", .files = &.{ "build.zig.zon", "build.zig" } },
    }, &bumps, &rep);
    try std.testing.expectEqual(@as(usize, 3), rep.items.items.len);
}

test "AC-CONV-028 植入缺陷：超过行数上限且无精简计划" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const line = "const x = 1;\n";
    const big = try a.alloc(u8, line.len * (loc_limit + 1));
    for (0..loc_limit + 1) |i| @memcpy(big[i * line.len ..][0..line.len], line);
    const text = try std.mem.concat(a, u8, &.{ big, "\n// 注释不计\n" });
    var rep: Report = .{ .a = a };
    try scanLoc(a, &.{.{ .path = "src/ui.zig", .text = text }}, &rep);
    try std.testing.expectEqual(@as(usize, 1), rep.items.items.len);
    try std.testing.expectEqual(loc_limit + 1, try countCodeLines(a, &.{.{ .path = "src/ui.zig", .text = text }}));
    var rep2: Report = .{ .a = a };
    try scanLoc(a, &.{ .{ .path = "src/ui.zig", .text = text }, .{ .path = "docs/14-roadmap.md", .text = "精简计划：拆分" } }, &rep2);
    try std.testing.expectEqual(@as(usize, 0), rep2.items.items.len);
}

test "AC-CONV-029 植入缺陷：预编译二进制、包管理器产物与 zon 依赖" {
    const bad = [_]File{
        .{ .path = "third_party/lib/x.lib" },
        .{ .path = "third_party/lib/node_modules/a.js" },
        .{ .path = "third_party/lib/x.c" },
        .{ .path = "build.zig.zon", .text = ".{ .dependencies = .{ .foo = .{ .url = \"x\" } } }" },
    };
    try expectCount(scanNoBinaries, &bad, 3);
}

test "AC-CONV-030 植入缺陷：LICENSE、登记缺失、SPDX、OFL、补丁标注" {
    const bad = [_]File{
        .{ .path = "LICENSE", .text = "MIT License\n\nCopyright (c) 2025 someone\n" },
        .{ .path = "THIRD_PARTY_NOTICES.md", .text = "## A\n- 路径: third_party/a\n- 上游地址: u\n- 版本: 1\n- SPDX: GPL-3.0\n- 许可文本: third_party/a/LICENSE\n" ++
            "## F\n- 路径: third_party/ghost\n- 上游地址: u\n- 版本: 1\n- SPDX: OFL-1.1\n- 许可文本: third_party/a/LICENSE\n" },
        .{ .path = "third_party/a/LICENSE", .text = "x" },
        .{ .path = "third_party/a/PATCHES.md", .text = "# a\n## 补丁\n- 目的: x\n- 文件: a.h\n- 上游版本: 1\n" },
        .{ .path = "third_party/a/a.h", .text = "int x;\n" },
        .{ .path = "third_party/b/b.c", .text = "" }, // 无登记、无许可文本
    };
    // LICENSE；A 的 SPDX 不在清单；F 路径不存在 + OFL 非字体；b 无登记；b 缺许可文本；a.h 缺标注（共 7 处）。
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var rep: Report = .{ .a = arena.allocator() };
    try scanLicenses(arena.allocator(), &bad, &rep);
    try std.testing.expectEqual(@as(usize, 7), rep.items.items.len);
}

test "AC-CONV-030 合规样本不误报" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const good = [_]File{
        .{ .path = "LICENSE", .text = "\n" ++ mit_text ++ "\n\n" },
        .{ .path = "THIRD_PARTY_NOTICES.md", .text = "## A\n- 路径: third_party/a\n- 上游地址: u\n- 版本: 1\n- SPDX: MIT OR Unlicense\n- 许可文本: third_party/a/LICENSE\n" ++
            "## 字体\n- 路径: tests/fonts/f.ttf\n- 上游地址: u\n- 版本: 1\n- SPDX: OFL-1.1\n- 许可文本: tests/fonts/f-OFL.txt\n- 来源字体: F\n- 子集化范围: ASCII\n" },
        .{ .path = "third_party/a/LICENSE", .text = "x" },
        .{ .path = "tests/fonts/f.ttf" },
        .{ .path = "tests/fonts/f-OFL.txt", .text = "x" },
    };
    var rep: Report = .{ .a = a };
    try scanLicenses(a, &good, &rep);
    try std.testing.expectEqual(@as(usize, 0), rep.items.items.len);
}
