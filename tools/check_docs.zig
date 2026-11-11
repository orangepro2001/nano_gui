//! 文档一致性检查（REQ-TEST-024）。当前仓库的已知缺口记录在 known 列表中，
//! 检查器仍会对新增断链、重复编号与未覆盖条款失败。

const std = @import("std");

const known_gaps = [_][]const u8{};

const Doc = struct { path: []const u8, text: []const u8, line_of: []u32 };

fn lineAt(text: []const u8, offset: usize) u32 {
    var n: u32 = 1;
    for (text[0..@min(offset, text.len)]) |c| {
        if (c == '\n') n += 1;
    }
    return n;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var docs = std.ArrayListUnmanaged(Doc).empty;
    defer {
        for (docs.items) |d| {
            gpa.free(d.text);
            gpa.free(d.path);
            gpa.free(d.line_of);
        }
        docs.deinit(gpa);
    }

    var dir = std.Io.Dir.cwd();
    const docs_dir = dir.openDir(io, "docs", .{ .iterate = true }) catch |e| {
        std.debug.print("check-docs: 无法打开 docs/: {t}\n", .{e});
        std.process.exit(1);
    };
    defer docs_dir.close(io);
    var walker = try docs_dir.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".md")) continue;
        const text = try entry.dir.readFileAlloc(io, entry.basename, gpa, .unlimited);
        const path = try std.fs.path.join(gpa, &.{ "docs", entry.path });
        try docs.append(gpa, .{ .path = path, .text = text, .line_of = &.{} });
    }

    var failures: usize = 0;
    var warnings: usize = 0;
    var reqs = std.StringHashMapUnmanaged(u32).empty;
    var acs = std.StringHashMapUnmanaged(u32).empty;
    var covered = std.StringHashMapUnmanaged(void).empty;
    defer reqs.deinit(gpa);
    defer acs.deinit(gpa);
    defer covered.deinit(gpa);

    // 1) 相对链接
    for (docs.items) |d| {
        var i: usize = 0;
        while (std.mem.indexOfPos(u8, d.text, i, "](")) |open| {
            const start = open + 2;
            const close = std.mem.indexOfScalarPos(u8, d.text, start, ')') orelse break;
            const target = d.text[start..close];
            i = close + 1;
            if (std.mem.startsWith(u8, target, "http") or std.mem.startsWith(u8, target, "#")) continue;
            if (!std.mem.endsWith(u8, target, ".md")) continue;
            const slash = std.mem.lastIndexOfScalar(u8, target, '#') orelse target.len;
            const rel = target[0..slash];
            const dirname = std.fs.path.dirname(d.path) orelse ".";
            const resolved = try std.fs.path.join(gpa, &.{ dirname, rel });
            defer gpa.free(resolved);
            dir.access(io, resolved, .{}) catch {
                var keybuf: [512]u8 = undefined;
                const key = std.fmt.bufPrint(&keybuf, "{s}: {s}", .{ d.path, target }) catch target;
                if (isKnown(key)) {
                    warnings += 1;
                    std.debug.print("check-docs: 已知缺口（链接）{s}\n", .{key});
                } else {
                    failures += 1;
                    std.debug.print("{s}:{d}: 断链 {s}\n", .{ d.path, lineAt(d.text, open), target });
                }
            };
        }
    }

    // 2) 编号唯一（只统计行首定义，避免把示例中的编号当成定义）
    for (docs.items) |d| {
        var it = std.mem.splitScalar(u8, d.text, '\n');
        var line: u32 = 0;
        while (it.next()) |l| {
            line += 1;
            const trimmed = std.mem.trimStart(u8, l, " \t");
            if (!std.mem.startsWith(u8, trimmed, "**")) continue;
            const end = std.mem.indexOfPos(u8, trimmed, 2, "**") orelse continue;
            const id = trimmed[2..end];
            if (std.mem.startsWith(u8, id, "REQ-")) {
                const gop = try reqs.getOrPut(gpa, id);
                if (gop.found_existing) {
                    failures += 1;
                    std.debug.print("{s}:{d}: 重复规范条款 {s}\n", .{ d.path, line, id });
                }
            } else if (std.mem.startsWith(u8, id, "AC-")) {
                const gop = try acs.getOrPut(gpa, id);
                if (gop.found_existing) {
                    failures += 1;
                    std.debug.print("{s}:{d}: 重复验收条款 {s}\n", .{ d.path, line, id });
                }
            }
        }
    }

    // 3) 每条 REQ 至少被一条 AC 覆盖
    for (docs.items) |d| {
        var it = std.mem.splitScalar(u8, d.text, '\n');
        while (it.next()) |l| {
            if (std.mem.indexOf(u8, l, "**AC-") == null) continue;
            var pos: usize = 0;
            while (std.mem.indexOfPos(u8, l, pos, "REQ-")) |at| {
                var e = at;
                while (e < l.len and (std.ascii.isAlphanumeric(l[e]) or l[e] == '-')) e += 1;
                const id = l[at..e];
                try covered.put(gpa, id, {});
                pos = e;
            }
        }
    }
    std.debug.print("check-docs: docs={d} reqs={d} acs={d} covered={d}\n", .{ docs.items.len, reqs.count(), acs.count(), covered.count() });
    var rit = reqs.keyIterator();
    while (rit.next()) |id| {
        if (!covered.contains(id.*)) {
            var keybuf: [256]u8 = undefined;
            const key = std.fmt.bufPrint(&keybuf, "{s}: uncovered", .{id.*}) catch id.*;
            if (isKnown(key)) {
                warnings += 1;
            } else {
                failures += 1;
                std.debug.print("check-docs: 规范条款未被任何 AC 覆盖: {s}\n", .{id.*});
            }
        }
    }

    // 3b) 每条 AC 恰好归入一个里程碑清单。
    var milestone_counts = std.StringHashMapUnmanaged(u8).empty;
    defer milestone_counts.deinit(gpa);
    for (docs.items) |d| {
        if (!std.mem.startsWith(u8, d.path, "docs/acceptance/")) continue;
        var lines = std.mem.splitScalar(u8, d.text, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trimStart(u8, line, " \t");
            if (!std.mem.startsWith(u8, trimmed, "| AC-")) continue;
            const at = std.mem.indexOf(u8, trimmed, "AC-") orelse continue;
            var e = at;
            while (e < trimmed.len and (std.ascii.isAlphanumeric(trimmed[e]) or trimmed[e] == '-')) e += 1;
            const id = trimmed[at..e];
            const gop = try milestone_counts.getOrPut(gpa, id);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* +|= 1;
        }
    }
    var ait = acs.keyIterator();
    while (ait.next()) |id| {
        const n = milestone_counts.get(id.*) orelse 0;
        if (n != 1) {
            failures += 1;
            std.debug.print("check-docs: AC 未恰好归入一个里程碑: {s}（{d} 次）\n", .{ id.*, n });
        }
    }

    // 4) 验收清单目录：当前规划阶段允许缺失，作为警告。
    dir.access(io, "docs/acceptance", .{}) catch {
        warnings += 1;
        std.debug.print("check-docs: 警告：docs/acceptance/ 尚不存在（规划阶段）\n", .{});
    };

    // 5) 测试名中的 AC 编号（追溯）
    var test_hits: usize = 0;
    const root_dir = try dir.openDir(io, ".", .{ .iterate = true });
    defer root_dir.close(io);
    var src_walker = try root_dir.walk(gpa);
    defer src_walker.deinit();
    while (try src_walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const is_src = std.mem.startsWith(u8, entry.path, "src/") or std.mem.startsWith(u8, entry.path, "tests/");
        if (!is_src or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const text = try entry.dir.readFileAlloc(io, entry.basename, gpa, .unlimited);
        defer gpa.free(text);
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, text, pos, "AC-")) |at| {
            test_hits += 1;
            pos = at + 1;
        }
    }

    std.debug.print("check-docs: {d} 篇文档, {d} 条 REQ, {d} 条 AC, {d} 处测试追溯, {d} 个失败, {d} 个警告\n", .{ docs.items.len, reqs.count(), acs.count(), test_hits, failures, warnings });
    if (failures > 0) std.process.exit(1);
}

fn isKnown(key: []const u8) bool {
    for (known_gaps) |k| {
        if (std.mem.eql(u8, k, key)) return true;
    }
    return false;
}
