//! M0 架构验收用的子进程探针（AC-ARCH-005、AC-ARCH-008、AC-ARCH-010、AC-ARCH-011）。
//! 由 build.zig 分别以调试与发布两种优化模式编译，测试通过命令行参数选择场景并检查退出状态与输出。
const std = @import("std");
const nano = @import("nano_gui");
const core = nano.core;

var err_count: u32 = 0;
var warn_count: u32 = 0;
var info_count: u32 = 0;
var debug_count: u32 = 0;

fn sink(level: core.log.Level, tag: []const u8, msg: []const u8) void {
    _ = tag;
    _ = msg;
    switch (level) {
        .err => err_count += 1,
        .warn => warn_count += 1,
        .info => info_count += 1,
        .debug => debug_count += 1,
    }
}

fn dupIdBuild(ctx: *anyopaque, u: *nano.ui.Ui) void {
    _ = ctx;
    _ = u.beginColumn(@src(), .{});
    // 同一调用点在循环内两次使用同一个显式键，制造 ID 冲突（REQ-FRAME-001）。
    for (0..2) |_| {
        _ = nano.widgets.label(u, @src(), "a", .{ .key = nano.ui.Key.int(7) });
    }
    u.endColumn();
}

fn invalidateFromWorker(app: *nano.app.App) void {
    // 非线程安全 API：调试构建应在入口断言中止。
    app.invalidateAll(.build);
}

pub fn main(init: std.process.Init) !u8 {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, std.heap.page_allocator);
    _ = args.next();
    const mode = args.next() orelse return 2;

    if (std.mem.eql(u8, mode, "leak")) {
        // 持久分配器泄漏一次后正常退出：debug 构建必须以非零码退出并打印分配点。
        var pa = core.PersistentAllocator.init();
        const gpa = pa.allocator();
        const leaked = try gpa.alloc(u8, 64);
        leaked[0] = 1;
        if (pa.deinit()) return 1;
        return 0;
    }
    if (std.mem.eql(u8, mode, "noleak")) {
        // 对照组：分配并释放后正常退出，退出码必须为 0。
        var pa = core.PersistentAllocator.init();
        const gpa = pa.allocator();
        const buf = try gpa.alloc(u8, 64);
        gpa.free(buf);
        if (pa.deinit()) return 1;
        return 0;
    }
    if (std.mem.eql(u8, mode, "worker-api")) {
        var app = try nano.app.App.init(std.heap.page_allocator, .{ .size = .{ .w = 200, .h = 120 } });
        const t = try core.thread.spawn(.{}, invalidateFromWorker, .{&app});
        t.join();
        return 0; // 调试构建不应走到这里。
    }
    if (std.mem.eql(u8, mode, "dup-id")) {
        var app = try nano.app.App.init(std.heap.page_allocator, .{ .size = .{ .w = 200, .h = 120 } });
        core.log.setSink(sink);
        var dummy: u8 = 0;
        app.renderOnce(&dummy, dupIdBuild);
        app.renderOnce(&dummy, dupIdBuild);
        core.log.setSink(null);
        var buf: [64]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "err={d}\n", .{err_count});
        try std.Io.File.stdout().writeStreamingAll(init.io, line);
        return 0;
    }
    if (std.mem.eql(u8, mode, "log")) {
        core.log.setSink(sink);
        core.log.write(.err, "probe", "e", .{});
        core.log.write(.warn, "probe", "w", .{});
        core.log.write(.info, "probe", "i", .{});
        core.log.write(.debug, "probe", "d", .{});
        core.log.setSink(null);
        var buf: [64]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "total={d}\n", .{err_count + warn_count + info_count + debug_count});
        try std.Io.File.stdout().writeStreamingAll(init.io, line);
        return 0;
    }
    return 2;
}
