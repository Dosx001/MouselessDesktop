const std = @import("std");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
    @cInclude("at-spi-2.0/atspi/atspi.h");
});

pub fn main() !void {
    const display = c.XOpenDisplay(null);
    defer _ = c.XCloseDisplay(display);
    if (display == null) {
        std.debug.print("Unable to open display\n", .{});
        return error.UnableToOpenDisplay;
    }
    const keycode = c.XKeysymToKeycode(display, c.XK_semicolon);
    if (keycode == 0) {
        std.debug.print("Unable to escape\n", .{});
        return error.UnableToEscape;
    }
    const root = c.DefaultRootWindow(display);
    const modifiers = [4]c.uint{
        c.Mod4Mask,
        c.Mod4Mask | c.Mod2Mask,
        c.Mod4Mask | c.LockMask,
        c.Mod4Mask | c.Mod2Mask | c.LockMask,
    };
    inline for (modifiers) |modifier|
        _ = c.XGrabKey(
            display,
            keycode,
            modifier,
            root,
            c.True,
            c.GrabModeAsync,
            c.GrabModeAsync,
        );
    defer inline for (modifiers) |modifier|
        c.XUngrabKey(display, keycode, modifier, root);
    _ = c.XSelectInput(display, root, c.KeyPressMask);
    _ = c.atspi_init();
    var event: c.XEvent = undefined;
    while (true) {
        while (0 < c.XPending(display)) {
            _ = c.XNextEvent(display, &event);
            if (event.type == c.KeyPress) {
                print_tree();
            }
        }
    }
    return;
}

fn print_tree() void {
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
                    print_child(win, 0);
                    return;
                }
            }
        }
    }
}

fn print_child(obj: ?*c.AtspiAccessible, padding: usize) void {
    if (obj == null) return;
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
        print_child(c.atspi_accessible_get_child_at_index(obj, @intCast(i), null), padding + 2);
    }
}
