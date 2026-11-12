//! 文档一致性检查（REQ-TEST-024、REQ-TEST-025、REQ-TEST-026）。
//!
//! 用法：`check_docs [--root <目录>]`。目录缺省为当前目录，其下需有 `docs/`；
//! 追溯部分扫描该目录下的 `tests/`、`src/`、`tools/`。
//! 所有失败项以 `文件:行: 信息` 输出，任一失败即以非零码退出。
//!
//! 检查项：
//!   1. 相对链接可达
//!   2. REQ/AC 编号唯一、域内无跳号
//!   3. 每条 REQ 被至少一条 AC 的“覆盖：”引用
//!   4. 每条 AC 在且仅在一个里程碑清单主表中；人工项执行记录与主表一致
//!   5. 控件文档章节齐全
//!   6. 09 的颜色/度量/时长令牌与代码默认主题一致
//!   7. 测试名追溯（REQ-TEST-025 三条）

const std = @import("std");
const Allocator = std.mem.Allocator;
const nano_gui = @import("nano_gui");
const theme = nano_gui.theme;

const Doc = struct { path: []const u8, text: []const u8 };

const Ctx = struct {
    a: Allocator,
    io: std.Io,
    root: std.Io.Dir,
    failures: usize = 0,
    warnings: usize = 0,

    fn fail(self: *Ctx, path: []const u8, line: usize, comptime fmt: []const u8, args: anytype) void {
        self.failures += 1;
        std.debug.print("{s}:{d}: ", .{ path, line });
        std.debug.print(fmt ++ "\n", args);
    }
};

/// 一条已定义的 REQ 或 AC。
const Def = struct {
    id: []const u8,
    is_ac: bool,
    domain_key: []const u8, // 去掉末尾序号后的前缀，如 REQ-W-BUTTON
    num: u32,
    path: []const u8,
    line: usize,
    abandoned: bool,
};

const Parsed = struct { id: []const u8, domain_key: []const u8, num: u32, is_ac: bool };

/// 解析 `REQ-<域>-nnn` / `AC-<域>-nnn`（00 第 3 节）。tok 须是完整记号，不合格返回 null。
fn parseId(tok: []const u8) ?Parsed {
    const is_ac = std.mem.startsWith(u8, tok, "AC-");
    if (!is_ac and !std.mem.startsWith(u8, tok, "REQ-")) return null;
    const last = std.mem.lastIndexOfScalar(u8, tok, '-') orelse return null;
    const num_s = tok[last + 1 ..];
    if (num_s.len != 3) return null;
    const num = std.fmt.parseInt(u32, num_s, 10) catch return null;
    const first = std.mem.indexOfScalar(u8, tok, '-').?;
    if (last <= first + 1) return null;
    const domain = tok[first + 1 .. last];
    var segs = std.mem.splitScalar(u8, domain, '-');
    while (segs.next()) |s| {
        if (s.len == 0) return null;
        for (s) |c| if (!std.ascii.isUpper(c)) return null;
    }
    return .{ .id = tok, .domain_key = tok[0..last], .num = num, .is_ac = is_ac };
}

fn isTokChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-';
}

/// 从 s[at..] 取出由字母数字与连字符组成的记号，去掉末尾连字符。
fn takeTok(s: []const u8, at: usize) []const u8 {
    var e = at;
    while (e < s.len and isTokChar(s[e])) e += 1;
    while (e > at and s[e - 1] == '-') e -= 1;
    return s[at..e];
}

fn lineAt(text: []const u8, offset: usize) usize {
    var n: usize = 1;
    for (text[0..@min(offset, text.len)]) |c| {
        if (c == '\n') n += 1;
    }
    return n;
}

fn splitCells(a: Allocator, line: []const u8) ![][]const u8 {
    var s = std.mem.trim(u8, line, " \t\r");
    if (std.mem.startsWith(u8, s, "|")) s = s[1..];
    if (std.mem.endsWith(u8, s, "|")) s = s[0 .. s.len - 1];
    var out = std.ArrayListUnmanaged([]const u8).empty;
    var it = std.mem.splitScalar(u8, s, '|');
    while (it.next()) |c| try out.append(a, std.mem.trim(u8, c, " \t"));
    return out.items;
}

fn stripTicks(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, "` ");
}

fn lessStr(_: void, x: Doc, y: Doc) bool {
    return std.mem.lessThan(u8, x.path, y.path);
}

