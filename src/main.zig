const ml = @import("mouseless.zig");
const sig = @import("signal.zig");
const std = @import("std");
const win = @import("window.zig");

const c = @cImport({
    @cInclude("gtk-3.0/gtk/gtk.h");
    @cInclude("libnotify/notify.h");
});

pub const std_options: std.Options = .{
    .logFn = @import("log.zig").logger,
};

pub fn main() !void {
    sig.setup();
    _ = c.notify_init("MouselessDesktop");
    defer c.notify_uninit();
    if (1 < std.os.argv.len) {
        _ = switch (std.os.argv[1][0]) {
            else => {},
        };
        return;
    }
    var argc: c_int = @intCast(std.os.argv.len);
    var argv: [*c][*c]u8 = @ptrCast(std.os.argv.ptr);
    c.gtk_init(&argc, &argv);
    try win.init();
    defer win.deinit();
    try ml.init();
    defer ml.deinit();
    const t_ml = std.Thread.spawn(
        .{},
        ml.run,
        .{},
    ) catch return std.log.err("unable to spawn thread", .{});
    const t_win = std.Thread.spawn(
        .{},
        win.run,
        .{},
    ) catch return std.log.err("unable to spawn thread", .{});
    c.gtk_main();
    t_ml.join();
    t_win.join();
    return;
}
