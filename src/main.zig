const std = @import("std");
const mouseless = @import("mouseless.zig");
const tray = @import("systemtray.zig");
const c = @cImport({
    @cInclude("gtk-3.0/gtk/gtk.h");
});

pub const std_options: std.Options = .{
    .logFn = @import("log.zig").logger,
};

pub fn main() !void {
    var argc: c_int = @intCast(std.os.argv.len);
    var argv: [*c][*c]u8 = @ptrCast(std.os.argv.ptr);
    c.gtk_init(&argc, &argv);
    tray.init();
    defer tray.deinit();
    mouseless.init() catch unreachable;
    defer mouseless.deinit();
    var running = true;
    const thread = std.Thread.spawn(.{}, mouseless.run, .{
        &running,
    }) catch unreachable;
    c.gtk_main();
    running = false;
    thread.join();
    return;
}
