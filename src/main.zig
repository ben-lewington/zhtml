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
const Allocator = std.mem.Allocator;
const tml = @import("tml");
// const Tree = parser.Tree;
// const Templ = @import("template.zig").Templ;

const sut =
    \\!doctype html!
    \\<html|
    \\  <head|
    \\    <script|
    \\      console.log('Hello, World')
    \\    >
    \\    <meta charset="utf-8">
    \\    <meta name="viewport" content="width=device-width,initial-scale=1">
    \\  >
    \\  <body|
    \\    <header|Header>
    \\    <main|Header>
    \\    <footer|Footer>
    \\  >
    \\>
;

const templ = tml.Document.initComptime(sut) catch unreachable;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // const alloc = arena.allocator();

    defer arena.deinit();
    //
    // var parser: tml.Parser = try .init(alloc, .{
    //     .total_nodes = 10,
    //     .total_attributes = 10,
    //     .total_top_level_children = 10,
    // });
    // defer parser.deinit(alloc);
    //
    // _ = try parser.parse(sut);
    //
    // const d: tml.Document = .{
    //     .nodes = parser.nodes.items,
    //     .attributes = parser.attrs.items,
    //     .top_level_node_count = parser.top_end orelse @intCast(parser.nodes.items.len),
    // };

    var wbuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &wbuf);

    try stdout.interface.print("{f}\n", .{templ.html()});
    try stdout.flush();
}

pub fn Template(comptime T: type) type {
    return struct {
        args: T,
    };
}
