const queue = @import("queue.zig");
const std = @import("std");

const c = @cImport({
    @cInclude("X11/Xatom.h");
    @cInclude("X11/Xlib.h");
    @cInclude("at-spi-2.0/atspi/atspi.h");
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
        .type = if (findActiveWindow()) .done else .quit,
        .size = .{ .x = 0, .y = 0 },
        .pos = .{ .x = 0, .y = 0 },
    });
}

fn findActiveWindow() bool {
    const pid = activePid();
    for (0..@intCast(c.atspi_get_desktop_count())) |i| {
        const desktop: ?*c.AtspiAccessible = c.atspi_get_desktop(@intCast(i));
        for (0..childCount(desktop)) |j| {
            const app = c.atspi_accessible_get_child_at_index(desktop, @intCast(j), null);
            defer c.g_object_unref(app);
            if (pid != c.atspi_accessible_get_process_id(
                app,
                null,
            )) continue;
            for (0..childCount(app)) |k| {
                const win = c.atspi_accessible_get_child_at_index(app, @intCast(k), null);
                defer c.g_object_unref(win);
                const states = c.atspi_accessible_get_state_set(win);
                defer c.g_object_unref(states);
                if (c.atspi_state_set_contains(
                    states,
                    c.ATSPI_STATE_ACTIVE,
                ) != 1) continue;
                const pos = c.atspi_component_get_position(
                    c.atspi_accessible_get_component_iface(win),
                    c.ATSPI_COORD_TYPE_SCREEN,
                    null,
                );
                defer c.g_free(pos);
                queue.push(queue.Message{
                    .type = .entry,
                    .pos = .{
                        .x = pos.*.x,
                        .y = pos.*.y,
                    },
                    .size = .{
                        .x = 0,
                        .y = 0,
                    },
                });
                const collection = c.atspi_accessible_get_collection(win);
                defer c.g_object_unref(collection);
                if (collection == null) {
                    parseChild(win);
                } else parseCollection(collection);
                return true;
            }
        }
    }
    std.log.warn("No active window found for pid {}", .{pid});
    return false;
}

fn parseCollection(collection: [*c]c.AtspiCollection) void {
    const states = [_]c.AtspiStateType{ c.ATSPI_STATE_SHOWING, c.ATSPI_STATE_VISIBLE };
    const s_array = c.g_array_new(0, 0, @sizeOf(c.AtspiStateType));
    defer _ = c.g_array_free(s_array, 1);
    const state_set = c.atspi_state_set_new(c.g_array_append_vals(
        s_array,
        @ptrCast(&states),
        states.len,
    ));
    defer c.g_object_unref(state_set);
    const roles = [_]c.AtspiRole{
        c.ATSPI_ROLE_CHECK_BOX,
        c.ATSPI_ROLE_LINK,
        c.ATSPI_ROLE_LIST_ITEM,
        c.ATSPI_ROLE_MENU_ITEM,
        c.ATSPI_ROLE_PAGE_TAB,
        c.ATSPI_ROLE_PUSH_BUTTON,
        c.ATSPI_ROLE_PUSH_BUTTON_MENU,
        c.ATSPI_ROLE_RADIO_BUTTON,
        c.ATSPI_ROLE_TOGGLE_BUTTON,
    };
    const r_array = c.g_array_new(0, 0, @sizeOf(c.AtspiRole));
    defer _ = c.g_array_free(r_array, 1);
    const rule = c.atspi_match_rule_new(
        state_set,
        c.ATSPI_Collection_MATCH_ALL,
        null,
        c.ATSPI_Collection_MATCH_NONE,
        c.g_array_append_vals(
            r_array,
            @ptrCast(&roles),
            roles.len,
        ),
        c.ATSPI_Collection_MATCH_ANY,
        null,
        c.ATSPI_Collection_MATCH_NONE,
        0,
    );
    defer c.g_object_unref(rule);
    const matches = c.atspi_collection_get_matches(
        collection,
        rule,
        c.ATSPI_Collection_SORT_ORDER_CANONICAL,
        0,
        1,
        null,
    );
    defer c.g_object_unref(matches);
    const data: [*c][*c]c.AtspiAccessible = @ptrCast(@alignCast(matches.*.data));
    for (0..matches.*.len) |i| sendPoint(data[i]);
}

fn parseChild(obj: ?*c.AtspiAccessible) void {
    if (obj == null) return;
    const states = c.atspi_accessible_get_state_set(obj);
    defer c.g_object_unref(states);
    if (c.atspi_state_set_contains(
        states,
        c.ATSPI_STATE_VISIBLE,
    ) != 1 or c.atspi_state_set_contains(
        states,
        c.ATSPI_STATE_SHOWING,
    ) != 1) return;
    if (checkRole(obj)) sendPoint(obj);
    for (0..childCount(obj)) |i| {
        parseChild(
            c.atspi_accessible_get_child_at_index(obj, @intCast(i), null),
        );
    }
}

fn sendPoint(obj: ?*c.AtspiAccessible) void {
    const comp = c.atspi_accessible_get_component_iface(obj);
    const size = c.atspi_component_get_size(comp, null);
    defer c.g_free(size);
    const pos = c.atspi_component_get_position(comp, c.ATSPI_COORD_TYPE_SCREEN, null);
    defer c.g_free(pos);
    queue.push(.{
        .type = .point,
        .pos = .{
            .x = pos.*.x,
            .y = pos.*.y,
        },
        .size = .{
            .x = size.*.x,
            .y = size.*.y,
        },
    });
}

fn childCount(child: ?*c.AtspiAccessible) usize {
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

fn checkRole(obj: ?*c.AtspiAccessible) bool {
    return switch (c.atspi_accessible_get_role(obj, null)) {
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

fn activePid() c_int {
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
