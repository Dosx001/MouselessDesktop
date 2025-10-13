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

var queue: [256]Message = undefined;
var count: usize = 0;
var head: usize = 0;
var tail: usize = 0;

pub fn push(msg: Message) void {
    while (count == queue.len)
        std.Thread.sleep(100 * std.time.ns_per_ms);
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