fn readDocs(ctx: *Ctx) ![]Doc {
    const a = ctx.a;
    const io = ctx.io;
    var out = std.ArrayListUnmanaged(Doc).empty;
    const docs_dir = ctx.root.openDir(io, "docs", .{ .iterate = true }) catch |e| {
        std.debug.print("docs:1: 无法打开 docs/: {t}\n", .{e});
        std.process.exit(1);
    };
    var walker = try docs_dir.walk(a);
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".md")) continue;
        const path = try std.fs.path.join(a, &.{ "docs", entry.path });
        const text = entry.dir.readFileAlloc(io, entry.basename, a, .unlimited) catch |e| {
            ctx.fail(path, 1, "无法读取: {t}", .{e});
            continue;
        };
        try out.append(a, .{ .path = path, .text = text });
    }
    std.mem.sort(Doc, out.items, {}, lessStr);
    return out.items;
}

// ---------------------------------------------------------------------------
// 1) 相对链接
// ---------------------------------------------------------------------------

fn checkLinks(ctx: *Ctx, docs: []const Doc) !void {
    for (docs) |d| {
        var i: usize = 0;
        while (std.mem.indexOfPos(u8, d.text, i, "](")) |open| {
            const start = open + 2;
            const close = std.mem.indexOfScalarPos(u8, d.text, start, ')') orelse break;
            const target = d.text[start..close];
            i = close + 1;
            if (std.mem.startsWith(u8, target, "http://") or std.mem.startsWith(u8, target, "https://") or
                std.mem.startsWith(u8, target, "mailto:") or std.mem.startsWith(u8, target, "#")) continue;
            const hash = std.mem.indexOfScalar(u8, target, '#') orelse target.len;
            const rel = target[0..hash];
            if (rel.len == 0) continue;
            const dirname = std.fs.path.dirname(d.path) orelse ".";
            const resolved = try std.fs.path.join(ctx.a, &.{ dirname, rel });
            ctx.root.access(ctx.io, resolved, .{}) catch {
                ctx.fail(d.path, lineAt(d.text, open), "断链 {s}", .{target});
            };
        }
    }
}

// ---------------------------------------------------------------------------
// 2) 编号定义：唯一、无跳号
// ---------------------------------------------------------------------------

fn collectDefs(ctx: *Ctx, docs: []const Doc) ![]Def {
    var defs = std.ArrayListUnmanaged(Def).empty;
    var seen = std.StringHashMapUnmanaged(Def).empty;
    for (docs) |d| {
        var it = std.mem.splitScalar(u8, d.text, '\n');
        var line: usize = 0;
        while (it.next()) |l| {
            line += 1;
            const trimmed = std.mem.trimStart(u8, l, " \t");
            if (!std.mem.startsWith(u8, trimmed, "**")) continue;
            const end = std.mem.indexOfPos(u8, trimmed, 2, "**") orelse continue;
            const p = parseId(trimmed[2..end]) orelse continue;
            const def = Def{
                .id = p.id,
                .is_ac = p.is_ac,
                .domain_key = p.domain_key,
                .num = p.num,
                .path = d.path,
                .line = line,
                .abandoned = isAbandonedMark(trimmed[end + 2 ..]),
            };
            if (seen.get(p.id)) |first| {
                ctx.fail(d.path, line, "重复的{s}条款 {s}（首次定义于 {s}:{d}）", .{ if (p.is_ac) "验收" else "规范", p.id, first.path, first.line });
                continue;
            }
            try seen.put(ctx.a, p.id, def);
            try defs.append(ctx.a, def);
        }
    }

    // 域内无跳号：同一 domain_key 的序号必须覆盖 1..max。
    var by_domain = std.StringHashMapUnmanaged(std.ArrayListUnmanaged(Def)).empty;
    for (defs.items) |def| {
        const gop = try by_domain.getOrPut(ctx.a, def.domain_key);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        try gop.value_ptr.append(ctx.a, def);
    }
    var dit = by_domain.iterator();
    while (dit.next()) |e| {
        const list = e.value_ptr.items;
        std.mem.sort(Def, list, {}, struct {
            fn lt(_: void, x: Def, y: Def) bool {
                return x.num < y.num;
            }
        }.lt);
        var expect: u32 = 1;
        for (list) |def| {
            if (expect < def.num) {
                if (def.num - expect == 1) {
                    ctx.fail(def.path, def.line, "{s} 跳号：缺 {s}-{d:0>3}（废弃条款应保留编号）", .{ def.domain_key, def.domain_key, expect });
                } else {
                    ctx.fail(def.path, def.line, "{s} 跳号：缺 {s}-{d:0>3} 至 {s}-{d:0>3}（废弃条款应保留编号）", .{ def.domain_key, def.domain_key, expect, def.domain_key, def.num - 1 });
                }
            }
            expect = def.num + 1;
        }
    }
    return defs.items;
}

