const std = @import("std");
type: []const u8,
properties: []const Property.Type,
default_instance: Instance,
first_instance: Instance,
other: std.StaticStringMap(*const anyopaque) = .{},
const Block = @This();

pub const Instance = enum(std.math.IntFittingRange(0, MaxState)) {
    _,

    pub fn block(self: @This()) *const Block {
        return switch (@intFromEnum(self)) {
            //__insert_blocks_here__
        };
    }

    pub fn properties(self: @This()) []const Property {
        var it = std.mem.reverseIterator(self.block().properties);
        var id = @intFromEnum(self) - @intFromEnum(self.block().first_instance);
        var res: [self.block().properties.len]Property = undefined;
        var i: usize = 0;
        while (it.next()) |property| : (i += 1) {
            const variants = Property.variants(property);
            res[i] = @unionInit(Property, @tagName(property), if (@FieldType(Property, @tagName(property)) == bool) id % variants != 0 else @enumFromInt(id % variants));
            id /= variants;
        }
        return res;
    }

    pub fn getProperty(self: @This(), comptime property: Property.Type) ?@FieldType(Property, @tagName(property)) {
        for (self.properties()) |prop| {
            if (prop == property) return prop;
        }
        return null;
    }
};

pub const Property = union(enum) {
    pub const Type = @typeInfo(@This()).@"union".tag_type.?;

    //__insert_properties_here__
    pub fn variants(self: @This().Type) u8 {
        return switch (self) {
            inline else => |t| if (@TypeOf(t) == bool) 2 else @intCast(@typeInfo(@TypeOf(t)).@"enum".fields.len),
        };
    }
};

//__cut_here__
pub const MaxState = unreachable;
