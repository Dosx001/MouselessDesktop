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
    sig.init();
    log.init();
    queue.init();
    defer log.deinit();
    try win.init(gpa);
    defer win.deinit();
    try ml.init();
    defer ml.deinit();
    _ = std.Thread.spawn(
        .{},
        ml.run,
        .{io},
    ) catch
        return std.log.err("unable to spawn thread", .{});
    win.run(io, gpa);
    return;
}
