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
                defer c.g_object_unref(app);
                for (0..@intCast(c.atspi_accessible_get_child_count(app, null))) |k| {
                    const win = c.atspi_accessible_get_child_at_index(app, @intCast(k), null);
                    defer c.g_object_unref(win);
                    const states = c.atspi_accessible_get_state_set(win);
                    defer c.g_object_unref(states);
                    const name = c.atspi_accessible_get_name(app, null);
                    defer c.g_free(name);
                    if (c.atspi_state_set_contains(states, c.ATSPI_STATE_ACTIVE) == 1) {
                        c.g_print("%s\n", name);
                        print_tree(win, 2);
                        return;
                    }
                }
            }
        }
    }
    return;
}

fn print_tree(obj: ?*c.AtspiAccessible, padding: usize) void {
    for (0..padding) |_| c.g_print(" ");
    const name = c.atspi_accessible_get_name(obj, null);
    defer c.g_free(name);
    const role = c.atspi_accessible_get_role_name(obj, null);
    defer c.g_free(role);
    const pos = c.atspi_component_get_position(
        c.atspi_accessible_get_component_iface(obj),
        c.ATSPI_COORD_TYPE_SCREEN,
        null,
    );
    defer c.g_free(pos);
    c.g_print(
        "(%s): %s, %d, %d\n",
        name,
        role,
        pos.*.x,
        pos.*.y,
    );
    for (0..@intCast(c.atspi_accessible_get_child_count(obj, null))) |i| {
        print_tree(c.atspi_accessible_get_child_at_index(obj, @intCast(i), null), padding + 2);
    }
}