// ---------------------------------------------------------------------------
// 3) REQ 被 AC 覆盖
// ---------------------------------------------------------------------------

fn checkCoverage(ctx: *Ctx, docs: []const Doc, defs: []const Def) !void {
    var covered = std.StringHashMapUnmanaged(void).empty;
    var req_set = std.StringHashMapUnmanaged(void).empty;
    for (defs) |def| {
        if (!def.is_ac) try req_set.put(ctx.a, def.id, {});
    }
    for (docs) |d| {
        var it = std.mem.splitScalar(u8, d.text, '\n');
        var line: usize = 0;
        while (it.next()) |l| {
            line += 1;
            const t = std.mem.trimStart(u8, l, " \t");
            if (!std.mem.startsWith(u8, t, "**AC-")) continue;
            const mark = std.mem.indexOf(u8, t, "覆盖：") orelse continue;
            var seg = t[mark + "覆盖：".len ..];
            if (std.mem.indexOf(u8, seg, "。")) |e| seg = seg[0..e];
            var pos: usize = 0;
            while (std.mem.indexOfPos(u8, seg, pos, "REQ-")) |at| {
                const tok = takeTok(seg, at);
                try covered.put(ctx.a, tok, {});
                if (!req_set.contains(tok)) ctx.fail(d.path, line, "“覆盖：”引用了未定义的规范条款“{s}”", .{tok});
                pos = at + @max(tok.len, 4);
            }
        }
    }
    for (defs) |def| {
        if (def.is_ac or def.abandoned) continue;
        if (!covered.contains(def.id)) ctx.fail(def.path, def.line, "规范条款未被任何 AC 的“覆盖：”引用: {s}", .{def.id});
    }
}

// ---------------------------------------------------------------------------
// 4) 里程碑清单
// ---------------------------------------------------------------------------

/// 结果列取值：通过 / 未执行 / 不通过（原因） / 阻塞（原因）；allow_bare 时（人工记录表）也接受不带原因的“不通过”“阻塞”。
fn validResult(r: []const u8, allow_bare: bool) bool {
    if (std.mem.eql(u8, r, "通过") or std.mem.eql(u8, r, "未执行")) return true;
    inline for (.{ "不通过", "阻塞" }) |k| {
        if (allow_bare and std.mem.eql(u8, r, k)) return true;
        if (std.mem.startsWith(u8, r, k ++ "（") and std.mem.endsWith(u8, r, "）") and r.len > (k ++ "（）").len) return true;
    }
    return false;
}

const methods = [_][]const u8{ "单元", "金图", "回放", "计量", "人工" };

const Row = struct {
    id: []const u8,
    method: []const u8,
    result: []const u8,
    path: []const u8,
    line: usize,
};

const Record = struct {
    id: []const u8,
    cells: [][]const u8, // 不含首列条款号
    path: []const u8,
    line: usize,
};

const Milestone = struct {
    name: []const u8,
    rows: []Row,
};

