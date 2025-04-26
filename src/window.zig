const go = @import("gobject.zig");
const queue = @import("queue.zig");
const std = @import("std");

const c = @cImport({
    @cInclude("X11/extensions/XTest.h");
    @cInclude("gtk-3.0/gtk/gtk.h");
});

const Click = enum {
    double,
    middle,
    single,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var window: *c.GtkWidget = undefined;
var fixed: *c.GtkWidget = undefined;
var entry: *c.GtkWidget = undefined;
var display: ?*c.Display = undefined;

var count: usize = 0;
const chars = ";ALSKDJFIWOE";
var key_buf: [4]u8 = [_]u8{ 0, 0, 0, 0 };
var map = std.StringHashMap(queue.Point).init(allocator);

pub fn init() !void {
    queue.init() catch |e| {
        return e;
    };
    display = c.XOpenDisplay(null);
    if (display == null) {
        std.log.err("XOpenDisplay failed", .{});
        return error.XOpenDisplay;
    }
    window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL);
    c.gtk_window_fullscreen(@ptrCast(window));
    c.gtk_window_set_skip_taskbar_hint(@ptrCast(window), 1);
    go.gSignalConnect(window, "delete-event", &c.gtk_main_quit, null);
    fixed = c.gtk_fixed_new();
    entry = c.gtk_entry_new();
    go.gSignalConnect(entry, "focus-out-event", &c.gtk_main_quit, null);
    bindKeys();
    c.gtk_container_add(@ptrCast(window), fixed);
    const screen = c.gtk_window_get_screen(@ptrCast(window));
    const visual = c.gdk_screen_get_rgba_visual(screen);
    if (visual != null) c.gtk_widget_set_visual(window, visual);
    const css_provider = c.gtk_css_provider_new();
    _ = c.gtk_css_provider_load_from_data(css_provider, @embedFile("styles.css"), -1, null);
    c.gtk_style_context_add_provider_for_screen(
        screen,
        @ptrCast(css_provider),
        c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
}

pub fn deinit() void {
    map.deinit();
    _ = c.XCloseDisplay(display);
    c.gtk_widget_destroy(window);
}

pub fn run() void {
    while (true) {
        if (queue.pop()) |msg| {
            switch (msg.type) {
                .done => return c.gtk_widget_show_all(window),
                .entry => c.gtk_fixed_put(
                    @ptrCast(fixed),
                    @ptrCast(entry),
                    msg.pos.x,
                    msg.pos.y,
                ),
                .point => {
                    const key = allocator.dupeZ(
                        u8,
                        key_buf[0..createKey()],
                    ) catch |e| {
                        std.log.err("key copy failed: {}", .{e});
                        return;
                    };
                    map.put(key, .{
                        .x = @divFloor(2 * msg.pos.x + msg.size.x, 2),
                        .y = @divFloor(2 * msg.pos.y + msg.size.y, 2),
                    }) catch |e| {
                        std.log.err("point allocation failed: {}", .{e});
                        return;
                    };
                    const label = c.gtk_label_new(@ptrCast(key));
                    c.gtk_fixed_put(@ptrCast(fixed), label, msg.pos.x, msg.pos.y);
                },
                .quit => return c.gtk_main_quit(),
            }
        } else std.time.sleep(100_000_000);
    }
}

fn bindKeys() void {
    const accel_group = c.gtk_accel_group_new();
    defer c.g_object_unref(@ptrCast(accel_group));
    const clear_closure = c.g_cclosure_new(
        &c.gtk_main_quit,
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
        allocator,
        std.mem.span(c.gtk_entry_get_text(@ptrCast(entry))),
    ) catch {
        std.log.err("key allocation failed", .{});
        return;
    };
    defer allocator.free(key);
    const pt = map.get(key) orelse return c.gtk_entry_set_text(@ptrCast(entry), "");
    c.gtk_widget_hide(window);
    c.gtk_main_quit();
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

fn createKey() u8 {
    defer count += 1;
    if (count == 0) {
        key_buf[0] = chars[0];
        return 1;
    }
    const base = chars.len;
    var i: usize = count;
    var j: u8 = 0;
    while (0 < i) : (i = @divFloor(i, base)) {
        key_buf[j] = chars[i % base];
        j += 1;
    }
    return j;
}
