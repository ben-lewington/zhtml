const std = @import("std");
const assert = std.debug.assert;
const Escaper = @This();

input: []const u8,

pub fn init(input: []const u8) Escaper {
    return .{ .input = input };
}

pub fn format(self: Escaper, w: *std.Io.Writer) !void {
    for (self.input) |ch| {
        if (escapes(ch)) |estr| {
            _ = try w.write(estr);
        } else {
            try w.writeByte(ch);
        }
    }
}

inline fn escapes(ch: u8) ?[]const u8 {
    return switch (ch) {
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
        else => null,
    };
}

test "escape_works" {
    const alloc = std.testing.allocator;
    const esc = try std.fmt.allocPrint(alloc, "{f}", .{Escaper.init("<script>BadThings(\"oh no!\")</script>")});
    defer alloc.free(esc);
    try std.testing.expectEqualSlices(u8, "&lt;script&gt;BadThings(&quot;oh no!&quot;)&lt;/script&gt;", esc);
}
