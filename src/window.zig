const go = @import("gobject.zig");
const queue = @import("queue.zig");
const std = @import("std");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("gtk-3.0/gtk/gtk.h");
    @cInclude("linux/uinput.h");
});

const Click = enum {
    left,
    middle,
    right,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var window: *c.GtkWidget = undefined;
var fixed: *c.GtkWidget = undefined;
var entry: *c.GtkWidget = undefined;
var height: c_int = 0;
var width: c_int = 0;

var count: usize = 0;
const chars = ";ALSKDJFIWOE";
var key_buf: [4]u8 = [_]u8{ 0, 0, 0, 0 };
var map = std.StringHashMap(queue.Point).init(allocator);

pub fn init() void {
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
    height = c.gdk_screen_get_height(screen);
    width = c.gdk_screen_get_width(screen);
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
        } else std.Thread.sleep(100 * std.time.ns_per_ms);
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
    const right_click_closure = c.g_cclosure_new(
        @ptrCast(&click),
        c.GINT_TO_POINTER(@intFromEnum(Click.right)),
        null,
    );
    defer c.g_closure_unref(right_click_closure);
    c.gtk_accel_group_connect(
        accel_group,
        c.GDK_KEY_Return,
        c.GDK_CONTROL_MASK,
        0,
        right_click_closure,
    );
    const middle_click_closure = c.g_cclosure_new(
        @ptrCast(&click),
        c.GINT_TO_POINTER(@intFromEnum(Click.middle)),
        null,
    );
    defer c.g_closure_unref(middle_click_closure);
    c.gtk_accel_group_connect(
        accel_group,
        c.GDK_KEY_Return,
        c.GDK_MOD1_MASK,
        0,
        middle_click_closure,
    );
    const left_click_closure = c.g_cclosure_new(
        @ptrCast(&click),
        c.GINT_TO_POINTER(@intFromEnum(Click.left)),
        null,
    );
    defer c.g_closure_unref(left_click_closure);
    c.gtk_accel_group_connect(
        accel_group,
        c.GDK_KEY_Return,
        0,
        0,
        left_click_closure,
    );
    c.gtk_window_add_accel_group(@ptrCast(window), accel_group);
}

fn uinput() c_int {
    const fd = c.open("/dev/uinput", c.O_WRONLY | c.O_NONBLOCK);
    if (fd < 0) {
        std.log.err("Failed to open /dev/uinput", .{});
        std.posix.exit(1);
    }
    _ = c.ioctl(fd, c.UI_SET_EVBIT, c.EV_KEY);
    var name: [80]u8 = undefined;
    @memcpy(name[0..9], "mouseless");
    _ = c.ioctl(
        fd,
        c.UI_DEV_SETUP,
        &c.uinput_setup{ .name = name },
    );
    return fd;
}

fn emit(
    fd: c_int,
    ev_type: c_ushort,
    code: c_ushort,
    val: c_int,
) void {
    _ = c.write(
        fd,
        &c.input_event{
            .type = ev_type,
            .code = code,
            .value = val,
            .time = .{
                .tv_sec = 0,
                .tv_usec = 0,
            },
        },
        @sizeOf(c.input_event),
    );
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
    const pt = map.get(key) orelse
        return c.gtk_entry_set_text(@ptrCast(entry), "");
    c.gtk_widget_hide(window);
    c.gtk_main_quit();
    const fd = uinput();
    defer _ = c.close(fd);
    while (c.g_main_context_iteration(
        c.g_main_context_default(),
        c.FALSE,
    ) == 1) {}
    const btn: c_ushort = @intCast(switch (@as(
        Click,
        @enumFromInt(c.GPOINTER_TO_INT(data)),
    )) {
        Click.right => c.BTN_RIGHT,
        Click.middle => c.BTN_MIDDLE,
        Click.left => c.BTN_LEFT,
    });
    _ = c.ioctl(fd, c.UI_SET_KEYBIT, btn);
    _ = c.ioctl(fd, c.UI_SET_EVBIT, c.EV_ABS);
    _ = c.ioctl(fd, c.UI_SET_ABSBIT, c.ABS_X);
    _ = c.ioctl(fd, c.UI_SET_ABSBIT, c.ABS_Y);
    var abs_setup = c.uinput_abs_setup{
        .code = c.ABS_X,
        .absinfo = .{
            .minimum = 0,
            .maximum = width,
        },
    };
    _ = c.ioctl(fd, c.UI_ABS_SETUP, &abs_setup);
    abs_setup.code = c.ABS_Y;
    abs_setup.absinfo.maximum = height;
    _ = c.ioctl(fd, c.UI_ABS_SETUP, &abs_setup);
    _ = c.ioctl(fd, c.UI_DEV_CREATE);
    std.Thread.sleep(500 * std.time.ns_per_ms);
    while (c.g_main_context_iteration(c.g_main_context_default(), 0) == 1) {}
    emit(fd, c.EV_ABS, c.ABS_X, pt.x);
    emit(fd, c.EV_ABS, c.ABS_Y, pt.y);
    emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
    std.Thread.sleep(100 * std.time.ns_per_ms);
    emit(fd, c.EV_KEY, btn, 1);
    emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
    std.Thread.sleep(100 * std.time.ns_per_ms);
    emit(fd, c.EV_KEY, btn, 0);
    emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
    std.Thread.sleep(500 * std.time.ns_per_ms);
    _ = c.ioctl(fd, c.UI_DEV_DESTROY);
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
