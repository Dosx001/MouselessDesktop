const std = @import("std");
const go = @import("gobject.zig");
const tray = @import("systemtray.zig");
const hotkey = @import("hotkey.zig");
const c = @cImport({
    @cInclude("gtk-3.0/gtk/gtk.h");
});

var RUNNING: bool = true;

pub fn main() !void {
    var argc: c_int = 0;
    var argv: [*c][*c]u8 = undefined;
    c.gtk_init(&argc, &argv);
    const window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL);
    go.g_signal_connect(window, "delete-event", @ptrCast(&c.gtk_widget_hide_on_delete), null);
    const w: *c.GtkWindow = @ptrCast(window);
    const screen = c.gtk_window_get_screen(w);
    const visual = c.gdk_screen_get_rgba_visual(screen);
    if (visual != null) c.gtk_widget_set_visual(window, visual);
    const file = c.g_file_new_for_path("src/styles.css");
    defer c.g_object_unref(file);
    const css_provider = c.gtk_css_provider_new();
    _ = c.gtk_css_provider_load_from_file(css_provider, file, null);
    c.gtk_style_context_add_provider_for_screen(
        screen,
        @ptrCast(css_provider),
        c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
    c.gtk_window_fullscreen(w);
    const stray = tray.SystemTray.init();
    defer stray.deinit();
    const thread = std.Thread.spawn(.{}, hotkey.Hotkey.init, .{
        &RUNNING,
        window,
    }) catch unreachable;
    c.gtk_main();
    RUNNING = false;
    thread.join();
    return;
}
