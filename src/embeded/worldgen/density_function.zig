const std = @import("std");

pub const SplineValue = union(enum) {
    number: f64,
    object: Spline,
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
pub const Spline = struct {
    coordinate: DensityF,
    points: []const struct {
        location: f64,
        derivative: f64,
        value: SplineValue,
    },
};

pub const DensityF = union(enum) {
    object: *const DensityFunction,
    number: f64,
    string: []const u8,
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

pub const DensityFunction = union(enum) {
    pub const Binary = struct { argument1: Df, argument2: Df };
    pub const Unary = struct { argument: Df };
    pub const NoArgument = struct {};
    const Df = DensityF;
    const Noise = []const u8;
    @"minecraft:spline": struct { spline: SplineValue },
    @"minecraft:find_top_surface": struct { lower_bound: Df, upper_bound: Df, density: Df, cell_height: u31 },
    @"minecraft:shifted_noise": struct {
        xz_scale: f64,
        y_scale: f64,
        shift_x: Df,
        shift_y: Df,
        shift_z: Df,
        noise: Noise,
    },
    @"minecraft:range_choice": struct {
        input: Df,
        min_inclusive: f64,
        max_exclusive: f64,
        when_in_range: Df,
        when_out_of_range: Df,
    },
    @"minecraft:old_blended_noise": struct { xz_scale: f64, y_scale: f64, xz_factor: f64, y_factor: f64, smear_scale_multiplier: f64 },
    @"minecraft:y_clamped_gradient": struct { from_value: f64, to_value: f64, from_y: i32, to_y: i32 },
    @"minecraft:weird_scaled_sampler": struct { input: Df, rarity_value_mapper: []const u8, noise: Noise },
    @"minecraft:noise": struct { noise: []const u8, xz_scale: f64, y_scale: f64 },

    @"minecraft:max": Binary,
    @"minecraft:min": Binary,
    @"minecraft:mul": Binary,
    @"minecraft:add": Binary,
    @"minecraft:clamp": struct { input: Df, min: f64, max: f64 },

    @"minecraft:blend_density": Unary,
    @"minecraft:flat_cache": Unary,
    @"minecraft:cache_once": Unary,
    @"minecraft:cache_2d": Unary,
    @"minecraft:interpolated": Unary,
    @"minecraft:abs": Unary,
    @"minecraft:square": Unary,
    @"minecraft:cube": Unary,
    @"minecraft:half_negative": Unary,
    @"minecraft:quarter_negative": Unary,
    @"minecraft:squeeze": Unary,
    @"minecraft:invert": Unary,
    @"minecraft:shift_a": Unary,
    @"minecraft:shift_b": Unary,

    @"minecraft:end_islands": NoArgument,
    @"minecraft:blend_offset": NoArgument,
    @"minecraft:blend_alpha": NoArgument,

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
