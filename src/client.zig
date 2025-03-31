const std = @import("std");
const msg = @import("message.zig");
const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("semaphore.h");
});

var shm: c_int = undefined;
var sem: [*c]c.sem_t = undefined;
var mmap: []align(std.mem.page_size) u8 = undefined;

fn setup() !void {
    shm = std.c.shm_open("mouseless", c.O_RDWR, 0o0666);
    if (shm < 0) {
        std.log.err("shm_open failed: {d}", .{shm});
        return error.ClientShmOpen;
    }
    sem = c.sem_open("mouseless", 0);
    if (sem == c.SEM_FAILED) {
        std.log.err("sem_open failed", .{});
        return error.ClientSemOpen;
    }
    mmap = try std.posix.mmap(
        null,
        msg.size,
        std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        shm,
        0,
    );
}

fn deinit() void {
    _ = c.sem_close(sem);
    std.posix.munmap(mmap);
}

pub fn show() !void {
    try setup();
    std.mem.copyForwards(u8, mmap, &[1]u8{@intFromEnum(msg.Type.show)});
    _ = c.sem_post(sem);
    deinit();
}

pub fn clean() !void {
    try setup();
    std.mem.copyForwards(u8, mmap, &[1]u8{@intFromEnum(msg.Type.clean)});
    _ = c.sem_post(sem);
    deinit();
}
