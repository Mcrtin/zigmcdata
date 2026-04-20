const std = @import("std");
const biome = @import("worldgen/biome.zig");

const BiomeParameters = @This();

pub const BiomeParameter = struct {
    biome: *const biome,
    parameters: Parameter,
};
pub const Parameter = struct {
    continentalness: [2]f64,
    depth: [2]f64,
    erosion: [2]f64,
    humidity: [2]f64,
    temperature: [2]f64,
    weirdness: [2]f64,
    offset: f64,
};
biomes: []const BiomeParameter,
