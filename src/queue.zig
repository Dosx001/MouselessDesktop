const std = @import("std");

pub const Type = enum {
    Done,
    Entry,
    Point,
    Quit,
};

pub const Point = struct {
    x: c_int = 0,
    y: c_int = 0,
};

pub const Message = struct {
    pos: Point = .{},
    size: Point = .{},
    type: Type,
};

var buffer: [512]Message = undefined;
var queue: std.Io.Queue(Message) = undefined;

pub fn init() void {
    queue = std.Io.Queue(Message).init(&buffer);
}

pub fn push(io: std.Io, msg: Message) void {
    queue.putOne(io, msg) catch unreachable;
}

pub fn pop(io: std.Io) Message {
    return queue.getOne(io) catch unreachable;
}
