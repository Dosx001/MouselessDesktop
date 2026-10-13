const std = @import("std");

pub const Type = enum {
    done,
    entry,
    point,
    quit,
};

pub const Point = struct {
    x: c_int,
    y: c_int,
};

pub const Message = struct {
    pos: Point,
    size: Point,
    type: Type,
};

var threaded = std.Io.Threaded.init_single_threaded;
const io = threaded.io();
var queue: [256]Message = undefined;
var count: usize = 0;
var head: usize = 0;
var tail: usize = 0;

pub fn push(msg: Message) void {
    while (count == queue.len)
        std.Io.sleep(io, .fromMicroseconds(100), .awake) catch unreachable;
    queue[tail] = msg;
    count += 1;
    tail = (tail + 1) % queue.len;
}

pub fn pop() ?Message {
    if (count == 0) return null;
    const msg = queue[head];
    count -= 1;
    head = (head + 1) % queue.len;
    return msg;
}
