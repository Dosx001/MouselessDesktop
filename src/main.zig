const log = @import("utils/log.zig");
const ml = @import("mouseless.zig");
const queue = @import("queue.zig");
const sig = @import("signal.zig");
const std = @import("std");
const win = @import("window.zig");

pub const std_options: std.Options = .{
    .logFn = log.logger,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    sig.init();
    try log.init(io);
    defer log.deinit();
    queue.init();
    try win.init(gpa);
    defer win.deinit();
    _ = std.Thread.spawn(
        .{},
        ml.init,
        .{io},
    ) catch
        return std.log.err("unable to spawn thread", .{});
    win.run(io, arena);
    return;
}
