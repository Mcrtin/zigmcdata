const std = @import("std");

pub const NoiseSettings = @This();
aquifers_enabled: bool,
default_block: BlockState,
default_fluid: BlockState,
disable_mob_generation: bool,
legacy_random_source: bool,
noise: NoiseGeneratorSettings,
noise_router: NoiseRouter,
ore_veins_enabled: bool,
sea_level: i12,
spawn_target: []const ParameterPoint,
surface_rule: *const SurfaceRule,

const DensityFunction = @import("density_function.zig").DensityF;

pub const NoiseGeneratorSettings = struct {
    height: u11,
    min_y: i12,
    size_horizontal: u3,
    size_vertical: u3,
};

pub const NoiseRouter = struct {
    barrier: DensityFunction,
    continents: DensityFunction,
    depth: DensityFunction,
    erosion: DensityFunction,
    final_density: DensityFunction,
    fluid_level_floodedness: DensityFunction,
    fluid_level_spread: DensityFunction,
    lava: DensityFunction,
    preliminary_surface_level: DensityFunction,
    ridges: DensityFunction,
    temperature: DensityFunction,
    vegetation: DensityFunction,
    vein_gap: DensityFunction,
    vein_ridged: DensityFunction,
    vein_toggle: DensityFunction,
};

pub const ParameterPoint = struct {
    temperature: Parameter,
    humidity: Parameter,
    continentalness: Parameter,
    erosion: Parameter,
    depth: f32,
    weirdness: Parameter,
    offset: f32,
};

pub const Parameter = [2]f64;

pub const HeightCondition = union(enum) {
    above_bottom: u31,
    absolute: i32,
    below_top: u31,
};

pub const Condition = union(enum) {
    @"minecraft:noise_threshold": struct {
        max_threshold: f64,
        min_threshold: f64,
        noise: []const u8,
    },
    @"minecraft:vertical_gradient": struct {
        false_at_and_above: HeightCondition,
        random_name: []const u8,
        true_at_and_below: HeightCondition,
    },
    @"minecraft:above_preliminary_surface": struct {},
    @"minecraft:biome": struct { biome_is: []const []const u8 },
    @"minecraft:not": struct { invert: *const Condition },
    @"minecraft:y_above": struct {
        add_stone_depth: bool,
        anchor: HeightCondition,
        surface_depth_multiplier: i32,
    },
    @"minecraft:water": struct {
        add_stone_depth: bool,
        offset: i32,
        surface_depth_multiplier: i32,
    },
    @"minecraft:stone_depth": struct {
        add_surface_depth: bool,
        offset: i32,
        secondary_depth_range: i32,
        surface_type: []const u8,
    },
    @"minecraft:hole": struct {},
    @"minecraft:temperature": struct {},
    @"minecraft:steep": struct {},

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const T = @This();
        const unionInfo = @typeInfo(T).@"union";
        if (unionInfo.tag_type == null) @compileError("Unable to parse into untagged union '" ++ @typeName(T) ++ "'");

        if (.object_begin != try source.next()) return error.UnexpectedToken;

        var result: ?T = null;

        const type_token: ?std.json.Token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
        const type_name = switch (type_token.?) {
            inline .string, .allocated_string => |slice| slice,
            else => return error.UnexpectedToken,
        };
        if (!std.mem.eql(u8, "type", type_name)) return error.UnexpectedToken;
        allocator.free(type_name);

        const field_name = try std.json.innerParse([]const u8, allocator, source, options);

        inline for (unionInfo.fields) |u_field| {
            if (std.mem.eql(u8, u_field.name, field_name)) {
                // Free the name token now in case we're using an allocator that optimizes freeing the last allocated object.
                // (Recursing into innerParse() might trigger more allocations.)
                allocator.free(field_name);
                if (u_field.type == void) {
                    // void isn't really a json type, but we can support void payload union tags with {} as a value.
                    if (.object_begin != try source.next()) return error.UnexpectedToken;
                    if (.object_end != try source.next()) return error.UnexpectedToken;
                    result = @unionInit(T, u_field.name, {});
                } else {
                    // Recurse.
                    result = @unionInit(T, u_field.name, try parseInnerStruct(u_field.type, allocator, source, options));
                }
                break;
            }
        } else {
            // Didn't match anything.
            return error.UnknownField;
        }
        return result.?;
    }
};

