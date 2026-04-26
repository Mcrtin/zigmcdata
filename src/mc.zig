const std = @import("std");
const writeZig = @import("writeZig.zig");

const FileData = struct {
    type_data: []const u8,
    type_file: type,
    path: []const u8,
    type_name: []const u8,
};
gpa: std.mem.Allocator,
translatables: *const std.StringArrayHashMapUnmanaged([]const u8),

const Parsers = struct {
    pub const worldgen = struct {
        pub const noise_settings: FileData = .{
            .path = "worldgen/noise_settings",
            .type_data = @embedFile("embeded/worldgen/noise_settings.zig"),
            .type_file = @import("embeded/worldgen/noise_settings.zig"),
            .type_name = "NoiseSettings",
        };
        pub const density_function: FileData = .{
            .path = "worldgen/density_function",
            .type_data = @embedFile("embeded/worldgen/density_function.zig"),
            .type_file = @import("embeded/worldgen/density_function.zig").DensityF,
            .type_name = "DensityF",
        };
        pub const noise: FileData = .{
            .path = "worldgen/noise",
            .type_data = @embedFile("embeded/worldgen/noise.zig"),
            .type_file = @import("embeded/worldgen/noise.zig"),
            .type_name = "Noise",
        };
        pub const biome: FileData = .{
            .path = "worldgen/biome",
            .type_data = @embedFile("embeded/worldgen/biome.zig"),
            .type_file = @import("embeded/worldgen/biome.zig"),
            .type_name = "Biome",
        };
    };
};

const FileExtension = enum { json, mcmeta, nbt };

pub fn parseDataDir(comptime file_data: FileData, io: std.Io, alloc: std.mem.Allocator, mc_data_dir: std.Io.Dir, out: std.Io.Dir) !void {
    var pbuf: [std.fs.max_path_bytes]u8 = undefined;
    var dir = try mc_data_dir.openDir(io, file_data.path, .{ .iterate = true });
    defer dir.close(io);
    var out_dir = try out.createDirPathOpen(io, std.Io.Dir.path.dirname(file_data.path).?, .{});
    defer out_dir.close(io);
    const out_file = try out_dir.createFile(io, std.fmt.bufPrint(&pbuf, "{s}.zig", .{std.Io.Dir.path.basename(file_data.path)}) catch unreachable, .{});
    defer out_file.close(io);
    var wbuf: [1024]u8 = undefined;
    var w = out_file.writer(io, &wbuf);
    defer w.interface.flush() catch {};

    try w.interface.writeAll(file_data.type_data);

    var walker = try dir.walk(alloc);
    defer walker.deinit();
    while (try walker.next(io)) |f| {
        switch (f.kind) {
            .file => {
                const file = try f.dir.openFile(io, f.basename, .{});
                defer file.close(io);

                var buf: [1024]u8 = undefined;
                var freader = file.reader(io, &buf);

                const ext = std.meta.stringToEnum(FileExtension, std.Io.Dir.path.extension(f.basename)[1..]) orelse return error.WrongFileType;
                switch (ext) {
                    .json, .mcmeta => {
                        try w.interface.writeAll("pub const ");
                        try writeZig.printId(&w.interface, try std.fmt.bufPrint(&pbuf, "minecraft:{s}", .{f.path[0 .. f.path.len - std.Io.Dir.path.extension(f.path).len]}));
                        try w.interface.print(": {s}", .{file_data.type_name});

                        try w.interface.writeAll(" = ");

                        var r = std.json.Reader.init(alloc, &freader.interface);
                        defer r.deinit();
                        const val = std.json.parseFromTokenSource(file_data.type_file, alloc, &r, .{ .ignore_unknown_fields = true }) catch |e| {
                            if (r.peekNextTokenType()) |next_token| {
                                std.debug.print("in: {s} next token: {t}\n", .{ f.path, next_token });
                            } else |e2| {
                                std.debug.print("next token errored: {t}\n", .{e2});
                            }
                            return e;
                        };
                        defer val.deinit();
                        // @setEvalBranchQuota(100000);
                        // try std.zon.stringify.serializeArbitraryDepth(val.value, .{}, &w.interface); TODO: currently, ptrs are ignored
                        try writeZig.write(&w.interface, 0, val.value);
                        try w.interface.writeAll(";\n");
                    },
                    .nbt => {},
                }
            },
            .directory => {},

            else => return error.WrongFileType,
        }
    }
}

fn FileDataSerializer(comptime file_data: FileData) type {
    return struct {
        pub fn parse(io: std.Io, alloc: std.mem.Allocator, mc_data_dir: std.Io.Dir, out: std.Io.Dir) void {
            parseDataDir(file_data, io, alloc, mc_data_dir, out) catch |e| {
                std.debug.print("cauth error {t} in write function!\n", .{e});
                if (@errorReturnTrace()) |st| std.debug.dumpErrorReturnTrace(st);
            };
        }
    };
}

pub fn parseData(io: std.Io, alloc: std.mem.Allocator, mc_data_dir: std.Io.Dir, out: std.Io.Dir, w: *std.Io.Writer) !void {
    try parseDataInner(Parsers, io, alloc, mc_data_dir, out, w, 0);
}

fn parseDataInner(T: type, io: std.Io, alloc: std.mem.Allocator, mc_data_dir: std.Io.Dir, out: std.Io.Dir, w: *std.Io.Writer, depth: usize) !void {
    var group: std.Io.Group = .init;
    inline for (@typeInfo(T).@"struct".decls) |decl| {
        const field = @field(T, decl.name);
        if (@TypeOf(field) == FileData) {
            try w.splatByteAll(' ', depth * 4);
            try w.print("pub const {s} = @import(\"{s}\");\n", .{ decl.name, @field(T, decl.name).path ++ ".zig" });
            const data: FileData = @field(T, decl.name);
            group.async(io, FileDataSerializer(data).parse, .{ io, alloc, mc_data_dir, out });
        } else {
            try w.splatByteAll(' ', depth * 4);
            try w.print("pub const {s} = struct {{\n", .{decl.name});
            try parseDataInner(field, io, alloc, mc_data_dir, out, w, depth + 1);
            try w.splatByteAll(' ', depth * 4);
            try w.writeAll("};\n");
        }
    }
    try group.await(io);
}
