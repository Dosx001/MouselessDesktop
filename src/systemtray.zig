const std = @import("std");
const icon = @import("icon.zig");
const go = @import("gobject.zig");
const c = @cImport({
    @cInclude("libappindicator3-0.1/libappindicator/app-indicator.h");
});

var app: *c.AppIndicator = undefined;

pub fn init() void {
    const path = icon.get_path(icon.Size.x32, false, std.heap.page_allocator);
    defer std.heap.page_allocator.free(path);
    app = c.app_indicator_new_with_path(
        "Mouseless Desktop",
        "32x32",
        c.APP_INDICATOR_CATEGORY_APPLICATION_STATUS,
        path.ptr,
    );
    const menu = c.gtk_menu_new();
    const quit = c.gtk_menu_item_new_with_label("Quit");
    go.g_signal_connect(quit, "activate", @ptrCast(&c.gtk_main_quit), null);
    c.gtk_menu_shell_append(@ptrCast(menu), @ptrCast(quit));
    c.gtk_widget_show_all(menu);
    c.app_indicator_set_menu(app, @ptrCast(menu));
    c.app_indicator_set_status(app, c.APP_INDICATOR_STATUS_ACTIVE);
}

pub fn deinit() void {
    c.g_object_unref(app);
}
