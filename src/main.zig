const std = @import("std");
const c = @cImport({
    @cInclude("dbus-1.0/dbus/dbus.h");
    @cInclude("glib-2.0/glib.h");
    @cInclude("at-spi-2.0/atspi/atspi.h");
});

pub fn main() !void {
    _ = c.atspi_init();
    while (true) : (std.time.sleep(3 * std.time.ns_per_s)) {
        for (0..@intCast(c.atspi_get_desktop_count())) |i| {
            const desktop: ?*c.AtspiAccessible = c.atspi_get_desktop(@intCast(i));
            for (0..@intCast(c.atspi_accessible_get_child_count(desktop, null))) |j| {
                const app = c.atspi_accessible_get_child_at_index(desktop, @intCast(j), null);
                for (0..@intCast(c.atspi_accessible_get_child_count(app, null))) |k| {
                    const win = c.atspi_accessible_get_child_at_index(app, @intCast(k), null);
                    const state_set = c.atspi_accessible_get_state_set(win);
                    if (c.atspi_state_set_contains(state_set, c.ATSPI_STATE_ACTIVE) == 1) {
                        c.g_print(
                            "%s\n",
                            c.atspi_accessible_get_name(app, null),
                        );
                    }
                    c.g_object_unref(win);
                    c.g_object_unref(state_set);
                }
                c.g_object_unref(app);
            }
        }
    }
    return;
}
