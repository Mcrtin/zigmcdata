//TODO: lang sub structs
const std = @import("std");
const utils = @import("utils.zig");

pub fn gen(w: *std.Io.Writer, data: *const std.StringArrayHashMapUnmanaged([]const u8)) !void {
    try w.writeAll(
        \\const std = @import("std");
        \\pub const Lang = enum {
        \\
    );

    for (data.keys()) |key| {
        try w.print(
            \\   @"{s}",
            \\
        , .{key});
    }
    try w.writeAll(
        \\   pub fn key(self: @This()) [:0]const u8 {
        \\      return @tagName(self);
        \\   }
        \\
        \\   pub fn toString(self: @This()) [:0]const u8 {
        \\      return switch(self) {
    );
    var it = data.iterator();
    while (it.next()) |item| {
        try w.print(
            \\      .@"{s}" => "
        , .{
            item.key_ptr.*,
        });
        try utils.writeEscaped(w, item.value_ptr.*);
        try w.writeAll("\",\n");
    }
    try w.writeAll(
        \\      };
        \\   }
        \\};
        \\
    );
}
