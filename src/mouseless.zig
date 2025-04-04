const std = @import("std");
const go = @import("gobject.zig");
const icon = @import("icon.zig");
const msg = @import("message.zig");
const c = @cImport({
    @cInclude("X11/Xatom.h");
    @cInclude("X11/extensions/XTest.h");
    @cInclude("at-spi-2.0/atspi/atspi.h");
    @cInclude("fcntl.h");
    @cInclude("gtk-3.0/gtk/gtk.h");
    @cInclude("semaphore.h");
});

const Click = enum {
    double,
    middle,
    single,
};

var window: *c.GtkWidget = undefined;
var display: ?*c.Display = undefined;
var fixed: *c.GtkWidget = undefined;
var entry: *c.GtkWidget = undefined;

var count: usize = 0;
const chars = ";ALSKDJFIWOE";
const Point = struct { x: c_int, y: c_int };
var map = std.StringHashMap(Point).init(std.heap.page_allocator);

var shm: c_int = undefined;
var mmap: []align(std.mem.page_size) u8 = undefined;
var sem: [*c]c.sem_t = undefined;

pub fn init() !void {
    shm = std.c.shm_open("mouseless", c.O_CREAT | c.O_EXCL | c.O_RDWR, 0o0666);
    if (shm < 0) {
        std.log.err("shm_open failed: {d}", .{shm});
        return error.ShmOpen;
    }
    sem = c.sem_open("mouseless", c.O_CREAT, @as(c.mode_t, 0o0666), @as(c_uint, 0));
    if (sem == c.SEM_FAILED) {
        std.log.err("sem_open failed", .{});
        return error.SemOpen;
    }
    if (std.c.ftruncate(shm, msg.size) != 0) {
        std.log.err("shm ftruncate failed", .{});
        return error.Ftruncate;
    }
    mmap = try std.posix.mmap(
        null,
        msg.size,
        std.posix.PROT.READ,
        .{ .TYPE = .SHARED },
        shm,
        0,
    );
    display = c.XOpenDisplay(null);
    if (display == null) {
        std.log.err("XOpenDisplay failed", .{});
        return error.XOpenDisplay;
    }
    map.ensureTotalCapacity(128) catch |e| {
        std.log.err("map allocation failed: {}", .{e});
        return e;
    };
}

pub fn gtk_init() !void {
    window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL);
    const path = try icon.get_path(icon.Size.x128, true, std.heap.page_allocator);
    defer std.heap.page_allocator.free(path);
    _ = c.gtk_window_set_default_icon_from_file(path.ptr, null);
    c.gtk_window_fullscreen(@ptrCast(window));
    go.g_signal_connect(window, "delete-event", @ptrCast(&hide), null);
    fixed = c.gtk_fixed_new();
    bind_keys();
    c.gtk_container_add(@ptrCast(window), fixed);
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
    std.posix.munmap(mmap);
    _ = std.c.shm_unlink("mouseless");
    _ = c.sem_close(sem);
    _ = c.sem_unlink("mouseless");
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

fn bind_keys() void {
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
    const click_double_closure = c.g_cclosure_new(
        @ptrCast(&click),
        c.GINT_TO_POINTER(@intFromEnum(Click.double)),
        null,
    );
    defer c.g_closure_unref(click_double_closure);
    c.gtk_accel_group_connect(
        accel_group,
        c.GDK_KEY_Return,
        c.GDK_CONTROL_MASK,
        0,
        click_double_closure,
    );
    const click_middle_closure = c.g_cclosure_new(
        @ptrCast(&click),
        c.GINT_TO_POINTER(@intFromEnum(Click.middle)),
        null,
    );
    defer c.g_closure_unref(click_middle_closure);
    c.gtk_accel_group_connect(
        accel_group,
        c.GDK_KEY_Return,
        c.GDK_MOD1_MASK,
        0,
        click_middle_closure,
    );
    const click_single_closure = c.g_cclosure_new(
        @ptrCast(&click),
        c.GINT_TO_POINTER(@intFromEnum(Click.single)),
        null,
    );
    defer c.g_closure_unref(click_single_closure);
    c.gtk_accel_group_connect(
        accel_group,
        c.GDK_KEY_Return,
        0,
        0,
        click_single_closure,
    );
    c.gtk_window_add_accel_group(@ptrCast(window), accel_group);
}

