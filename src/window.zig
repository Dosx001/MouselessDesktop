const go = @import("gobject.zig");
const gtk = @import("gtk");
const queue = @import("queue.zig");
const std = @import("std");
const uinput = @import("uinput");

var window: *gtk.GtkWidget = undefined;
var fixed: *gtk.GtkWidget = undefined;
var entry: *gtk.GtkWidget = undefined;
var height: c_int = 0;
var width: c_int = 0;

var count: usize = 0;
const chars = ";ALSKDJFIWOE";
var key_buf: [4]u8 = [_]u8{ 0, 0, 0, 0 };
var map: std.hash_map.StringHashMap(queue.Point) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    map = .init(allocator);
    map.ensureTotalCapacity(128) catch |err| {
        std.log.err("map allocation failed: {}", .{err});
        return err;
    };
    gtk.gtk_init(0, null);
    window = gtk.gtk_window_new(gtk.GTK_WINDOW_TOPLEVEL);
    gtk.gtk_window_fullscreen(@ptrCast(window));
    gtk.gtk_window_set_skip_taskbar_hint(
        @ptrCast(window),
        1,
    );
    fixed = gtk.gtk_fixed_new();
    entry = gtk.gtk_entry_new();
    go.gSignalConnect(
        window,
        "focus-out-event",
        gtk.G_CALLBACK(quit),
        null,
    );
    bindKeys();
    gtk.gtk_container_add(@ptrCast(window), fixed);
    const screen = gtk.gtk_window_get_screen(@ptrCast(window));
    height = gtk.gdk_screen_get_height(screen);
    width = gtk.gdk_screen_get_width(screen);
    const visual = gtk.gdk_screen_get_rgba_visual(screen);
    if (visual != null) gtk.gtk_widget_set_visual(window, visual);
    const css_provider = gtk.gtk_css_provider_new();
    _ = gtk.gtk_css_provider_load_from_data(
        css_provider,
        @embedFile("styles.css"),
        -1,
        null,
    );
    gtk.gtk_style_context_add_provider_for_screen(
        screen,
        @ptrCast(css_provider),
        gtk.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
}

fn quit(
    _: *gtk.GtkWidget,
    _: *gtk.GdkEventFocus,
    _: gtk.gpointer,
) callconv(.c) void {
    gtk.gtk_main_quit();
}

pub fn deinit() void {
    map.deinit();
    gtk.gtk_widget_destroy(window);
}

pub fn run(io: std.Io, allocator: std.mem.Allocator) void {
    while (true) {
        const msg = queue.pop(io);
        switch (msg.type) {
            .Done => {
                gtk.gtk_widget_show_all(window);
                gtk.gtk_main();
                return;
            },
            .Entry => gtk.gtk_fixed_put(
                @ptrCast(fixed),
                entry,
                msg.pos.x,
                msg.pos.y,
            ),
            .Point => {
                @branchHint(.likely);
                const key = allocator.dupeSentinel(
                    u8,
                    key_buf[0..createKey()],
                    0,
                ) catch |err| {
                    std.log.err("key copy failed: {}", .{err});
                    return;
                };
                map.put(key, .{
                    .x = @divFloor(2 * msg.pos.x + msg.size.x, 2),
                    .y = @divFloor(2 * msg.pos.y + msg.size.y, 2),
                }) catch |err| {
                    std.log.err("point allocation failed: {}", .{err});
                    return;
                };
                const label = gtk.gtk_label_new(key);
                gtk.gtk_fixed_put(
                    @ptrCast(fixed),
                    label,
                    msg.pos.x,
                    msg.pos.y,
                );
            },
            .Quit => return,
        }
    }
}

fn bindKeys() void {
    const accel_group = gtk.gtk_accel_group_new();
    defer gtk.g_object_unref(@ptrCast(accel_group));
    const clear_closure = gtk.g_cclosure_new(
        gtk.G_CALLBACK(quit),
        null,
        null,
    );
    defer gtk.g_closure_unref(clear_closure);
    gtk.gtk_accel_group_connect(
        accel_group,
        gtk.GDK_KEY_Escape,
        0,
        0,
        clear_closure,
    );
    const right_click_closure = gtk.g_cclosure_new(
        gtk.G_CALLBACK(click),
        gtk.GINT_TO_POINTER(uinput.BTN_RIGHT),
        null,
    );
    defer gtk.g_closure_unref(right_click_closure);
    gtk.gtk_accel_group_connect(
        accel_group,
        gtk.GDK_KEY_Return,
        gtk.GDK_CONTROL_MASK,
        0,
        right_click_closure,
    );
    const middle_click_closure = gtk.g_cclosure_new(
        gtk.G_CALLBACK(click),
        gtk.GINT_TO_POINTER(uinput.BTN_MIDDLE),
        null,
    );
    defer gtk.g_closure_unref(middle_click_closure);
    gtk.gtk_accel_group_connect(
        accel_group,
        gtk.GDK_KEY_Return,
        gtk.GDK_MOD1_MASK,
        0,
        middle_click_closure,
    );
    const left_click_closure = gtk.g_cclosure_new(
        gtk.G_CALLBACK(click),
        gtk.GINT_TO_POINTER(uinput.BTN_LEFT),
        null,
    );
    defer gtk.g_closure_unref(left_click_closure);
    gtk.gtk_accel_group_connect(
        accel_group,
        gtk.GDK_KEY_Return,
        0,
        0,
        left_click_closure,
    );
    gtk.gtk_window_add_accel_group(
        @ptrCast(window),
        accel_group,
    );
}

