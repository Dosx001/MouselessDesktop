const std = @import("std");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
    @cInclude("at-spi-2.0/atspi/atspi.h");
    @cInclude("libappindicator3-0.1/libappindicator/app-indicator.h");
});

var RUNNING: bool = true;

pub fn main() !void {
    var argc: c_int = 0;
    var argv: [*c][*c]u8 = undefined;
    c.gtk_init(&argc, &argv);
    const window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL);
    const w: *c.GtkWindow = @ptrCast(window);
    const screen = c.gtk_window_get_screen(w);
    const visual = c.gdk_screen_get_rgba_visual(screen);
    if (visual != null) c.gtk_widget_set_visual(window, visual);
    const css_provider = c.gtk_css_provider_new();
    _ = c.gtk_css_provider_load_from_data(
        css_provider,
        "window { background-color: transparent; }",
        -1,
        null,
    );
    c.gtk_style_context_add_provider_for_screen(
        screen,
        @ptrCast(css_provider),
        c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
    c.gtk_window_fullscreen(w);
    c.gtk_window_present(w);
    const app = c.app_indicator_new(
        "Mouseless Desktop",
        "application-exit",
        c.APP_INDICATOR_CATEGORY_APPLICATION_STATUS,
    );
    const menu = c.gtk_menu_new();
    const quit = c.gtk_menu_item_new_with_label("Quit");
    _ = g_signal_connect(quit, "activate", @ptrCast(&on_quit), null);
    c.gtk_menu_shell_append(@ptrCast(menu), @ptrCast(quit));
    c.gtk_widget_show_all(menu);
    c.app_indicator_set_menu(app, @ptrCast(menu));
    c.app_indicator_set_status(app, c.APP_INDICATOR_STATUS_ACTIVE);
    const thread = std.Thread.spawn(.{}, hotkey, .{&RUNNING}) catch unreachable;
    c.gtk_main();
    RUNNING = false;
    thread.join();
    return;
}

fn hotkey(run: *bool) !void {
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
    defer inline for (modifiers) |modifier| {
        _ = c.XUngrabKey(display, keycode, modifier, root);
    };
    _ = c.XSelectInput(display, root, c.KeyPressMask);
    _ = c.atspi_init();
    var event: c.XEvent = undefined;
    while (run.*) {
        while (0 < c.XPending(display)) {
            _ = c.XNextEvent(display, &event);
            if (event.type == c.KeyPress) {
                print_tree();
            }
        }
    }
}

fn g_signal_connect(
    instance: c.gpointer,
    detailed_signal: [*c]const c.gchar,
    c_handler: c.GCallback,
    data: c.gpointer,
) c.gulong {
    var zero: u32 = 0;
    const flags: *c.GConnectFlags = @ptrCast(&zero);
    return c.g_signal_connect_data(
        instance,
        detailed_signal,
        c_handler,
        data,
        null,
        flags.*,
    );
}

fn on_quit(_: ?*c.GtkMenuItem, _: ?*c.gpointer) void {
    c.gtk_main_quit();
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