fn click(
    _: *c.GClosure,
    _: *c.GValue,
    _: c.guint,
    _: [*c]const c.GValue,
    data: c.gpointer,
    _: c.gpointer,
) void {
    const key = std.ascii.allocUpperString(
        std.heap.page_allocator,
        std.mem.span(c.gtk_entry_get_text(@ptrCast(entry))),
    ) catch {
        std.log.err("key allocation failed", .{});
        return;
    };
    defer std.heap.page_allocator.free(key);
    const pt = map.get(key) orelse return c.gtk_entry_set_text(@ptrCast(entry), "");
    clear();
    const root = c.DefaultRootWindow(display);
    _ = c.XWarpPointer(display, c.None, root, 0, 0, 0, 0, pt.x, pt.y);
    while (c.g_main_context_iteration(c.g_main_context_default(), c.FALSE) == 1) {}
    switch (@as(Click, @enumFromInt(c.GPOINTER_TO_INT(data)))) {
        Click.double => {
            _ = c.XTestFakeButtonEvent(display, 1, 1, c.CurrentTime);
            _ = c.XTestFakeButtonEvent(display, 1, 0, c.CurrentTime);
            _ = c.XTestFakeButtonEvent(display, 1, 1, c.CurrentTime);
            _ = c.XTestFakeButtonEvent(display, 1, 0, c.CurrentTime);
        },
        Click.middle => {
            _ = c.XTestFakeButtonEvent(display, 2, 1, c.CurrentTime);
            _ = c.XTestFakeButtonEvent(display, 2, 0, c.CurrentTime);
        },
        Click.single => {
            _ = c.XTestFakeButtonEvent(display, 1, 1, c.CurrentTime);
            _ = c.XTestFakeButtonEvent(display, 1, 0, c.CurrentTime);
        },
    }
    _ = c.XFlush(display);
}

pub fn run(running: *bool) !void {
    while (running.*) {
        _ = c.sem_wait(sem);
        switch (@as(msg.Type, @enumFromInt(mmap[0..1][0]))) {
            msg.Type.clean => clear(),
            msg.Type.show => {
                if (find_active_window())
                    c.gtk_widget_show_all(window);
            },
        }
    }
}

fn find_active_window() bool {
    entry = c.gtk_entry_new();
    const pid = active_pid();
    for (0..@intCast(c.atspi_get_desktop_count())) |i| {
        const desktop: ?*c.AtspiAccessible = c.atspi_get_desktop(@intCast(i));
        for (0..child_count(desktop)) |j| {
            const app = c.atspi_accessible_get_child_at_index(desktop, @intCast(j), null);
            defer c.g_object_unref(app);
            for (0..child_count(app)) |k| {
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
            const buffer = std.heap.page_allocator.alloc(u8, 4) catch |e| {
                std.log.err("key buffer allocation failed: {}", .{e});
                return;
            };
            defer std.heap.page_allocator.free(buffer);
            const key = std.heap.page_allocator.dupe(
                u8,
                buffer[0..create_key(buffer)],
            ) catch |e| {
                std.log.err("key copy failed: {}", .{e});
                return;
            };
            map.put(key, Point{
                .x = @divFloor(2 * pos.*.x + size.*.x, 2),
                .y = @divFloor(2 * pos.*.y + size.*.y, 2),
            }) catch |e| {
                std.log.err("point allocation failed: {}", .{e});
                return;
            };
            count += 1;
            const label = c.gtk_label_new(@ptrCast(key));
            c.gtk_fixed_put(@ptrCast(fixed), label, pos.*.x, pos.*.y);
        }
    }
    for (0..child_count(obj)) |i| {
        label_object(
            c.atspi_accessible_get_child_at_index(obj, @intCast(i), null),
        );
    }
}

fn child_count(child: ?*c.AtspiAccessible) usize {
    const index = c.atspi_accessible_get_child_count(child, null);
    if (index == -1) {
        const role = c.atspi_accessible_get_role_name(child, null);
        defer c.g_free(role);
        const name = c.atspi_accessible_get_name(child, null);
        defer c.g_free(name);
        std.log.warn("failed to get child count for ({s}, {s})", .{ role, name });
        return 0;
    }
    return @intCast(index);
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

pub fn reset() void {
    _ = std.c.shm_unlink("mouseless");
    _ = c.sem_unlink("mouseless");
}
