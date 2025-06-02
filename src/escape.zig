const std = @import("std");
const assert = std.debug.assert;

pub inline fn escapes(ch: u8) ?[]const u8 {
    return switch (ch) {
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
        else => null,
    };
}

pub fn escapeNeeded(input: []const u8) bool {
    return for (input) |ch| {
        if (escapes(ch)) |_| break true;
    } else false;
}

pub fn escapedLen(input: []const u8) usize {
    var len = 0;
    for (input) |ch| {
        len += if (escapes(ch)) |estr| estr.len else 1;
    }
    return len;
}

pub fn escapeToStr(input: []const u8, output: []u8) usize {
    const elen = escapedLen(input);
    assert(elen < output.len);
    var ix: usize = 0;
    for (input) |ch| {
        if (escapes(ch)) |estr| {
            @memcpy(output[ix .. ix + estr.len], estr);
            ix += estr.len;
        } else {
            output[ix] = ch;
            ix += 1;
        }
    }
    return elen;
}

test "escape_works" {}
