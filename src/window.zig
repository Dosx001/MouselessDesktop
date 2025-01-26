const go = @import("gobject.zig");
const c = @cImport({
    @cInclude("gtk-3.0/gtk/gtk.h");
});

pub const Window = struct {
    window: *c.GtkWidget,
    pub fn init() Window {
        const window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL);
        c.gtk_window_fullscreen(@ptrCast(window));
        go.g_signal_connect(window, "delete-event", @ptrCast(&c.gtk_widget_hide_on_delete), null);
        const screen = c.gtk_window_get_screen(@ptrCast(window));
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
        return Window{ .window = window };
    }
    pub fn deinit(self: Window) void {
        c.gtk_widget_destroy(@ptrCast(self.window));
    }
};
