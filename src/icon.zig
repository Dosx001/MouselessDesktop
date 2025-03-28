const std = @import("std");

pub const Size = enum {
    x32,
    x128,
    x256,
};

pub fn get_path(size: Size, full: bool, allocator: std.mem.Allocator) ![]const u8 {
    const name = switch (size) {
        Size.x32 => "32x32",
        Size.x128 => "128x128",
        Size.x256 => "256x256",
    };
    const icon = std.fmt.allocPrint(
        allocator,
        "/usr/share/icons/hicolor/{s}/apps/mouselessdesktop.png",
        .{name},
    ) catch |e| {
        std.log.warn("default icon allocation failed: {}", .{e});
        return e;
    };
    std.fs.accessAbsolute(icon, .{}) catch {
        allocator.free(icon);
        const buffer = std.heap.page_allocator.alloc(u8, 128) catch |e| {
            std.log.warn("icon buffer allocation failed: {}", .{e});
            return e;
        };
        defer std.heap.page_allocator.free(buffer);
        const dir = std.posix.getcwd(buffer) catch |e| {
            std.log.warn("icon path allocation failed: {}", .{e});
            return e;
        };
        if (full)
            return std.fmt.allocPrint(
                allocator,
                "{s}/assets/{s}.png",
                .{ dir, name },
            ) catch |e| {
                std.log.warn("full icon allocation failed: {}", .{e});
                return e;
            };
        return std.fmt.allocPrint(
            allocator,
            "{s}/assets/",
            .{dir},
        ) catch |e| {
            std.log.warn("prefix icon allocation failed: {}", .{e});
            return e;
        };
    };
    return icon;
}
