const std = @import("std");
const client = @import("client.zig");
const mouseless = @import("mouseless.zig");
const tray = @import("systemtray.zig");
const c = @cImport({
    @cInclude("gtk-3.0/gtk/gtk.h");
    @cInclude("libnotify/notify.h");
    @cInclude("signal.h");
});

pub const std_options: std.Options = .{
    .logFn = @import("log.zig").logger,
};

pub fn main() !void {
    _ = c.signal(c.SIGINT, sigint_handler);
    _ = c.notify_init("MouselessDesktop");
    if (1 < std.os.argv.len) {
        _ = switch (std.os.argv[1][0]) {
            's' => try client.show(),
            'c' => mouseless.reset(),
            else => {},
        };
        return;
    }
    try mouseless.init();
    var argc: c_int = @intCast(std.os.argv.len);
    var argv: [*c][*c]u8 = @ptrCast(std.os.argv.ptr);
    c.gtk_init(&argc, &argv);
    try tray.init();
    defer tray.deinit();
    try mouseless.gtk_init();
    defer mouseless.deinit();
    var running = true;
    const thread = std.Thread.spawn(.{}, mouseless.run, .{
        &running,
    }) catch return std.log.err("unable to spawn thread", .{});
    c.gtk_main();
    running = false;
    try client.clean();
    thread.join();
    c.notify_uninit();
    return;
}

fn sigint_handler(_: c_int) callconv(.C) void {
    c.gtk_main_quit();
}
