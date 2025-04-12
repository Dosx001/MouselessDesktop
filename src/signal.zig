const std = @import("std");
const mouseless = @import("mouseless.zig");
const c = @cImport({
    @cInclude("gtk-3.0/gtk/gtk.h");
    @cInclude("signal.h");
});

pub fn setup() void {
    _ = c.signal(c.SIGHUP, gtk_quit);
    _ = c.signal(c.SIGINT, gtk_quit);
    _ = c.signal(c.SIGQUIT, gtk_quit);
    _ = c.signal(c.SIGILL, gtk_quit);
    _ = c.signal(c.SIGABRT, reset);
    _ = c.signal(c.SIGSEGV, reset);
    _ = c.signal(c.SIGTERM, gtk_quit);
}

fn gtk_quit(_: c_int) callconv(.C) void {
    c.gtk_main_quit();
}

fn reset(signal: c_int) callconv(.C) void {
    mouseless.reset();
    switch (signal) {
        c.SIGILL => std.log.err("Illegal instruction", .{}),
        c.SIGABRT => std.log.err("Error program aborted", .{}),
        c.SIGSEGV => std.log.err("Segmentation fault", .{}),
        else => {},
    }
    std.posix.exit(1);
}
