const go = @import("gobject.zig");
const queue = @import("queue.zig");
const std = @import("std");

const c = @cImport({
    @cInclude("X11/Xatom.h");
    @cInclude("X11/extensions/XTest.h");
    @cInclude("at-spi-2.0/atspi/atspi.h");
    @cInclude("gtk-3.0/gtk/gtk.h");
});

var display: ?*c.Display = undefined;

pub fn init() !void {
    display = c.XOpenDisplay(null);
    if (display == null) {
        std.log.err("XOpenDisplay failed", .{});
        return error.XOpenDisplay;
    }
}

pub fn deinit() void {
    _ = c.XCloseDisplay(display);
}

pub fn run() void {
    queue.push(queue.Message{
        .type = if (find_active_window()) .Show else .Done,
        .pt = .{ .x = 0, .y = 0 },
        .pos = .{ .x = 0, .y = 0 },
    });
}

fn find_active_window() bool {
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
                    queue.push(queue.Message{
                        .type = .Entry,
                        .pt = .{
                            .x = 0,
                            .y = 0,
                        },
                        .pos = .{
                            .x = pos.*.x,
                            .y = pos.*.y,
                        },
                    });
                    parse_child(win);
                    return true;
                }
            }
        }
    }
    std.log.warn("No active window found for pid {}", .{pid});
    return false;
}

fn parse_child(obj: ?*c.AtspiAccessible) void {
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
            queue.push(.{
                .type = .Point,
                .pt = .{
                    .x = @divFloor(2 * pos.*.x + size.*.x, 2),
                    .y = @divFloor(2 * pos.*.y + size.*.y, 2),
                },
                .pos = .{
                    .x = pos.*.x,
                    .y = pos.*.y,
                },
            });
        }
    }
    for (0..child_count(obj)) |i| {
        parse_child(
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
