const std = @import("std");

pub const Type = enum {
    Done,
    Entry,
    Point,
    Show,
};

pub const Point = struct {
    x: c_int,
    y: c_int,
};

pub const Message = struct {
    pt: Point,
    pos: Point,
    type: Type,
};

pub var queue: std.fifo.LinearFifo(
    Message,
    .Dynamic,
) = undefined;

pub fn init() !void {
    queue = std.fifo.LinearFifo(
        Message,
        .Dynamic,
    ).init(std.heap.page_allocator);
    queue.ensureTotalCapacity(128) catch
        return error.QueueAlloc;
}

pub fn deinit() void {
    queue.deinit();
}

pub fn push(msg: Message) void {
    queue.writeItem(msg) catch
        std.log.err("queue overflow", .{});
}

pub fn pop() ?Message {
    return queue.readItem();
}
