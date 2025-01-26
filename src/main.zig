const std = @import("std");
const go = @import("gobject.zig");
const hotkey = @import("hotkey.zig");
const tray = @import("systemtray.zig");
const window = @import("window.zig");
const c = @cImport({
    @cInclude("gtk-3.0/gtk/gtk.h");
});

pub fn main() !void {
    var argc: c_int = 0;
    var argv: [*c][*c]u8 = undefined;
    c.gtk_init(&argc, &argv);
    const stray = tray.SystemTray.init();
    defer stray.deinit();
    const win = window.Window.init();
    defer win.deinit();
    var running = true;
    const thread = std.Thread.spawn(.{}, hotkey.Hotkey.init, .{
        &running,
        win.window,
    }) catch unreachable;
    c.gtk_main();
    running = false;
    thread.join();
    return;
}
