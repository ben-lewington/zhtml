const assert = @import("std").debug.assert;

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

        pub inline fn extend_until(self: *Self, slice: []const T) usize {
            var i = 0;
            while (self.len + i < self.inner.len) : (i += 1) {
                self.inner[self.len + i] = slice[i];
            }
            return i;
        }
    };
}

pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();
        inner: []T,
        len: ?usize = null,

        pub inline fn init(inner: []T) Self {
            return .{
                .inner = inner,
            };
        }

        pub inline fn push(self: *Self, item: T) void {
            assert(self.len orelse 0 < self.inner.len);
            // @import("std").log.debug("pushing: {*}", .{item});
            const len = self.len orelse 0;
            self.inner[len] = item;
            if (self.len) |l| {
                self.len = l + 1;
            } else self.len = 0;
        }

        pub inline fn pop(self: *Self) T {
            assert(if (self.len) |_| true else false);
            if (self.len) |l| {
                defer {
                    if (l == 0) {
                        self.len = null;
                    } else {
                        self.len = l - 1;
                    }
                }
                return self.inner[l];
            } else unreachable;
        }

        pub inline fn peek(self: *const Self) ?T {
            return if (self.len) |l| self.inner[l] else null;
        }
    };
}