fn uinput_init() c_int {
    const fd = uinput.open("/dev/uinput", uinput.O_WRONLY | uinput.O_NONBLOCK);
    if (fd < 0) {
        std.log.err("Failed to open /dev/uinput", .{});
        std.posix.system.exit(1);
    }
    _ = uinput.ioctl(fd, uinput.UI_SET_EVBIT, uinput.EV_KEY);
    var name: [80]u8 = @splat(0);
    @memcpy(name[0..9], "mouseless");
    _ = uinput.ioctl(
        fd,
        uinput.UI_DEV_SETUP,
        &uinput.uinput_setup{
            .name = name,
            .ff_effects_max = 0,
            .id = undefined,
        },
    );
    return fd;
}

fn emit(
    fd: c_int,
    ev_type: c_ushort,
    code: c_ushort,
    val: c_int,
) void {
    _ = std.c.write(
        fd,
        @ptrCast(&uinput.input_event{
            .type = ev_type,
            .code = code,
            .value = val,
            .time = undefined,
        }),
        @sizeOf(uinput.input_event),
    );
}

fn click(
    _: *gtk.GClosure,
    _: *gtk.GValue,
    _: gtk.guint,
    _: [*c]const gtk.GValue,
    data: gtk.gpointer,
    _: gtk.gpointer,
) callconv(.c) void {
    const key = std.ascii.allocUpperString(
        std.heap.c_allocator,
        std.mem.span(gtk.gtk_entry_get_text(@ptrCast(entry))),
    ) catch {
        std.log.err("key allocation failed", .{});
        return;
    };
    defer std.heap.c_allocator.free(key);
    const pt = map.get(key) orelse
        return gtk.gtk_entry_set_text(@ptrCast(entry), "");
    gtk.gtk_widget_hide(window);
    const fd = uinput_init();
    defer _ = std.c.close(fd);
    const btn: c_ushort = @intCast(gtk.GPOINTER_TO_INT(data));
    _ = uinput.ioctl(fd, uinput.UI_SET_KEYBIT, btn);
    _ = uinput.ioctl(fd, uinput.UI_SET_EVBIT, uinput.EV_ABS);
    _ = uinput.ioctl(fd, uinput.UI_SET_ABSBIT, uinput.ABS_X);
    _ = uinput.ioctl(fd, uinput.UI_SET_ABSBIT, uinput.ABS_Y);
    var abs_setup = uinput.uinput_abs_setup{
        .code = uinput.ABS_X,
        .absinfo = .{
            .minimum = 0,
            .maximum = width,
            .fuzz = 0,
            .flat = 0,
            .value = 0,
            .resolution = 0,
        },
    };
    _ = uinput.ioctl(fd, uinput.UI_ABS_SETUP, &abs_setup);
    abs_setup.code = uinput.ABS_Y;
    abs_setup.absinfo.maximum = height;
    _ = uinput.ioctl(fd, uinput.UI_ABS_SETUP, &abs_setup);
    _ = uinput.ioctl(fd, uinput.UI_DEV_CREATE);
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();
    std.Io.sleep(io, .fromMilliseconds(500), .awake) catch unreachable;
    while (gtk.g_main_context_iteration(gtk.g_main_context_default(), 0) == 1) {}
    emit(fd, uinput.EV_ABS, uinput.ABS_X, pt.x);
    emit(fd, uinput.EV_ABS, uinput.ABS_Y, pt.y);
    emit(fd, uinput.EV_SYN, uinput.SYN_REPORT, 0);
    std.Io.sleep(io, .fromMilliseconds(100), .awake) catch unreachable;
    emit(fd, uinput.EV_KEY, btn, 1);
    emit(fd, uinput.EV_SYN, uinput.SYN_REPORT, 0);
    std.Io.sleep(io, .fromMilliseconds(100), .awake) catch unreachable;
    emit(fd, uinput.EV_KEY, btn, 0);
    emit(fd, uinput.EV_SYN, uinput.SYN_REPORT, 0);
    std.Io.sleep(io, .fromMilliseconds(500), .awake) catch unreachable;
    _ = uinput.ioctl(fd, uinput.UI_DEV_DESTROY);
    std.posix.system.exit(0);
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
