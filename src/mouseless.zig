const std = @import("std");
const icon = @import("icon.zig");
const go = @import("gobject.zig");
const c = @cImport({
    @cInclude("X11/Xatom.h");
    @cInclude("X11/Xlib.h");
    @cInclude("X11/extensions/XTest.h");
    @cInclude("X11/keysym.h");
    @cInclude("at-spi-2.0/atspi/atspi.h");
    @cInclude("gtk-3.0/gtk/gtk.h");
});

var window: *c.GtkWidget = undefined;
var display: ?*c.Display = undefined;
var fixed: *c.GtkWidget = undefined;
var entry: *c.GtkWidget = undefined;

var count: usize = 0;
const chars = ";ALSKDJFIWOE";
const Point = struct { x: c_int, y: c_int };
var map = std.StringHashMap(Point).init(std.heap.page_allocator);

pub fn init() !void {
    display = c.XOpenDisplay(null);
    if (display == null) {
        std.debug.print("Unable to open display\n", .{});
        return error.UnableToOpenDisplay;
    }
    window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL);
    const path = icon.get_path(icon.Size.x128, true, std.heap.page_allocator);
    defer std.heap.page_allocator.free(path);
    _ = c.gtk_window_set_default_icon_from_file(path.ptr, null);
    c.gtk_window_fullscreen(@ptrCast(window));
    go.g_signal_connect(window, "delete-event", @ptrCast(&hide), null);
    fixed = c.gtk_fixed_new();
    c.gtk_container_add(@ptrCast(window), fixed);
    const accel_group = c.gtk_accel_group_new();
    defer c.g_object_unref(@ptrCast(accel_group));
    const clear_closure = c.g_cclosure_new(
        @ptrCast(&clear),
        null,
        null,
    );
    defer c.g_closure_unref(clear_closure);
    c.gtk_accel_group_connect(
        accel_group,
        c.GDK_KEY_Escape,
        0,
        0,
        clear_closure,
    );
    const click_closure = c.g_cclosure_new(
        @ptrCast(&click),
        null,
        null,
    );
    defer c.g_closure_unref(click_closure);
    c.gtk_accel_group_connect(
        accel_group,
        c.GDK_KEY_Return,
        0,
        0,
        click_closure,
    );
    c.gtk_window_add_accel_group(@ptrCast(window), accel_group);
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
    map.ensureTotalCapacity(128) catch unreachable;
}

fn clear_keys() void {
    var iter = map.iterator();
    while (iter.next()) |e|
        std.heap.page_allocator.free(e.key_ptr.*);
    map.clearRetainingCapacity();
}

pub fn deinit() void {
    c.gtk_widget_destroy(window);
    _ = c.XCloseDisplay(display);
    clear_keys();
}

fn hide() void {
    count = 0;
    c.gtk_container_foreach(@ptrCast(fixed), @ptrCast(&c.gtk_widget_destroy), null);
    _ = c.gtk_widget_hide_on_delete(window);
    clear_keys();
}

fn clear() void {
    c.gtk_widget_hide(window);
    count = 0;
    c.gtk_container_foreach(@ptrCast(fixed), @ptrCast(&c.gtk_widget_destroy), null);
    clear_keys();
}

fn click() void {
    const key = std.ascii.allocUpperString(
        std.heap.page_allocator,
        std.mem.span(c.gtk_entry_get_text(@ptrCast(entry))),
    ) catch unreachable;
    defer std.heap.page_allocator.free(key);
    const pt = map.get(key) orelse return c.gtk_entry_set_text(@ptrCast(entry), "");
    clear();
    const root = c.DefaultRootWindow(display);
    _ = c.XWarpPointer(display, c.None, root, 0, 0, 0, 0, pt.x, pt.y);
    while (c.g_main_context_iteration(c.g_main_context_default(), c.FALSE) == 1) {}
    _ = c.XTestFakeButtonEvent(display, 1, 1, c.CurrentTime);
    _ = c.XTestFakeButtonEvent(display, 1, 0, c.CurrentTime);
    _ = c.XFlush(display);
}

pub fn run(running: *bool) void {
    const keycode = c.XKeysymToKeycode(display, c.XK_semicolon);
    if (keycode == 0) {
        std.debug.print("Unable to escape\n", .{});
        return;
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
    while (running.*) {
        while (0 < c.XPending(display)) {
            _ = c.XNextEvent(display, &event);
            if (event.type == c.KeyPress) {
                if (find_active_window())
                    c.gtk_widget_show_all(window);
            }
        }
    }
}

fn find_active_window() bool {
    entry = c.gtk_entry_new();
    const pid = active_pid();
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
                if (c.atspi_state_set_contains(states, c.ATSPI_STATE_ACTIVE) == 1 and
                    pid == c.atspi_accessible_get_process_id(win, null))
                {
                    const pos = c.atspi_component_get_position(
                        c.atspi_accessible_get_component_iface(win),
                        c.ATSPI_COORD_TYPE_SCREEN,
                        null,
                    );
                    defer c.g_free(pos);
                    c.gtk_fixed_put(@ptrCast(fixed), @ptrCast(entry), @intCast(pos.*.x), @intCast(pos.*.y));
                    label_object(win);
                    return true;
                }
            }
        }
    }
    return false;
}