pub const BlockState = struct {
    Name: []const u8,
    Properties: ?union(enum) {
        level: u4,
        snowy: []const u8, //TODO: wtf
        axis: enum { x, y, z },
    } = null,
};

pub const SurfaceRule = union(enum) {
    @"minecraft:sequence": struct { sequence: []const SurfaceRule },
    @"minecraft:condition": struct { if_true: Condition, then_run: *const SurfaceRule },
    @"minecraft:block": struct { result_state: BlockState },
    @"minecraft:bandlands": struct {},

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const T = @This();
        const unionInfo = @typeInfo(T).@"union";
        if (unionInfo.tag_type == null) @compileError("Unable to parse into untagged union '" ++ @typeName(T) ++ "'");

        if (.object_begin != try source.next()) return error.UnexpectedToken;

        var result: ?T = null;

        const type_token: ?std.json.Token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
        const type_name = switch (type_token.?) {
            inline .string, .allocated_string => |slice| slice,
            else => return error.UnexpectedToken,
        };
        if (!std.mem.eql(u8, "type", type_name)) return error.UnexpectedToken;
        allocator.free(type_name);

        const field_name = try std.json.innerParse([]const u8, allocator, source, options);

        inline for (unionInfo.fields) |u_field| {
            if (std.mem.eql(u8, u_field.name, field_name)) {
                // Free the name token now in case we're using an allocator that optimizes freeing the last allocated object.
                // (Recursing into innerParse() might trigger more allocations.)
                allocator.free(field_name);
                if (u_field.type == void) {
                    // void isn't really a json type, but we can support void payload union tags with {} as a value.
                    if (.object_end != try source.next()) return error.UnexpectedToken;
                    result = @unionInit(T, u_field.name, {});
                } else {
                    // Recurse.
                    result = @unionInit(T, u_field.name, try parseInnerStruct(u_field.type, allocator, source, options));
                }
                break;
            }
        } else {
            // Didn't match anything.
            return error.UnknownField;
        }
        return result.?;
    }
};

fn parseInnerStruct(T: type, allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !T {
    const structInfo = @typeInfo(T).@"struct";
    var r: T = undefined;
    var fields_seen = [_]bool{false} ** structInfo.fields.len;

    while (true) {
        var name_token: ?std.json.Token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
        const field_name = switch (name_token.?) {
            inline .string, .allocated_string => |slice| slice,
            .object_end => { // No more fields.
                break;
            },
            else => {
                return error.UnexpectedToken;
            },
        };

        inline for (structInfo.fields, 0..) |field, i| {
            if (field.is_comptime) @compileError("comptime fields are not supported: " ++ @typeName(T) ++ "." ++ field.name);
            if (std.mem.eql(u8, field.name, field_name)) {
                // Free the name token now in case we're using an allocator that optimizes freeing the last allocated object.
                // (Recursing into innerParse() might trigger more allocations.)
                allocator.free(field_name);
                name_token = null;
                if (fields_seen[i]) {
                    switch (options.duplicate_field_behavior) {
                        .use_first => {
                            // Parse and ignore the redundant value.
                            // We don't want to skip the value, because we want type checking.
                            _ = try std.json.innerParse(field.type, allocator, source, options);
                            break;
                        },
                        .@"error" => return error.DuplicateField,
                        .use_last => {},
                    }
                }
                @field(r, field.name) = try std.json.innerParse(field.type, allocator, source, options);
                fields_seen[i] = true;
                break;
            }
        } else {
            // Didn't match anything.
            allocator.free(field_name);
            if (options.ignore_unknown_fields) {
                try source.skipValue();
            } else {
                return error.UnknownField;
            }
        }
    }
    try fillDefaultStructValues(T, &r, &fields_seen);
    return r;
}

fn fillDefaultStructValues(comptime T: type, r: *T, fields_seen: *[@typeInfo(T).@"struct".fields.len]bool) !void {
    inline for (@typeInfo(T).@"struct".fields, 0..) |field, i| {
        if (!fields_seen[i]) {
            if (field.defaultValue()) |default| {
                @field(r, field.name) = default;
            } else {
                return error.MissingField;
            }
        }
    }
}
