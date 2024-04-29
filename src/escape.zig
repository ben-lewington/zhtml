const std = @import("std");
const assert = std.debug.assert;
const str = []const u8;
const Buffer = @import("big_enough.zig").Buffer;

pub inline fn escapes(ch: u8) ?str {
    return switch (ch) {
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
        else => null,
    };
}

pub fn escapeNeeded(input: str) bool {
    return for (input) |ch| {
        if (escapes(ch)) |_| break true;
    } else false;
}

pub fn escapeToStr(input: str, output: *Buffer(u8)) struct { len: usize } {
    const cap = output.inner.len - output.len;
    assert(input.len < cap);
    var acc_esc: usize = 0;
    for (input) |ch| {
        if (escapes(ch)) |estr| {
            assert(input.len + acc_esc + estr.len - 1 < cap);
            output.extend(estr);
            acc_esc += estr.len - 1;
        } else {
            output.push(ch);
        }
    }
    return .{ .len = input.len + acc_esc };
}
