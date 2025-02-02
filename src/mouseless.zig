const std = @import("std");
const go = @import("gobject.zig");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
    @cInclude("at-spi-2.0/atspi/atspi.h");
    @cInclude("gtk-3.0/gtk/gtk.h");
});

var window: *c.GtkWidget = undefined;
var display: ?*c.Display = undefined;
var fixed: *c.GtkWidget = undefined;

var count: usize = 0;
const chars = ";alskdjfiwoe";
const Point = struct { x: c_int, y: c_int };
var map = std.StringHashMap(Point).init(std.heap.page_allocator);

pub fn init() !void {
    display = c.XOpenDisplay(null);
    if (display == null) {
        std.debug.print("Unable to open display\n", .{});
        return error.UnableToOpenDisplay;
    }
    window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL);
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
                find_active_window();
                c.gtk_widget_show_all(window);
            }
        }
    }
}

fn find_active_window() void {
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
                if (c.atspi_state_set_contains(states, c.ATSPI_STATE_ACTIVE) == 1) {
                    label_object(win);
                    return;
                }
            }
        }
    }
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
            const pos = c.atspi_component_get_position(
                c.atspi_accessible_get_component_iface(obj),
                c.ATSPI_COORD_TYPE_SCREEN,
                null,
            );
            defer c.g_free(pos);
            var buffer = std.heap.page_allocator.alloc(u8, 4) catch unreachable;
            create_key(&buffer);
            map.put(buffer, Point{ .x = pos.*.x, .y = pos.*.y }) catch unreachable;
            count += 1;
            const label = c.gtk_label_new(@ptrCast(buffer));
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

fn create_key(buf: *[]u8) void {
    if (count == 0) {
        buf.ptr[0] = chars[0];
        buf.ptr[1] = 0;
        return;
    }
    const base = chars.len;
    var i: usize = count;
    var j: u8 = 0;
    while (0 < i) : (i = @divFloor(i, base)) {
        buf.ptr[j] = chars[i % base];
        j += 1;
    }
    buf.ptr[j] = 0;
}
