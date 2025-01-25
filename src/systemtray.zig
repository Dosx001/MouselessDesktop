const std = @import("std");
const go = @import("gobject.zig");
const c = @cImport({
    @cInclude("libappindicator3-0.1/libappindicator/app-indicator.h");
});
pub const SystemTray = struct {
    app: *c.AppIndicator,
    pub fn init() SystemTray {
        const app = c.app_indicator_new(
            "Mouseless Desktop",
            "application-exit",
            c.APP_INDICATOR_CATEGORY_APPLICATION_STATUS,
        );
        const menu = c.gtk_menu_new();
        const quit = c.gtk_menu_item_new_with_label("Quit");
        go.g_signal_connect(quit, "activate", @ptrCast(&c.gtk_main_quit), null);
        c.gtk_menu_shell_append(@ptrCast(menu), @ptrCast(quit));
        c.gtk_widget_show_all(menu);
        c.app_indicator_set_menu(app, @ptrCast(menu));
        c.app_indicator_set_status(app, c.APP_INDICATOR_STATUS_ACTIVE);
        return SystemTray{ .app = app };
    }
    pub fn deinit(self: SystemTray) void {
        c.g_object_unref(self.app);
    }
};
