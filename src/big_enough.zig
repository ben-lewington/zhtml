const std = @import("std");
const assert = std.debug.assert;

// These are fixed size dynamic arrays. Make sure that inner is big enough for your puposes,
// else it's going to crash!
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();
        inner: []T,
        len: usize,

        pub inline fn init(inner: []T) Self {
            return .{
                .inner = inner,
                .len = 0,
            };
        }

        pub inline fn push(self: *Self, item: T) void {
            assert(self.len < self.inner.len);
            self.inner[self.len] = item;
            self.len += 1;
        }

        pub inline fn extend(self: *Self, slice: []const T) void {
            assert(self.len + slice.len < self.inner.len);
            for (slice, 0..) |p, i| self.inner[self.len + i] = p;
            self.len += slice.len;
        }
    };
}

pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();
        inner: []T,
        top: ?usize = null,

        pub inline fn init(inner: []T) Self {
            return .{
                .inner = inner,
            };
        }

        pub inline fn push(self: *Self, item: T) void {
            assert(self.top orelse 0 < self.inner.len);
            if (self.top) |t| {
                self.inner[t + 1] = item;
                self.top = t + 1;
            } else {
                self.inner[0] = item;
                self.top = 0;
            }
        }

        pub inline fn pop(self: *Self) T {
            assert(if (self.top) |_| true else false);
            var ret: T = undefined;
            if (self.top) |t| {
                if (t > 0) {
                    self.top = t - 1;
                    ret = self.inner[t];
                } else {
                    self.top = null;
                    ret = self.inner[0];
                }
            } else unreachable;
            return ret;
        }

        pub inline fn peek(self: *const Self) ?T {
            if (self.top) |t| {
                const item = self.inner[t];
                return item;
            } else return null;
        }
    };
}

test "stack works" {
    const alc = std.testing.allocator;
    const buf = try alc.alloc(usize, 50);
    defer alc.free(buf);

    var stack = Stack(usize).init(buf);
    try std.testing.expectEqual(null, stack.peek());

    stack.push(1);
    const t = stack.pop();
    try std.testing.expectEqual(1, t);

    stack.push(2);
    try std.testing.expectEqualSlices(usize, &[_]usize{2}, stack.inner[0 .. stack.top.? + 1]);
    stack.push(3);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 2, 3 }, stack.inner[0 .. stack.top.? + 1]);
    try std.testing.expectEqual(3, stack.peek());
}
