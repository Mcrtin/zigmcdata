const std = @import("std");

const BiomeParameter = struct {
    biome: []const u8,
    parameters: struct {
        continentalness: std.json.Value,
        depth: std.json.Value,
        erosion: std.json.Value,
        humidity: std.json.Value,
        offset: std.json.Value,
        temperature: std.json.Value,
        weirdness: std.json.Value,
    },
};

const Parameters = struct { biomes: []const BiomeParameter };

pub fn gen(gpa: std.mem.Allocator, dir: *std.fs.Dir, out: *std.Io.Writer) !void {
    try out.writeAll(@embedFile("embeded/BiomeParameters.zig"));
    var it: std.fs.Dir.Iterator = dir.iterateAssumeFirstIteration();
    while (try it.next()) |entry| {
        const file = try dir.openFile(entry.name, .{});
        var buf: [1024]u8 = undefined;
        var io_reader = file.reader(&buf);
        var r = std.json.Reader.init(gpa, &io_reader.interface);
        defer r.deinit();
        const parsed = try std.json.parseFromTokenSource(Parameters, gpa, &r, .{ .allocate = .alloc_always });
        defer parsed.deinit();
        const parameters: Parameters = parsed.value;

        try out.print("pub const @\"minecraft:{s}\": BiomeParameters  = .{{\n", .{entry.name[0..std.fs.path.extension(entry.name).len]});
        try out.writeAll("    .biomes = &.{\n");
        for (parameters.biomes) |biome| {
            try out.print(
                \\    .{{
                \\        .biome = &biome.@"{s}",
                \\        .parameters = .{{
                \\            .continentalness = .{any},
                \\            .depth           = .{any},
                \\            .erosion         = .{any},
                \\            .humidity        = .{any},
                \\            .offset          = .{any},
                \\            .temperature     = .{any},
                \\            .weirdness       = .{any},
                \\        }},
                \\    }},
                \\
            , .{
                biome.biome,
                toParam(biome.parameters.continentalness),
                toParam(biome.parameters.depth),
                toParam(biome.parameters.erosion),
                toParam(biome.parameters.humidity),
                toParam(biome.parameters.offset),
                toParam(biome.parameters.temperature),
                toParam(biome.parameters.weirdness),
            });
        }
        try out.writeAll("    },\n");
        try out.writeAll("};\n\n");
    }
}
fn toParam(val: std.json.Value) [2]f64 {
    return switch (val) {
        .float => |f| .{ f, f },
        .array => |a| .{ a.items[0].float, a.items[1].float },
        else => unreachable,
    };
}
