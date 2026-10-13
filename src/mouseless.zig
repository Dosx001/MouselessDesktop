const atspi = @import("atspi");
const queue = @import("queue.zig");
const std = @import("std");

var display: ?*atspi.Display = undefined;

pub fn init() !void {
    display = atspi.XOpenDisplay(null);
    if (display == null) {
        std.log.err("XOpenDisplay failed", .{});
        return error.XOpenDisplay;
    }
}

pub fn deinit() void {
    _ = atspi.XCloseDisplay(display);
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
    for (0..@intCast(atspi.atspi_get_desktop_count())) |i| {
        const desktop: ?*atspi.AtspiAccessible = atspi.atspi_get_desktop(
            @intCast(i),
        );
        for (0..childCount(desktop)) |j| {
            const app = atspi.atspi_accessible_get_child_at_index(
                desktop,
                @intCast(j),
                null,
            );
            defer atspi.g_object_unref(app);
            if (pid != atspi.atspi_accessible_get_process_id(
                app,
                null,
            )) continue;
            for (0..childCount(app)) |k| {
                const win = atspi.atspi_accessible_get_child_at_index(
                    app,
                    @intCast(k),
                    null,
                );
                defer atspi.g_object_unref(win);
                const states = atspi.atspi_accessible_get_state_set(win);
                defer atspi.g_object_unref(states);
                if (atspi.atspi_state_set_contains(
                    states,
                    atspi.ATSPI_STATE_ACTIVE,
                ) != 1) continue;
                const pos = atspi.atspi_component_get_position(
                    atspi.atspi_accessible_get_component_iface(win),
                    atspi.ATSPI_COORD_TYPE_SCREEN,
                    null,
                );
                defer atspi.g_free(pos);
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
                const collection = atspi.atspi_accessible_get_collection(win);
                if (collection != null) {
                    parseCollection(collection);
                    atspi.g_object_unref(collection);
                } else parseChild(win);
                return true;
            }
        }
    }
    _ = std.c.printf("No active window found for pid %d\n", pid);
    return false;
}

fn parseCollection(collection: [*c]atspi.AtspiCollection) void {
    const states = [_]atspi.AtspiStateType{
        atspi.ATSPI_STATE_SHOWING,
        atspi.ATSPI_STATE_VISIBLE,
    };
    const s_array = atspi.g_array_new(
        0,
        0,
        @sizeOf(atspi.AtspiStateType),
    );
    defer _ = atspi.g_array_free(s_array, 1);
    const state_set = atspi.atspi_state_set_new(atspi.g_array_append_vals(
        s_array,
        @ptrCast(&states),
        states.len,
    ));
    defer atspi.g_object_unref(state_set);
    const roles = [_]atspi.AtspiRole{
        atspi.ATSPI_ROLE_CHECK_BOX,
        atspi.ATSPI_ROLE_LINK,
        atspi.ATSPI_ROLE_LIST_ITEM,
        atspi.ATSPI_ROLE_MENU_ITEM,
        atspi.ATSPI_ROLE_PAGE_TAB,
        atspi.ATSPI_ROLE_PUSH_BUTTON,
        atspi.ATSPI_ROLE_PUSH_BUTTON_MENU,
        atspi.ATSPI_ROLE_RADIO_BUTTON,
        atspi.ATSPI_ROLE_TOGGLE_BUTTON,
    };
    const r_array = atspi.g_array_new(
        0,
        0,
        @sizeOf(atspi.AtspiRole),
    );
    defer _ = atspi.g_array_free(r_array, 1);
    const rule = atspi.atspi_match_rule_new(
        state_set,
        atspi.ATSPI_Collection_MATCH_ALL,
        null,
        atspi.ATSPI_Collection_MATCH_NONE,
        atspi.g_array_append_vals(
            r_array,
            @ptrCast(&roles),
            roles.len,
        ),
        atspi.ATSPI_Collection_MATCH_ANY,
        null,
        atspi.ATSPI_Collection_MATCH_NONE,
        0,
    );
    defer atspi.g_object_unref(rule);
    const matches = atspi.atspi_collection_get_matches(
        collection,
        rule,
        atspi.ATSPI_Collection_SORT_ORDER_CANONICAL,
        0,
        1,
        null,
    );
    defer _ = atspi.g_array_free(matches, 1);
    const data: [*c][*c]atspi.AtspiAccessible = @ptrCast(@alignCast(matches.*.data));
    for (0..matches.*.len) |i| sendPoint(data[i]);
}

