const std = @import("std");
const c = @cImport({
    @cInclude("dbus-1.0/dbus/dbus.h");
    @cInclude("glib-2.0/glib.h");
    @cInclude("at-spi-2.0/atspi/atspi.h");
});

pub fn main() !void {
    _ = c.atspi_init();
    const desktop: ?*c.AtspiAccessible = c.atspi_get_desktop(0);
    var app: ?*c.AtspiAccessible = null;
    for (0..@intCast(c.atspi_accessible_get_child_count(desktop, null))) |i| {
        app = c.atspi_accessible_get_child_at_index(desktop, @intCast(i), null);
        c.g_print(
            "(Index, application, application_child_count)=(%d,%s,%d)\n",
            i,
            c.atspi_accessible_get_name(app, null),
            c.atspi_accessible_get_child_count(app, null),
        );
        c.g_object_unref(app);
    }
    return;
}
