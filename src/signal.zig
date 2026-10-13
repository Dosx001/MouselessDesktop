const std = @import("std");
const posix = std.posix;

pub fn init() void {
    var sa = posix.Sigaction{
        .handler = .{ .handler = quit },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.HUP, &sa, null);
    posix.sigaction(posix.SIG.INT, &sa, null);
    posix.sigaction(posix.SIG.QUIT, &sa, null);
    posix.sigaction(posix.SIG.TERM, &sa, null);
    sa.handler = .{ .handler = exit };
    posix.sigaction(posix.SIG.ILL, &sa, null);
    posix.sigaction(posix.SIG.ABRT, &sa, null);
    posix.sigaction(posix.SIG.SEGV, &sa, null);
}

fn quit(_: posix.SIG) callconv(.c) void {
    std.posix.system.exit(0);
}

fn exit(signal: posix.SIG) callconv(.c) void {
    switch (signal) {
        posix.SIG.ILL => std.log.err("Illegal instruction", .{}),
        posix.SIG.ABRT => std.log.err("Error program aborted", .{}),
        posix.SIG.SEGV => std.log.err("Segmentation fault", .{}),
        else => {},
    }
    posix.system.exit(1);
}