fn checkMilestones(ctx: *Ctx, docs: []const Doc, defs: []const Def) ![]Milestone {
    var ms = std.ArrayListUnmanaged(Milestone).empty;
    var counts = std.StringHashMapUnmanaged(std.ArrayListUnmanaged(Row)).empty;
    var def_set = std.StringHashMapUnmanaged(Def).empty;
    for (defs) |d| try def_set.put(ctx.a, d.id, d);

    for (docs) |d| {
        if (!std.mem.startsWith(u8, d.path, "docs/acceptance/")) continue;
        const base = std.fs.path.basename(d.path);
        if (!std.mem.endsWith(u8, base, ".md")) continue;
        const stem = base[0 .. base.len - 3];

        var rows = std.ArrayListUnmanaged(Row).empty;
        var records = std.ArrayListUnmanaged(Record).empty;
        var in_manual = false;
        var it = std.mem.splitScalar(u8, d.text, '\n');
        var line: usize = 0;
        while (it.next()) |l| {
            line += 1;
            if (std.mem.startsWith(u8, l, "## ")) {
                in_manual = std.mem.indexOf(u8, l, "人工项执行记录") != null;
                continue;
            }
            const t = std.mem.trimStart(u8, l, " \t");
            if (!std.mem.startsWith(u8, t, "| AC-")) continue;
            const cells = try splitCells(ctx.a, t);
            const id = cells[0];
            if (in_manual) {
                if (cells.len != 7) {
                    ctx.fail(d.path, line, "人工项执行记录行应有 7 列（条款 + 六个字段），实际 {d}", .{cells.len});
                    continue;
                }
                if (!validResult(cells[5], true)) ctx.fail(d.path, line, "{s} 执行记录的结果“{s}”不在 通过/不通过/阻塞/未执行 之内", .{ id, cells[5] });
                try records.append(ctx.a, .{ .id = id, .cells = cells[1..], .path = d.path, .line = line });
            } else {
                if (cells.len < 4) {
                    ctx.fail(d.path, line, "主表行列数不足（需 条款/方式/摘要/结果）", .{});
                    continue;
                }
                const method = cells[1];
                var ok = false;
                for (methods) |m| {
                    if (std.mem.eql(u8, m, method)) ok = true;
                }
                if (!ok) ctx.fail(d.path, line, "{s} 的方式“{s}”不在 单元/金图/回放/计量/人工 之内", .{ id, method });
                if (!validResult(cells[cells.len - 1], false)) ctx.fail(d.path, line, "{s} 的结果“{s}”不在 通过/不通过（原因）/阻塞（原因）/未执行 之内", .{ id, cells[cells.len - 1] });
                const row = Row{ .id = id, .method = method, .result = cells[cells.len - 1], .path = d.path, .line = line };
                try rows.append(ctx.a, row);
                const gop = try counts.getOrPut(ctx.a, id);
                if (!gop.found_existing) gop.value_ptr.* = .empty;
                try gop.value_ptr.append(ctx.a, row);
                if (!def_set.contains(id)) ctx.fail(d.path, line, "清单中的 {s} 在文档中没有定义", .{id});
            }
        }

        // 人工项执行记录与主表人工 AC 一一对应（AC-TEST-022）
        for (rows.items) |r| {
            if (!std.mem.eql(u8, r.method, "人工")) continue;
            var n: usize = 0;
            var rec: ?Record = null;
            for (records.items) |x| {
                if (std.mem.eql(u8, x.id, r.id)) {
                    n += 1;
                    rec = x;
                }
            }
            if (n != 1) {
                ctx.fail(r.path, r.line, "人工 AC {s} 在“人工项执行记录”中应恰有一行，实际 {d} 行", .{ r.id, n });
                continue;
            }
            const x = rec.?;
            const passed = std.mem.eql(u8, r.result, "通过");
            if (passed) {
                // 六个字段：执行人、日期、Windows 版本、缩放、结果、备注（无备注写“无”）
                const names = [_][]const u8{ "执行人", "执行日期", "Windows 版本", "显示缩放", "结果", "备注" };
                for (names, 0..) |nm, i| {
                    if (x.cells[i].len == 0) ctx.fail(x.path, x.line, "{s} 结果为通过但执行记录缺“{s}”", .{ r.id, nm });
                }
            }
            if (!std.mem.startsWith(u8, x.cells[4], r.result) and !std.mem.startsWith(u8, r.result, x.cells[4])) {
                ctx.fail(x.path, x.line, "{s} 执行记录结果“{s}”与主表结果“{s}”不一致", .{ r.id, x.cells[4], r.result });
            }
        }
        for (records.items) |x| {
            var is_manual = false;
            for (rows.items) |r| {
                if (std.mem.eql(u8, r.id, x.id) and std.mem.eql(u8, r.method, "人工")) is_manual = true;
            }
            if (!is_manual) ctx.fail(x.path, x.line, "人工项执行记录含非人工 AC（或不在本清单主表）: {s}", .{x.id});
        }

        try ms.append(ctx.a, .{ .name = stem, .rows = rows.items });
    }

    // 每条 AC 在且仅在一个里程碑主表中
    for (defs) |def| {
        if (!def.is_ac) continue;
        const list = counts.get(def.id);
        const n = if (list) |l| l.items.len else 0;
        if (n == 0) {
            ctx.fail(def.path, def.line, "{s} 未归入任何里程碑清单主表", .{def.id});
        } else if (n > 1) {
            for (list.?.items) |r| ctx.fail(r.path, r.line, "{s} 出现在 {d} 个里程碑主表行中（应恰好 1）", .{ def.id, n });
        }
    }
    std.mem.sort(Milestone, ms.items, {}, struct {
        fn lt(_: void, x: Milestone, y: Milestone) bool {
            return std.mem.lessThan(u8, x.name, y.name);
        }
    }.lt);
    return ms.items;
}

