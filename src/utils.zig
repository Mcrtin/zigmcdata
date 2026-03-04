const std = @import("std");

pub fn writeSnakeToCamel(writer: *std.Io.Writer, text: []const u8) !void {
    var to_upper = false;
    for (text) |c| {
        if (c == '_') {
            to_upper = true;
        } else {
            try writer.writeByte(if (to_upper) std.ascii.toUpper(c) else c);
        }
    }
}

//TODO: remove
pub fn snakeToCamelAlloc(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var res = try std.ArrayList(u8).initCapacity(gpa, text.len);
    var to_upper = false;
    var i: usize = 0;
    for (text) |c| {
        if (c == '_') to_upper = true else {
            res.appendAssumeCapacity(if (to_upper) std.ascii.toUpper(c) else c);
            to_upper = false;
            i += 1;
        }
    }
    return res.toOwnedSlice(gpa);
}

pub fn writeCamelToSnake(writer: *std.Io.Writer, text: []const u8) !void {
    for (text, 0..) |c, i| {
        if (std.ascii.isUpper(c)) {
            if (i != 0) {
                try writer.writeByte('_');
            }
            try writer.writeByte(std.ascii.toLower(c));
        } else {
            try writer.writeByte(c);
        }
    }
}

pub fn writeEscaped(writer: *std.Io.Writer, text: []const u8) !void {
    for (text) |c| {
        switch (c) {
            '\\', '"' => {
                try writer.writeByte('\\');
                try writer.writeByte(c);
            },
            '\n' => {
                try writer.writeByte('\\');
                try writer.writeByte('n');
            },
            else => try writer.writeByte(c),
        }
    }
}

pub fn containsForbiddenChar(text: []const u8) bool {
    if (std.mem.eql(u8, text, "void")) return true;
    if (std.mem.eql(u8, text, "type")) return true;
    if (text.len > 0) {
        if (!std.ascii.isAlphabetic(text[0])) return true;
    } else return true;
    for (text) |c| {
        switch (c) {
            '/', '"', ':', '\n', '\\' => return true,
            else => {},
        }
    }
    return false;
}

pub fn join(comptime T: type, gpa: std.mem.Allocator, slices: [][]const T, separator: T) ![]T {
    var arr = std.ArrayList(T){};
    for (slices, 0..) |slice, i| {
        try arr.appendSlice(gpa, slice);
        if (i < slices.len - 1) try arr.append(gpa, separator);
    }
    return arr.toOwnedSlice(gpa);
}
