const std = @import("std");
const icon = @import("icon.zig");
const c = @cImport({
    @cInclude("libnotify/notify.h");
    @cInclude("syslog.h");
});

pub fn logger(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_name = if (scope == .default) "" else "(" ++ @tagName(scope) ++ "): ";
    if (@import("builtin").mode == .Debug) {
        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();
        const stderr = std.io.getStdErr().writer();
        nosuspend stderr.print(
            @tagName(level) ++ "|" ++ scope_name ++ format ++ "\n",
            args,
        ) catch return;
    }
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &buf,
        scope_name ++ format,
        args,
    ) catch return;
    buf[msg.len] = 0;
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