fn label_object(obj: ?*c.AtspiAccessible) void {
    if (obj == null) return;
    const role = c.atspi_accessible_get_role(obj, null);
    if (check_role(role)) {
        const states = c.atspi_accessible_get_state_set(obj);
        defer c.g_object_unref(states);
        if (c.atspi_state_set_contains(
            states,
            c.ATSPI_STATE_VISIBLE,
        ) == 1 and c.atspi_state_set_contains(
            states,
            c.ATSPI_STATE_SHOWING,
        ) == 1) {
            const size = c.atspi_component_get_size(
                c.atspi_accessible_get_component_iface(obj),
                null,
            );
            defer c.g_free(size);
            const pos = c.atspi_component_get_position(
                c.atspi_accessible_get_component_iface(obj),
                c.ATSPI_COORD_TYPE_SCREEN,
                null,
            );
            defer c.g_free(pos);
            const buffer = std.heap.page_allocator.alloc(u8, 4) catch unreachable;
            defer std.heap.page_allocator.free(buffer);
            const key = std.heap.page_allocator.dupe(
                u8,
                buffer[0..create_key(buffer)],
            ) catch unreachable;
            map.put(key, Point{
                .x = @divFloor(2 * pos.*.x + size.*.x, 2),
                .y = @divFloor(2 * pos.*.y + size.*.y, 2),
            }) catch unreachable;
            count += 1;
            const label = c.gtk_label_new(@ptrCast(key));
            c.gtk_fixed_put(@ptrCast(fixed), label, pos.*.x, pos.*.y);
        }
    }
    for (0..@intCast(c.atspi_accessible_get_child_count(obj, null))) |i| {
        label_object(
            c.atspi_accessible_get_child_at_index(obj, @intCast(i), null),
        );
    }
}

fn check_role(role: c_uint) bool {
    return switch (role) {
        c.ATSPI_ROLE_CHECK_BOX,
        c.ATSPI_ROLE_LINK,
        c.ATSPI_ROLE_LIST_ITEM,
        c.ATSPI_ROLE_MENU_ITEM,
        c.ATSPI_ROLE_PAGE_TAB,
        c.ATSPI_ROLE_PUSH_BUTTON,
        c.ATSPI_ROLE_PUSH_BUTTON_MENU,
        c.ATSPI_ROLE_RADIO_BUTTON,
        c.ATSPI_ROLE_TOGGLE_BUTTON,
        => true,
        else => false,
    };
}

fn create_key(buf: []u8) u8 {
    if (count == 0) {
        buf.ptr[0] = chars[0];
        return 1;
    }
    const base = chars.len;
    var i: usize = count;
    var j: u8 = 0;
    while (0 < i) : (i = @divFloor(i, base)) {
        buf[j] = chars[i % base];
        j += 1;
    }
    return j;
}

fn active_pid() c_int {
    var atom = c.XInternAtom(display, "_NET_ACTIVE_WINDOW", 1);
    if (atom == c.None) return 0;
    var actual_type: c.Atom = undefined;
    var actual_format: c_int = undefined;
    var nitems: c_ulong = undefined;
    var bytes_after: c_ulong = undefined;
    var prop: [*c]u8 = undefined;
    var win: c.Window = undefined;
    if (c.XGetWindowProperty(
        display,
        c.DefaultRootWindow(display),
        atom,
        0,
        1,
        0,
        c.XA_WINDOW,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_after,
        &prop,
    ) == c.Success) {
        defer _ = c.XFree(prop);
        if (0 < nitems)
            win = @as(*c.Window, @ptrCast(@alignCast(prop))).*;
    }
    if (win == 0) return 0;
    atom = c.XInternAtom(display, "_NET_WM_PID", 1);
    if (atom == c.None) return 0;
    if (c.XGetWindowProperty(
        display,
        win,
        atom,
        0,
        1,
        0,
        c.XA_CARDINAL,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_after,
        &prop,
    ) == c.Success) {
        defer _ = c.XFree(prop);
        if (0 < nitems)
            return @as(*c.pid_t, @ptrCast(@alignCast(prop))).*;
    }
    return 0;
}