fn parseChild(obj: ?*atspi.AtspiAccessible) void {
    if (obj == null) return;
    const states = atspi.atspi_accessible_get_state_set(obj);
    defer atspi.g_object_unref(states);
    if (atspi.atspi_state_set_contains(
        states,
        atspi.ATSPI_STATE_VISIBLE,
    ) != 1 or atspi.atspi_state_set_contains(
        states,
        atspi.ATSPI_STATE_SHOWING,
    ) != 1) return;
    if (checkRole(obj)) sendPoint(obj);
    for (0..childCount(obj)) |i| {
        parseChild(
            atspi.atspi_accessible_get_child_at_index(
                obj,
                @intCast(i),
                null,
            ),
        );
    }
}

fn sendPoint(obj: ?*atspi.AtspiAccessible) void {
    const comp = atspi.atspi_accessible_get_component_iface(obj);
    defer atspi.g_object_unref(comp);
    const rect = atspi.atspi_component_get_extents(
        comp,
        atspi.ATSPI_COORD_TYPE_SCREEN,
        null,
    );
    defer atspi.g_free(rect);
    queue.push(.{
        .type = .point,
        .pos = .{
            .x = rect.*.x,
            .y = rect.*.y,
        },
        .size = .{
            .x = rect.*.width,
            .y = rect.*.height,
        },
    });
}

fn childCount(child: ?*atspi.AtspiAccessible) usize {
    const index = atspi.atspi_accessible_get_child_count(
        child,
        null,
    );
    if (index == -1) {
        const role = atspi.atspi_accessible_get_role_name(
            child,
            null,
        );
        defer atspi.g_free(role);
        const name = atspi.atspi_accessible_get_name(
            child,
            null,
        );
        defer atspi.g_free(name);
        std.log.warn(
            "failed to get child count for ({s}, {s})",
            .{ role, name },
        );
        return 0;
    }
    return @intCast(index);
}

fn checkRole(obj: ?*atspi.AtspiAccessible) bool {
    return switch (atspi.atspi_accessible_get_role(obj, null)) {
        atspi.ATSPI_ROLE_CHECK_BOX,
        atspi.ATSPI_ROLE_LINK,
        atspi.ATSPI_ROLE_LIST_ITEM,
        atspi.ATSPI_ROLE_MENU_ITEM,
        atspi.ATSPI_ROLE_PAGE_TAB,
        atspi.ATSPI_ROLE_PUSH_BUTTON,
        atspi.ATSPI_ROLE_PUSH_BUTTON_MENU,
        atspi.ATSPI_ROLE_RADIO_BUTTON,
        atspi.ATSPI_ROLE_TOGGLE_BUTTON,
        => true,
        else => false,
    };
}

fn activePid() c_int {
    var atom = atspi.XInternAtom(display, "_NET_ACTIVE_WINDOW", 1);
    if (atom == atspi.None) return 0;
    var actual_type: atspi.Atom = undefined;
    var actual_format: c_int = undefined;
    var nitems: c_ulong = undefined;
    var bytes_after: c_ulong = undefined;
    var prop: [*c]u8 = undefined;
    var win: atspi.Window = undefined;
    if (atspi.XGetWindowProperty(
        display,
        atspi.DefaultRootWindow(display),
        atom,
        0,
        1,
        0,
        atspi.XA_WINDOW,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_after,
        &prop,
    ) == atspi.Success) {
        defer _ = atspi.XFree(prop);
        if (0 < nitems)
            win = @as(
                *atspi.Window,
                @ptrCast(@alignCast(prop)),
            ).*;
    }
    if (win == 0) return 0;
    atom = atspi.XInternAtom(display, "_NET_WM_PID", 1);
    if (atom == atspi.None) return 0;
    if (atspi.XGetWindowProperty(
        display,
        win,
        atom,
        0,
        1,
        0,
        atspi.XA_CARDINAL,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_after,
        &prop,
    ) == atspi.Success) {
        defer _ = atspi.XFree(prop);
        if (0 < nitems)
            return @as(
                *atspi.pid_t,
                @ptrCast(@alignCast(prop)),
            ).*;
    }
    return 0;
}
