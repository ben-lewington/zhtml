const std = @import("std");
const str = []const u8;
const cPr = std.fmt.comptimePrint;

pub const COMPTIME_PRINT = false;

pub fn err(comptime fmt: str, args: anytype) void {
    if (@inComptime()) {
        if (COMPTIME_PRINT) @compileLog(cPr("[ERROR]:{s}", .{cPr(fmt, args)}));
    } else std.log.err(fmt, args);
}

pub fn warn(comptime fmt: str, args: anytype) void {
    if (@inComptime()) {
        if (COMPTIME_PRINT) @compileLog(cPr("[WARN]: {s}", .{cPr(fmt, args)}));
    } else std.log.warn(fmt, args);
}

pub fn info(comptime fmt: str, args: anytype) void {
    if (@inComptime()) {
        if (COMPTIME_PRINT) @compileLog(cPr("[INFO]: {s}", .{cPr(fmt, args)}));
    } else std.log.info(fmt, args);
}

pub fn debug(comptime fmt: str, args: anytype) void {
    if (@inComptime()) {
        if (COMPTIME_PRINT) @compileLog(cPr("[DEBUG]: {s}", .{cPr(fmt, args)}));
    } else std.log.debug(fmt, args);
}
