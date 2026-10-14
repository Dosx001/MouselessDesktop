const log = @import("log");
const std = @import("std");

pub fn init() void {
    _ = log.notify_init("MouselessDesktop");
}

pub fn deinit() void {
    log.notify_uninit();
}

pub fn logger(
    comptime level: std.log.Level,
    comptime _: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrintSentinel(
        &buf,
        format,
        args,
        0,
    ) catch |err| {
        std.log.err("Failed to format log message: {}", .{err});
        return;
    };
    const tty = 1 == std.posix.system.isatty(
        std.posix.system.STDERR_FILENO,
    );
    if (tty) {
        // const io = std.Options.debug_io;
        // const prev = io.swapCancelProtection(.blocked);
        // defer _ = io.swapCancelProtection(prev);
        // const stderr = std.debug.lockStderr(&buf).terminal();
        // defer std.debug.unlockStderr();
        // std.log.defaultLogFileTerminal(level, scope, format, args, stderr) catch |err| {
        //     std.log.err("Failed to write log message: {}", .{err});
        //     return;
        // };
        _ = std.c.printf("%s\n", msg.ptr);
    }
    if (@intFromEnum(level) < @intFromEnum(std.log.Level.info)) {
        const note = log.notify_notification_new("MouselessDesktop", msg.ptr, null);
        _ = log.notify_notification_show(note, null);
        _ = log.g_object_unref(note);
    }
    if (tty) return;
    log.syslog(switch (level) {
        .err => log.LOG_ERR,
        .warn => log.LOG_WARNING,
        .info => log.LOG_INFO,
        .debug => log.LOG_DEBUG,
    }, "%s", msg.ptr);
}
