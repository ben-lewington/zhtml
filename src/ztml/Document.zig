const std = @import("std");

pub const Node = struct {
    kind: Kind,
    content: []const u8,
    attrs: ?Slice = null,
    children: ?Slice = null,
    interp_ix: ?u32 = null,

    const Slice = struct { u32, u32 };

    pub const Kind = enum(u8) {
        /// any string of alphanumeric, whitespace delimited tokens
        text,
        /// !doctype html!
        meta,
        /// # a comment #
        comment,
        /// <tag_name (attr="value")* | children >
        tag,
        ///
        interp,
    };

    pub const Attr = union(enum) {
        simple: struct {
            name: []const u8,
            value: ?[]const u8 = null,
        },
        interp: struct {
            name: []const u8,
            interp_ix: u32,
        },
        interp_splat: u32,
    };
};

pub const Interp = struct {
    kind: Kind,
    pub const Kind = enum {
        import,
        render_value,
        attr_value,
        attr_splat,
        @"if",
        @"for",
    };
};

// pub const Engine = struct {
//
//     pub fn Template(
//         comptime self: *const Engine,
//         comptime lookup: @EnumLiteral(),
//         comptime link: @EnumLiteral(),
//     ) type {
//         return struct {
//             self.Template(comptime self: *const Engine, comptime lookup: @EnumLiteral(), comptime link: @EnumLiteral())
//         };
//     }
// };
