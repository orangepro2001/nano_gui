//! 文档哈希工具：证明构建/测试过程不写入 docs/。
//! 用法：hash_docs [--write 路径 | --check 基线路径]

const std = @import("std");

const Entry = struct { path: []const u8, hex: [64]u8 };

fn collect(allocator: std.mem.Allocator, io: std.Io) ![]Entry {
    var list = std.ArrayListUnmanaged(Entry).empty;
    const docs_dir = try std.Io.Dir.cwd().openDir(io, "docs", .{ .iterate = true });
    defer docs_dir.close(io);
    var walker = try docs_dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |e| {
        if (e.kind != .file) continue;
        const bytes = try e.dir.readFileAlloc(io, e.basename, allocator, .unlimited);
        defer allocator.free(bytes);
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
        const hex = std.fmt.bytesToHex(hash, .lower);
        try list.append(allocator, .{
            .path = try std.fs.path.join(allocator, &.{ "docs", e.path }),
            .hex = hex,
        });
    }
    std.mem.sort(Entry, list.items, {}, struct {
        fn less(_: void, a: Entry, b: Entry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.less);
    return list.toOwnedSlice(allocator);
}

fn appendAll(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, entries: []const Entry) !void {
    for (entries) |e| {
        try out.appendSlice(allocator, &e.hex);
        try out.appendSlice(allocator, "  ");
        try out.appendSlice(allocator, e.path);
        try out.append(allocator, '\n');
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const entries = try collect(gpa, io);
    defer {
        for (entries) |e| gpa.free(e.path);
        gpa.free(entries);
    }
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.next();
    if (args.next()) |mode| {
        if (std.mem.eql(u8, mode, "--write")) {
            const path = args.next() orelse "docs.sha256.current";
            var out = std.ArrayListUnmanaged(u8).empty;
            defer out.deinit(gpa);
            try appendAll(&out, gpa, entries);
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.items });
            var buf: [256]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "docs-hash: wrote {d} files to {s}\n", .{ entries.len, path });
            try std.Io.File.stdout().writeStreamingAll(io, msg);
            return;
        }
        if (std.mem.eql(u8, mode, "--check")) {
            const path = args.next() orelse "docs.sha256";
            const base = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited) catch |e| {
                std.debug.print("docs-hash: 无法读取基线 {s}: {t}\n", .{ path, e });
                std.process.exit(2);
            };
            defer gpa.free(base);
            var out = std.ArrayListUnmanaged(u8).empty;
            defer out.deinit(gpa);
            try appendAll(&out, gpa, entries);
            if (std.mem.eql(u8, base, out.items)) {
                var buf: [128]u8 = undefined;
                const msg = try std.fmt.bufPrint(&buf, "docs-hash: docs/ 未变化（{d} 文件）\n", .{entries.len});
                try std.Io.File.stdout().writeStreamingAll(io, msg);
                return;
            }
            std.debug.print("docs-hash: docs/ 与基线不一致\n", .{});
            std.process.exit(1);
        }
    }
    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(gpa);
    try appendAll(&out, gpa, entries);
    try std.Io.File.stdout().writeStreamingAll(io, out.items);
}
