const std = @import("std");
pub const Error = std.Io.Writer.Error;

pub fn write(w: *std.Io.Writer, depth: usize, val: anytype) Error!void {
    const T = @TypeOf(val);
    switch (@typeInfo(T)) {
        .void => try w.writeAll("{}"),
        .bool => if (val) try w.writeAll("true") else try w.writeAll("false"),
        .comptime_int, .int => try w.printInt(val, 10, .lower, .{}),
        .comptime_float, .float => if (val == 0) try w.writeAll("0") else try w.printFloat(val, .{ .mode = if (val > 1e6) .scientific else .decimal }),
        .pointer => |p| if (T == []const u8)
            try printString(w, val)
        else if (p.size == .one) {
            try w.writeByte('&');
            try write(w, depth, val.*);
        } else if (p.size == .slice) {
            try w.writeAll("&.{\n");
            for (val) |v| {
                try w.splatByteAll(' ', (depth + 1) * 4);
                try write(w, depth + 1, v);
                try w.writeAll(",\n");
            }
            try w.splatByteAll(' ', depth * 4);
            try w.writeAll("}");
        } else @compileError("unsupported pointer type " ++ @tagName(p.size)),
        .vector, .array => {
            try w.writeAll(".{\n");
            for (val) |v| {
                try w.splatByteAll(' ', (depth + 1) * 4);
                try write(w, depth + 1, v);
                try w.writeAll(",\n");
            }
            try w.splatByteAll(' ', depth * 4);
            try w.writeAll("}");
        },
        .@"struct" => |s| {
            try w.writeAll(".{\n");
            inline for (s.fields) |field| {
                try w.splatByteAll(' ', (depth + 1) * 4);
                try w.writeByte('.');
                try printId(w, field.name);
                try w.writeAll(" = ");
                try write(w, depth + 1, @field(val, field.name));
                try w.writeAll(",\n");
            }
            try w.splatByteAll(' ', depth * 4);
            try w.writeAll("}");
        },
        .undefined => try w.writeAll("undefined"),
        .null => try w.writeAll("null"),
        .optional => if (val == null) try w.writeAll("null") else try write(w, depth, val.?),
        .enum_literal, .@"enum", .error_set, .error_union => try w.print(".{t}", .{val}),
        .@"union" => {
            try w.writeAll(".{\n");
            try w.splatByteAll(' ', (depth + 1) * 4);
            try w.writeByte('.');
            try printId(w, @tagName(val));
            try w.writeAll(" = ");
            switch (std.meta.activeTag(val)) {
                inline else => |v| try write(w, depth + 1, @field(val, @tagName(v))),
            }
            try w.writeAll(",\n");
            try w.splatByteAll(' ', depth * 4);
            try w.writeAll("}");
        },
        else => @compileError("can't write " ++ @typeName(T)),
    }
}

pub fn printId(w: *std.Io.Writer, val: []const u8) !void {
    if (containsForbiddenChar(val)) {
        try w.writeByte('@');
        try printString(w, val);
    } else try w.writeAll(val);
}
pub fn printString(w: *std.Io.Writer, text: []const u8) !void {
    try w.writeByte('"');
    for (text) |c| {
        switch (c) {
            '\\', '"' => {
                try w.writeByte('\\');
                try w.writeByte(c);
            },
            '\n' => {
                try w.writeByte('\\');
                try w.writeByte('n');
            },
            else => try w.writeByte(c),
        }
    }
    try w.writeByte('"');
}

fn containsForbiddenChar(text: []const u8) bool {
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