// ---------------------------------------------------------------------------
// 5) 控件文档章节
// ---------------------------------------------------------------------------

fn checkWidgets(ctx: *Ctx, docs: []const Doc) !void {
    var tmpl: ?Doc = null;
    for (docs) |d| {
        if (std.mem.eql(u8, d.path, "docs/10-widgets/_template.md")) tmpl = d;
    }
    const t = tmpl orelse {
        ctx.fail("docs/10-widgets/_template.md", 1, "缺少控件文档模板", .{});
        return;
    };
    var heads = std.ArrayListUnmanaged([]const u8).empty;
    var in_code = false;
    var it = std.mem.splitScalar(u8, t.text, '\n');
    while (it.next()) |l| {
        if (std.mem.startsWith(u8, l, "```")) in_code = !in_code;
        if (in_code) continue;
        // 章节标题形如 "## 1. 用途"
        if (std.mem.startsWith(u8, l, "## ") and std.mem.trim(u8, l[3..], " \t\r").len > 0) {
            try heads.append(ctx.a, std.mem.trimEnd(u8, l, " \t\r"));
        }
    }
    if (heads.items.len == 0) {
        ctx.fail(t.path, 1, "未能从模板解析出任何章节标题", .{});
        return;
    }
    for (docs) |d| {
        if (!std.mem.startsWith(u8, d.path, "docs/10-widgets/")) continue;
        if (std.mem.eql(u8, d.path, t.path)) continue;
        var found = try ctx.a.alloc(bool, heads.items.len);
        @memset(found, false);
        var dit = std.mem.splitScalar(u8, d.text, '\n');
        var dcode = false;
        while (dit.next()) |l| {
            if (std.mem.startsWith(u8, l, "```")) dcode = !dcode;
            if (dcode) continue;
            const lt = std.mem.trimEnd(u8, l, " \t\r");
            for (heads.items, 0..) |h, i| {
                if (std.mem.eql(u8, h, lt)) found[i] = true;
            }
        }
        for (heads.items, 0..) |h, i| {
            if (!found[i]) ctx.fail(d.path, 1, "缺少模板章节“{s}”", .{h});
        }
    }
}

// ---------------------------------------------------------------------------
// 6) 令牌一致性（09 的 REQ-THEME-007 / REQ-THEME-011 / 时长表）
// ---------------------------------------------------------------------------

fn parseHexColor(s: []const u8) ?nano_gui.core.Color {
    var h = stripTicks(s);
    if (!std.mem.startsWith(u8, h, "#")) return null;
    h = h[1..];
    if (h.len != 6 and h.len != 8) return null;
    const v = std.fmt.parseInt(u32, h, 16) catch return null;
    if (h.len == 6) return .{ .r = @truncate(v >> 16), .g = @truncate(v >> 8), .b = @truncate(v), .a = 255 };
    return .{ .r = @truncate(v >> 24), .g = @truncate(v >> 16), .b = @truncate(v >> 8), .a = @truncate(v) };
}

