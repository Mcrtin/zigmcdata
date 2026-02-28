const std = @import("std");
const utils = @import("utils.zig");

interface: *std.io.Writer,
indentation: u32 = 0,

const Self = @This();
pub fn indent(self: *Self) void {
    self.interface.splatByteAll(' ', self.indentation * 3) catch unreachable;
}

pub fn indented(self: *Self, comptime str: []const u8) void {
    var i: usize = 0;
    while (std.mem.indexOfScalarPos(u8, str, i, '\n')) |i_| : (i = i_) {
        self.indent();
        self.interface.writeAll(str[i..i_]) catch unreachable;
    }
    self.indent();
    self.interface.writeAll(str[i..]) catch unreachable;
}

pub fn assign(self: *Self, name: []const u8, type_name: ?[]const u8, public: bool) void {
    self.indent();
    if (public) self.interface.writeAll("pub ") catch unreachable;
    self.interface.writeAll("const ") catch unreachable;
    self.identifier(name);
    if (type_name) |type_name_| self.interface.print(": {s}", .{type_name_}) catch unreachable;
    self.interface.writeAll(" = ") catch unreachable;
}

pub fn identifier(self: *Self, id: []const u8) void {
    if (utils.containsForbiddenChar(id)) {
        self.interface.writeAll("@\"") catch unreachable;
        utils.writeEscaped(self.interface, id) catch unreachable;
        self.interface.writeAll("\"") catch unreachable;
    } else self.interface.writeAll(id) catch unreachable;
}

pub fn import(self: *Self, name: []const u8, public: bool) void {
    if (std.mem.endsWith(u8, name, ".zig"))
        assign(self, name[0 .. name.len - 4], null, public)
    else
        assign(self, name, null, false);
    self.interface.print("@import(\"{s}\")", .{name}) catch unreachable;
    self.endStatement();
}

pub fn @"enum"(self: *Self, iter: anytype, comptime name_field: ?[]const u8, comptime id_field: ?[]const u8) void {
    self.interface.writeAll("enum {\n") catch unreachable;
    self.indentation += 1;
    switch (@typeInfo(@TypeOf(iter))) {
        .pointer => {
            if (std.meta.hasMethod(@TypeOf(iter), "next")) {
                while (iter.next()) |item| self.enumField(item, name_field, id_field);
            } else for (iter) |item| self.enumField(item, name_field, id_field);
        },
        else => @compileError("iter not an iterator or slice"),
    }
    self.indentation -= 1;
    self.indent();
    self.interface.writeAll("}") catch unreachable;
}

pub fn enumField(self: *Self, item: anytype, comptime name_field: ?[]const u8, comptime id_field: ?[]const u8) void {
    self.indent();
    const name = if (name_field) |n| @field(item, n) else item;
    self.identifier(name);
    if (id_field) |id| self.interface.print(" = {any}", .{@field(item, id)}) catch unreachable;
    self.interface.writeAll(",\n") catch unreachable;
}

pub fn field(self: Self, name: []const u8, value: anytype) void {
    self.indent();
    self.interface.writeAll(".") catch unreachable;
    self.identifier(name);
    self.interface.writeAll(" = ") catch unreachable;
    self.write(value);

    self.interface.writeAll(",\n") catch unreachable;
}

pub fn write(self: *Self, value: anytype) void {
    self.interface.printValue("", .{}, value, 10);
    // const type_info = @typeInfo(@TypeOf(value));
    // switch (type_info) {
    //     .bool => (if (@as(bool, value)) self.interface.writeAll("true") else self.interface.writeAll("false")) catch unreachable,
    //     .int => self.interface.printValue(comptime fmt: []const u8, options: Options, value: anytype, max_depth: usize),
    //     .float => {},
    //     .pointer => {},
    //     .array => {},
    //     .@"struct" => {},
    //     .comptime_float => {},
    //     .comptime_int => {},
    //     .undefined => {},
    //     .null => {},
    //     .optional => {},
    //     .@"enum" => {},
    //     .@"union" => {},
    //     .vector => {},
    //     .enum_literal => {},
    // }
}

pub fn endStatement(self: *Self) void {
    self.interface.writeAll(";\n\n") catch unreachable;
}

pub fn writeStructInstance(self: *Self, instance: anytype) void {
    const type_info = @typeInfo(@TypeOf(instance));
    self.interface.writeAll(".{\n") catch unreachable;
    self.indentation += 1;
    switch (type_info) {
        .@"struct" => |info| {
            for (info.fields) |item| {
                self.field(item.name, @field(instance, item.name));
            }
        },
        else => @compileError("Expected struct found " ++ type_info),
    }
    self.indentation -= 1;
    self.indent();
    self.interface.writeAll("}");
}
