const std = @import("std");
const assert = std.debug.assert;
const Escaper = @This();

input: []const u8,

pub fn format(self: Escaper, w: *std.Io.Writer) !void {
    for (self.input) |ch| {
        if (escapes(ch)) |estr| {
            _ = try w.write(estr);
        } else {
            try w.writeByte(ch);
        }
    }
}

pub inline fn escapes(ch: u8) ?[]const u8 {
    return switch (ch) {
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
        else => null,
    };
}

test "escape_works" {}
