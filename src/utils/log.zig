const std = @import("std");
const c = @cImport({
    @cInclude("libnotify/notify.h");
    @cInclude("syslog.h");
});

var print: bool = false;

pub fn init(console_log: bool) void {
    print = console_log;
    _ = c.notify_init("MouselessDesktop");
}

pub fn deinit() void {
    c.notify_uninit();
}

pub fn logger(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_name = if (scope == .default) "" else "(" ++ @tagName(scope) ++ "): ";
    if (print and @import("builtin").mode == .Debug) {
        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();
        const stderr = std.io.getStdErr().writer();
        nosuspend stderr.print(
            @tagName(level) ++ "|" ++ scope_name ++ format ++ "\n",
            args,
        ) catch return;
    }
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(
        &buf,
        scope_name ++ format,
        args,
    ) catch return;
    if (@intFromEnum(level) < @intFromEnum(std.log.Level.info)) {
        const note = c.notify_notification_new("MouselessDesktop", msg.ptr, null);
        _ = c.notify_notification_show(note, null);
        _ = c.g_object_unref(note);
    }
    c.syslog(switch (level) {
        .err => c.LOG_ERR,
        .warn => c.LOG_WARNING,
        .info => c.LOG_INFO,
        .debug => c.LOG_DEBUG,
    }, "%s", msg.ptr);
}