fn fmtColor(buf: *[10]u8, c: nano_gui.core.Color) []const u8 {
    return std.fmt.bufPrint(buf, "#{X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{ c.r, c.g, c.b, c.a }) catch "?";
}

fn checkTokens(ctx: *Ctx, docs: []const Doc) !void {
    var doc: ?Doc = null;
    for (docs) |d| {
        if (std.mem.eql(u8, d.path, "docs/09-theme.md")) doc = d;
    }
    const d = doc orelse {
        ctx.fail("docs/09-theme.md", 1, "缺少主题文档", .{});
        return;
    };
    const light = theme.Theme.default(.light, .{});
    const dark = theme.Theme.default(.dark, .{});

    const Section = enum { none, color, metric };
    var sec: Section = .none;
    var seen_color = std.EnumSet(theme.ColorToken).init(.{});
    var seen_metric = std.EnumSet(theme.Metric).init(.{});
    var seen_dur = std.EnumSet(theme.Duration).init(.{});
    var n_color: usize = 0;
    var n_metric: usize = 0;
    var n_dur: usize = 0;
    var line_color: usize = 1;
    var line_metric: usize = 1;
    var line_dur: usize = 1;
    var it = std.mem.splitScalar(u8, d.text, '\n');
    var line: usize = 0;
    while (it.next()) |l| {
        line += 1;
        if (std.mem.startsWith(u8, l, "**REQ-THEME-")) {
            if (std.mem.startsWith(u8, l, "**REQ-THEME-007**")) {
                sec = .color;
                line_color = line;
            } else if (std.mem.startsWith(u8, l, "**REQ-THEME-011**")) {
                sec = .metric;
                line_metric = line;
            } else sec = .none;
            continue;
        }
        if (!std.mem.startsWith(u8, l, "| `")) continue;
        const cells = try splitCells(ctx.a, l);
        if (cells.len < 2) continue;

        if (std.mem.startsWith(u8, cells[0], "`dur_")) {
            const name = stripTicks(cells[0])[4..];
            if (n_dur == 0) line_dur = line;
            const num = std.mem.trim(u8, std.mem.trimEnd(u8, cells[1], "ms "), " ");
            const want = std.fmt.parseInt(u16, num, 10) catch {
                ctx.fail(d.path, line, "时长令牌 dur_{s} 的值“{s}”无法解析", .{ name, cells[1] });
                continue;
            };
            n_dur += 1;
            const e = std.meta.stringToEnum(theme.Duration, name) orelse {
                ctx.fail(d.path, line, "代码缺少时长令牌 dur_{s}（文档 {d} ms）", .{ name, want });
                continue;
            };
            if (seen_dur.contains(e)) ctx.fail(d.path, line, "时长令牌 dur_{s} 在文档中重复", .{name});
            seen_dur.insert(e);
            const got = light.durationMs(e);
            if (got != want) ctx.fail(d.path, line, "时长令牌 dur_{s}：文档 {d} ms，代码 {d} ms", .{ name, want, got });
            continue;
        }

        switch (sec) {
            .color => {
                if (cells.len < 3) {
                    ctx.fail(d.path, line, "颜色令牌行列数不足（需 令牌/浅色/深色）: {s}", .{cells[0]});
                    continue;
                }
                const name = stripTicks(cells[0]);
                n_color += 1;
                const lc = parseHexColor(cells[1]) orelse {
                    ctx.fail(d.path, line, "颜色令牌 {s} 的浅色值“{s}”无法解析", .{ name, cells[1] });
                    continue;
                };
                const dc = parseHexColor(cells[2]) orelse {
                    ctx.fail(d.path, line, "颜色令牌 {s} 的深色值“{s}”无法解析", .{ name, cells[2] });
                    continue;
                };
                const e = std.meta.stringToEnum(theme.ColorToken, name) orelse {
                    ctx.fail(d.path, line, "代码缺少颜色令牌 {s}", .{name});
                    continue;
                };
                if (seen_color.contains(e)) ctx.fail(d.path, line, "颜色令牌 {s} 在文档中重复", .{name});
                seen_color.insert(e);
                const pairs = [_]struct { label: []const u8, want: nano_gui.core.Color, got: nano_gui.core.Color }{
                    .{ .label = "浅色", .want = lc, .got = light.color(e) },
                    .{ .label = "深色", .want = dc, .got = dark.color(e) },
                };
                for (pairs) |p| {
                    if (!std.meta.eql(p.want, p.got)) {
                        var b1: [10]u8 = undefined;
                        var b2: [10]u8 = undefined;
                        ctx.fail(d.path, line, "颜色令牌 {s}（{s}）：文档 {s}，代码 {s}", .{ name, p.label, fmtColor(&b1, p.want), fmtColor(&b2, p.got) });
                    }
                }
            },
            .metric => {
                // 首列形如 `a` / `b` / `c`，值列形如 20 / 24 / 28
                var names = std.ArrayListUnmanaged([]const u8).empty;
                var ni = std.mem.splitSequence(u8, cells[0], " / ");
                while (ni.next()) |n| try names.append(ctx.a, stripTicks(n));
                var vals = std.ArrayListUnmanaged([]const u8).empty;
                var vi = std.mem.splitSequence(u8, cells[1], " / ");
                while (vi.next()) |v| try vals.append(ctx.a, std.mem.trim(u8, v, " "));
                if (names.items.len != vals.items.len) {
                    ctx.fail(d.path, line, "度量令牌行的名字数（{d}）与值数（{d}）不一致", .{ names.items.len, vals.items.len });
                    continue;
                }
                for (names.items, vals.items) |name, vs| {
                    n_metric += 1;
                    const want = std.fmt.parseFloat(f32, vs) catch {
                        ctx.fail(d.path, line, "度量令牌 {s} 的值“{s}”无法解析", .{ name, vs });
                        continue;
                    };
                    const e = std.meta.stringToEnum(theme.Metric, name) orelse {
                        ctx.fail(d.path, line, "代码缺少度量令牌 {s}（文档 {d}）", .{ name, want });
                        continue;
                    };
                    if (seen_metric.contains(e)) ctx.fail(d.path, line, "度量令牌 {s} 在文档中重复", .{name});
                    seen_metric.insert(e);
                    const got = light.metric(e);
                    if (@abs(got - want) > 1e-4) ctx.fail(d.path, line, "度量令牌 {s}：文档 {d}，代码 {d}", .{ name, want, got });
                }
            },
            .none => {},
        }
    }
    // 反向：代码枚举的每个成员都必须在文档中出现，且文档解析数量等于成员数
    inline for (.{
        .{ theme.ColorToken, &seen_color, n_color, line_color, "颜色" },
        .{ theme.Metric, &seen_metric, n_metric, line_metric, "度量" },
        .{ theme.Duration, &seen_dur, n_dur, line_dur, "时长" },
    }) |spec| {
        const E = spec[0];
        const n_members = std.enums.values(E).len;
        for (std.enums.values(E)) |m| {
            if (!spec[1].contains(m)) ctx.fail(d.path, spec[3], "文档缺少代码中的{s}令牌 {s}", .{ spec[4], @tagName(m) });
        }
        if (spec[2] != n_members) ctx.fail(d.path, spec[3], "文档{s}令牌表解析出 {d} 项，代码枚举有 {d} 个成员", .{ spec[4], spec[2], n_members });
    }
    std.debug.print("check-docs: 令牌比对 颜色 {d}、度量 {d}、时长 {d} 项\n", .{ n_color, n_metric, n_dur });
}

// ---------------------------------------------------------------------------
// 7) 测试名追溯
// ---------------------------------------------------------------------------

fn scanTests(ctx: *Ctx, defs: []const Def, ms: []const Milestone) !void {
    var def_set = std.StringHashMapUnmanaged(void).empty;
    for (defs) |d| try def_set.put(ctx.a, d.id, {});
    var traced = std.StringHashMapUnmanaged(void).empty;
    var n_tests: usize = 0;

    for ([_][]const u8{ "tests", "src", "tools" }) |sub| {
        const dir = ctx.root.openDir(ctx.io, sub, .{ .iterate = true }) catch |e| {
            ctx.fail(sub, 1, "无法打开扫描目录: {t}", .{e});
            continue;
        };
        var walker = try dir.walk(ctx.a);
        var paths = std.ArrayListUnmanaged([]const u8).empty;
        while (try walker.next(ctx.io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
            try paths.append(ctx.a, try ctx.a.dupe(u8, entry.path));
        }
        std.mem.sort([]const u8, paths.items, {}, struct {
            fn lt(_: void, x: []const u8, y: []const u8) bool {
                return std.mem.lessThan(u8, x, y);
            }
        }.lt);
        for (paths.items) |rel| {
            const full = try std.fs.path.join(ctx.a, &.{ sub, rel });
            const text = dir.readFileAlloc(ctx.io, rel, ctx.a, .unlimited) catch |e| {
                ctx.fail(full, 1, "无法读取: {t}", .{e});
                continue;
            };
            var it = std.mem.splitScalar(u8, text, '\n');
            var line: usize = 0;
            while (it.next()) |l| {
                line += 1;
                const t = std.mem.trimStart(u8, l, " \t");
                if (!std.mem.startsWith(u8, t, "test \"")) continue;
                const end = std.mem.indexOfScalarPos(u8, t, 6, '"') orelse continue;
                const name = t[6..end];
                n_tests += 1;
                var pos: usize = 0;
                while (std.mem.indexOfPos(u8, name, pos, "AC-")) |at| {
                    const tok = takeTok(name, at);
                    pos = at + tok.len;
                    const p = parseId(tok) orelse {
                        ctx.fail(full, line, "测试名引用了不合法的 AC 编号“{s}”（格式 AC-<域>-nnn）", .{tok});
                        continue;
                    };
                    if (!def_set.contains(tok)) {
                        ctx.fail(full, line, "测试名引用的 {s} 在文档中没有定义", .{tok});
                        continue;
                    }
                    try traced.put(ctx.a, tok, {});
                    // 简写 AC-LAYOUT-001/002：同域的后续序号
                    while (pos + 4 <= name.len and name[pos] == '/' and
                        std.ascii.isDigit(name[pos + 1]) and std.ascii.isDigit(name[pos + 2]) and std.ascii.isDigit(name[pos + 3]) and
                        (pos + 4 == name.len or !isTokChar(name[pos + 4])))
                    {
                        const sib = try std.fmt.allocPrint(ctx.a, "{s}-{s}", .{ p.domain_key, name[pos + 1 .. pos + 4] });
                        if (!def_set.contains(sib)) {
                            ctx.fail(full, line, "测试名引用的 {s} 在文档中没有定义", .{sib});
                        } else {
                            try traced.put(ctx.a, sib, {});
                        }
                        pos += 4;
                    }
                }
            }
        }
    }

    // (2) 结果为通过的非人工 AC 必须有测试；(3) 其余未追溯的作为警告
    std.debug.print("check-docs: 扫描到 {d} 个测试名\n", .{n_tests});
    if (n_tests == 0) ctx.fail("tests", 1, "tests/、src/、tools/ 中没有扫描到任何测试名", .{});
    var any_warn = false;
    for (ms) |m| {
        var untraced = std.ArrayListUnmanaged([]const u8).empty;
        for (m.rows) |r| {
            if (std.mem.eql(u8, r.method, "人工")) continue;
            if (traced.contains(r.id)) continue;
            if (std.mem.eql(u8, r.result, "通过")) {
                ctx.fail(r.path, r.line, "{s} 结果为通过但没有名字含该编号的自动化测试", .{r.id});
            } else {
                try untraced.append(ctx.a, r.id);
            }
        }
        if (untraced.items.len > 0) {
            if (!any_warn) std.debug.print("check-docs: 警告：未追溯 AC（结果尚非通过，不使检查失败）\n", .{});
            any_warn = true;
            ctx.warnings += untraced.items.len;
            std.debug.print("  {s}: {d} 条\n", .{ m.name, untraced.items.len });
            std.debug.print("    ", .{});
            for (untraced.items, 0..) |id, i| {
                if (i > 0) std.debug.print(" ", .{});
                std.debug.print("{s}", .{id});
            }
            std.debug.print("\n", .{});
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const a = init.arena.allocator();

    var root_path: []const u8 = ".";
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--root")) {
            root_path = try a.dupe(u8, args.next() orelse {
                std.debug.print("check-docs: --root 需要目录参数\n", .{});
                std.process.exit(2);
            });
        } else {
            std.debug.print("check-docs: 未知参数 {s}\n", .{arg});
            std.process.exit(2);
        }
    }

    const root = std.Io.Dir.cwd().openDir(io, root_path, .{ .iterate = true }) catch |e| {
        std.debug.print("{s}:1: 无法打开根目录: {t}\n", .{ root_path, e });
        std.process.exit(1);
    };
    var ctx = Ctx{ .a = a, .io = io, .root = root };

    const docs = try readDocs(&ctx);
    try checkLinks(&ctx, docs);
    const defs = try collectDefs(&ctx, docs);
    try checkCoverage(&ctx, docs, defs);
    const ms = try checkMilestones(&ctx, docs, defs);
    try checkWidgets(&ctx, docs);
    try checkTokens(&ctx, docs);
    try scanTests(&ctx, defs, ms);

    var n_req: usize = 0;
    var n_ac: usize = 0;
    for (defs) |d| {
        if (d.is_ac) n_ac += 1 else n_req += 1;
    }
    std.debug.print("check-docs: {d} 篇文档, {d} 条 REQ, {d} 条 AC, {d} 个失败, {d} 个警告\n", .{ docs.len, n_req, n_ac, ctx.failures, ctx.warnings });
    if (ctx.failures > 0) std.process.exit(1);
}

/// 废弃标记只认紧跟加粗编号之后的"（已废弃"（00 第 3 节），正文中出现的同样字样不算。
fn isAbandonedMark(after_id: []const u8) bool {
    var rest = after_id;
    while (true) {
        if (std.mem.startsWith(u8, rest, " ") or std.mem.startsWith(u8, rest, "\t")) {
            rest = rest[1..];
        } else if (std.mem.startsWith(u8, rest, "\u{3000}")) {
            rest = rest["\u{3000}".len..];
        } else break;
    }
    return std.mem.startsWith(u8, rest, "（已废弃");
}
