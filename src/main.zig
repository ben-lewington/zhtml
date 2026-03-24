// ws := [' ' | '\n' | '\r' | '\t']
//
// symbols := {
//     def := '<'
//     push := '|'
//     pinch := ';'
//     pop := '>'
// }
//
// ident := [a-zA-Z0-9][a-zA-Z0-9-_]*
// literal := ".*"
//
// shorthand := {
//     class := '.'
//     id := '#'
// }
//
// markup :=
//     ([ident | literal] ws)*                                                          // text
//   | symbols.def '!' ([ident | literal] ws)* symbols.pinch                            // meta
//   | symbols.def '!' '-' ws ([ident | literal] ws)* symbols.pinch                     // comment
//   | symbols.def ident ([ident | ident '=' literal])* symbols.push markup symbols.pop // tag
const std = @import("std");
const log = std.log.scoped(.tml);
const Tokeniser = @import("tokeniser.zig").Tokeniser;
const Allocator = std.mem.Allocator;
// const parser = @import("parser.zig");
// const Tree = parser.Tree;
// const Templ = @import("template.zig").Templ;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // const templ = comptime Templ(
    //     .interp,
    //     \\<a|The content is @content@bar>
    //     ,
    // ) catch unreachable;

    var wbuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &wbuf);

    // try templ.render(stdout, .{ .content = true, .bar = 3 });
    _ = try stdout.interface.write("\n");
}

pub fn Template(comptime T: type) type {
    return struct {
        args: T,

    };
}
