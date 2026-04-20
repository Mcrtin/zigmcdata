const std = @import("std");
type: []const u8,
name: []const u8,
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
            else => unreachable,
        };
    }

    pub fn getProperty(self: @This(), comptime property: Property.Type) ?@FieldType(Property, @tagName(property)) {
        const properties = self.block().properties;
        const id = @intFromEnum(self) - @intFromEnum(self.block().first_instance);
        if (std.mem.indexOfScalar(Property.Type, properties, property)) |idx| {
            var variants: usize = 1;
            for (properties[idx + 1 ..]) |prop|
                variants *= Property.variants(prop);
            const variant = (id / variants) % Property.variants(property);
            return if (@FieldType(Property, @tagName(property)) == bool)
                variant == 0
            else
                @enumFromInt(variant);
        } else return null;
    }

    pub fn getIthProperty(self: @This(), idx: usize) ?Property {
        const properties = self.block().properties;
        const id = @intFromEnum(self) - @intFromEnum(self.block().first_instance);
        if (idx >= properties.len) return null;
        var variants: usize = 1;
        for (properties[idx + 1 ..]) |prop|
            variants *= Property.variants(prop);
        const variant = (id / variants) % Property.variants(properties[idx]);
        switch (properties[idx]) {
            inline else => |p| {
                return @unionInit(Property, @tagName(p), if (@FieldType(Property, @tagName(p)) == bool) variant == 0 else @enumFromInt(variant));
            },
        }
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
