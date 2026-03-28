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
    };
};

const FileExtension = enum { json, mcmeta, nbt };

pub fn parseDataDir(alloc: std.mem.Allocator, file_data: FileData, mc_data_dir: std.fs.Dir, out: std.fs.Dir) !void {
    var pbuf: [std.fs.max_path_bytes]u8 = undefined;
    var dir = try mc_data_dir.openDir(file_data.path, .{ .iterate = true });
    defer dir.close();
    var out_dir = try out.makeOpenPath(std.fs.path.dirname(file_data.path).?, .{});
    defer out_dir.close();
    const out_file = try out_dir.createFile(std.fmt.bufPrint(&pbuf, "{s}.zig", .{std.fs.path.basename(file_data.path)}) catch unreachable, .{});
    defer out_file.close();
    var wbuf: [1024]u8 = undefined;
    var w = out_file.writer(&wbuf);
    defer w.interface.flush() catch {};

    try w.interface.writeAll(file_data.type_data);

    var walker = try dir.walk(alloc);
    defer walker.deinit();
    while (try walker.next()) |f| {
        switch (f.kind) {
            .file => {
                const file = try f.dir.openFile(f.basename, .{});
                defer file.close();

                var buf: [1024]u8 = undefined;
                var freader = file.reader(&buf);

                const ext = std.meta.stringToEnum(FileExtension, std.fs.path.extension(f.basename)[1..]) orelse return error.WrongFileType;
                switch (ext) {
                    .json, .mcmeta => {
                        try w.interface.writeAll("pub const ");
                        try writeZig.printId(&w.interface, try std.fmt.bufPrint(&pbuf, "minecraft:{s}", .{f.path[0 .. f.path.len - std.fs.path.extension(f.path).len]}));
                        try w.interface.print(": {s}", .{file_data.type_name});

                        try w.interface.writeAll(" = ");

                        var r = std.json.Reader.init(alloc, &freader.interface);
                        defer r.deinit();
                        const val = std.json.parseFromTokenSource(file_data.type_file, alloc, &r, .{}) catch |e| {
                            if (r.peekNextTokenType()) |next_token| {
                                std.debug.print("next token: {t}\n", .{next_token});
                            } else |e2| {
                                std.debug.print("next token errored: {t}\n", .{e2});
                            }
                            return e;
                        };
                        defer val.deinit();
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

pub fn parseData(alloc: std.mem.Allocator, mc_data_dir: std.fs.Dir, out: std.fs.Dir, w: *std.Io.Writer) !void {
    try parseDataInner(Parsers, alloc, mc_data_dir, out, w, 0);
}

fn parseDataInner(T: type, alloc: std.mem.Allocator, mc_data_dir: std.fs.Dir, out: std.fs.Dir, w: *std.Io.Writer, depth: usize) !void {
    inline for (@typeInfo(T).@"struct".decls) |decl| {
        const field = @field(T, decl.name);
        if (@TypeOf(field) == FileData) {
            try w.splatByteAll(' ', depth * 4);
            try w.print("pub const {s} = @import(\"{s}\");\n", .{ decl.name, @field(T, decl.name).path ++ ".zig" });
            try parseDataDir(alloc, @field(T, decl.name), mc_data_dir, out);
        } else {
            try w.splatByteAll(' ', depth * 4);
            try w.print("pub const {s} = struct {{\n", .{decl.name});
            try parseDataInner(field, alloc, mc_data_dir, out, w, depth + 1);
            try w.splatByteAll(' ', depth * 4);
            try w.writeAll("};\n");
        }
    }
}
