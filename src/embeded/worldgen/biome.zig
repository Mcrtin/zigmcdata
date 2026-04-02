const std = @import("std");
pub const Biome = @This();
pub const Spawner = struct {
    type: []const u8,
    maxCount: u31,
    minCount: u31,
    weight: u31,
};

// attributes: ?std.json.ArrayHashMap(std.json.Value), TODO
carvers: Carvers,
creature_spawn_probability: ?f64 = null,
downfall: f64,
// effects: std.json.ArrayHashMap([]const u8), TODO
features: []const []const []const u8,
has_precipitation: bool,
spawn_costs: struct {},

spawners: struct {
    ambient: []const Spawner,
    axolotls: []const Spawner,
    creature: []const Spawner,
    misc: []const Spawner,
    monster: []const Spawner,
    underground_water_creature: []const Spawner,
    water_ambient: []const Spawner,
    water_creature: []const Spawner,
},
temperature: f64,
pub const Carvers = union(enum) {
    string: []const u8,
    array: []const []const u8,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        return switch (try source.peekNextTokenType()) {
            .object_begin => jsonParseInner(allocator, source, options, "object"),
            .array_begin => jsonParseInner(allocator, source, options, "array"),

            .true, .false => jsonParseInner(allocator, source, options, "bool"),
            .null => jsonParseInner(allocator, source, options, "null"),
            .number => jsonParseInner(allocator, source, options, "number"),
            .string => jsonParseInner(allocator, source, options, "string"),

            .object_end, .array_end => return error.SyntaxError,
            .end_of_document => return error.EndOfStream,
        };
    }
    pub fn jsonParseInner(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions, comptime name: []const u8) !@This() {
        return if (!@hasField(@This(), name))
            error.SyntaxError
        else
            @unionInit(@This(), name, try std.json.innerParse(@FieldType(@This(), name), allocator, source, options));
    }
};
