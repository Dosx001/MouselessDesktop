const std = @import("std");

const c = @cImport({
    @cInclude("gtk-3.0/gtk/gtk.h");
    @cInclude("signal.h");
});

pub fn setup() void {
    _ = c.signal(c.SIGHUP, gtkQuit);
    _ = c.signal(c.SIGINT, gtkQuit);
    _ = c.signal(c.SIGQUIT, gtkQuit);
    _ = c.signal(c.SIGILL, gtkQuit);
    _ = c.signal(c.SIGABRT, exit);
    _ = c.signal(c.SIGSEGV, exit);
    _ = c.signal(c.SIGTERM, gtkQuit);
}

fn gtkQuit(_: c_int) callconv(.c) void {
    c.gtk_main_quit();
}

fn exit(signal: c_int) callconv(.c) void {
    switch (signal) {
        c.SIGILL => std.log.err("Illegal instruction", .{}),
        c.SIGABRT => std.log.err("Error program aborted", .{}),
        c.SIGSEGV => std.log.err("Segmentation fault", .{}),
        else => {},
    }
    std.posix.exit(1);
}
