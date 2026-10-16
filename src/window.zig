const go = @import("gobject.zig");
const gtk = @import("gtk");
const queue = @import("queue.zig");
const std = @import("std");
const uinput = @import("uinput");

const Mapping = struct {
    binding: [*c]const u8,
    data: u32,
    func: fn (
        [*c]gtk.struct__GtkWidget,
        ?*gtk.struct__GVariant,
        ?*anyopaque,
    ) callconv(.c) c_int,
};

var main_loop: ?*gtk.GMainLoop = undefined;
var controller: ?*gtk.GtkEventController = undefined;
var window: *gtk.GtkWindow = undefined;
var fixed: *gtk.GtkWidget = undefined;
var entry: *gtk.GtkWidget = undefined;
var height: c_int = 0;
var width: c_int = 0;

var count: usize = 0;
const chars = ";ALSKDJFIWOE";
var key_buf: [4]u8 = undefined;
var map: std.hash_map.StringHashMap(queue.Point) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    map = .init(allocator);
    map.ensureTotalCapacity(128) catch |err| {
        std.log.err("map allocation failed: {}", .{err});
        return err;
    };
    gtk.gtk_init();
    window = @ptrCast(gtk.gtk_window_new());
    gtk.gtk_window_fullscreen(window);
    gtk.gtk_window_set_decorated(window, 0);
    gtk.gtk_window_set_resizable(window, 0);
    controller = gtk.gtk_shortcut_controller_new();
    gtk.gtk_widget_add_controller(
        @ptrCast(window),
        controller,
    );
    go.gSignalConnect(
        window,
        "notify::is-active",
        gtk.G_CALLBACK(check_focus),
        null,
    );
    bindKeys();
    fixed = gtk.gtk_fixed_new();
    entry = gtk.gtk_entry_new();
    gtk.gtk_widget_set_size_request(
        entry,
        100,
        -1,
    );
    go.gSignalConnect(
        entry,
        "activate",
        gtk.G_CALLBACK(left_click),
        null,
    );
    gtk.gtk_window_set_child(
        window,
        fixed,
    );
    const display = gtk.gtk_widget_get_display(
        @ptrCast(window),
    );
    const monitors = gtk.gdk_display_get_monitors(display);
    if (0 < gtk.g_list_model_get_n_items(monitors)) {
        const monitor = gtk.g_list_model_get_item(
            monitors,
            0,
        );
        defer gtk.g_object_unref(monitor);
        var geometry: gtk.GdkRectangle = undefined;
        gtk.gdk_monitor_get_geometry(
            @ptrCast(monitor),
            &geometry,
        );
        width = geometry.width;
        height = geometry.height;
    }
    const css_provider = gtk.gtk_css_provider_new();
    gtk.gtk_css_provider_load_from_data(
        css_provider,
        @embedFile("styles.css"),
        -1,
    );
    gtk.gtk_style_context_add_provider_for_display(
        display,
        @ptrCast(css_provider),
        gtk.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
    gtk.g_object_unref(css_provider);
    main_loop = gtk.g_main_loop_new(null, 0);
    const focus = gtk.gtk_event_controller_focus_new();
    gtk.gtk_widget_add_controller(
        @ptrCast(window),
        focus,
    );
}

pub fn deinit() void {
    map.deinit();
    gtk.gtk_window_destroy(window);
}

fn left_click(
    _: [*c]gtk.GtkEntry,
    _: gtk.gpointer,
) callconv(.c) c_int {
    _ = click(
        null,
        null,
        gtk.GINT_TO_POINTER(
            uinput.BTN_LEFT,
        ),
    );
    return 0;
}

fn check_focus(
    _: [*c]gtk.GObject,
    _: [*c]gtk.GParamSpec,
    _: gtk.gpointer,
) callconv(.c) void {
    if (gtk.gtk_window_is_active(window) != 1) {
        gtk.g_main_loop_quit(main_loop);
    }
}

pub fn run(
    io: std.Io,
    allocator: std.mem.Allocator,
) void {
    while (true) {
        const msg = queue.pop(io);
        switch (msg.type) {
            .Done => {
                gtk.gtk_window_present(@ptrCast(window));
                _ = gtk.gtk_widget_grab_focus(entry);
                gtk.g_main_loop_run(main_loop);
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

fn exit(
    _: [*c]gtk.GtkWidget,
    _: ?*gtk.GVariant,
    _: gtk.gpointer,
) callconv(.c) c_int {
    std.posix.system.exit(0);
    return 0;
}

fn bindKeys() void {
    const mappings: [3]Mapping = .{
        .{
            .binding = "Escape",
            .data = 0,
            .func = exit,
        },
        .{
            .binding = "<Alt>Return",
            .data = uinput.BTN_RIGHT,
            .func = click,
        },
        .{
            .binding = "<Control>Return",
            .data = uinput.BTN_MIDDLE,
            .func = click,
        },
    };
    inline for (mappings) |mapping| {
        const action = gtk.gtk_callback_action_new(
            mapping.func,
            gtk.GINT_TO_POINTER(mapping.data),
            null,
        );
        const trigger = gtk.gtk_shortcut_trigger_parse_string(
            mapping.binding,
        );
        const shortcut = gtk.gtk_shortcut_new(
            trigger,
            action,
        );
        gtk.gtk_shortcut_controller_add_shortcut(
            @ptrCast(controller),
            shortcut,
        );
    }
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
    _: [*c]gtk.GtkWidget,
    _: ?*gtk.GVariant,
    data: gtk.gpointer,
) callconv(.c) c_int {
    const buffer = gtk.gtk_entry_get_buffer(@ptrCast(entry));
    const key = std.ascii.allocUpperString(
        std.heap.c_allocator,
        std.mem.span(
            gtk.gtk_entry_buffer_get_text(
                buffer,
            ),
        ),
    ) catch {
        std.log.err("key allocation failed", .{});
        return 1;
    };
    defer std.heap.c_allocator.free(key);
    const pt = map.get(key) orelse {
        gtk.gtk_entry_set_buffer(@ptrCast(entry), null);
        return 1;
    };
    gtk.gtk_widget_set_visible(@ptrCast(window), 0);
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
    return 0;
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
