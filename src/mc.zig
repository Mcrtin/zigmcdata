const std = @import("std");
const writeZig = @import("writeZig.zig");

const FileData = struct {
    type_data: []const u8,
    type_file: type,
    path: []const u8,
};
gpa: std.mem.Allocator,
translatables: *const std.StringArrayHashMapUnmanaged([]const u8),

const type_table = std.StaticStringMap(FileData).initComptime(.{
    .{ "worldgen/noise_settings", FileData{
        .path = "worldgen/noise_settings",
        .type_data = @embedFile("embeded/worldgen/noise_settings.zig"),
        .type_file = @import("embeded/worldgen/noise_settings.zig"),
    } },
    .{ "worldgen/density_function", FileData{
        .path = "worldgen/density_function",
        .type_data = @embedFile("embeded/worldgen/density_function.zig"),
        .type_file = @import("embeded/worldgen/density_function.zig").DensityF,
    } },
});

const FileExtension = enum { json, mcmeta, nbt };

pub fn parseDataDir(alloc: std.mem.Allocator, file_data: FileData, mc_data_dir: std.fs.Dir, out: std.fs.Dir) !void {
    std.debug.print("work on: {s}\n", .{file_data.path});
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

    var walker = try dir.walk(alloc);
    defer walker.deinit();
    var last_depth = walker.stack.items.len - 1;
    while (try walker.next()) |f| {
        const depth = walker.stack.items.len - 1;
        std.debug.print("depth: {d}\n", .{depth});
        while (last_depth > depth) : (last_depth -= 1) {
            try w.interface.splatByteAll(' ', (last_depth - 1) * 3);
            try w.interface.writeAll("};\n");
        }
        switch (f.kind) {
            .file => {
                std.debug.print("current file: {s}\n", .{f.basename});
                const file = try f.dir.openFile(f.basename, .{});
                defer file.close();

                var buf: [1024]u8 = undefined;
                var freader = file.reader(&buf);

                const ext = std.meta.stringToEnum(FileExtension, std.fs.path.extension(f.basename)[1..]) orelse return error.WrongFileType;
                switch (ext) {
                    .json, .mcmeta => {
                        const field_name = std.fs.path.stem(f.basename);

                        try w.interface.splatByteAll(' ', depth * 3);
                        try w.interface.writeAll("pub const ");
                        try writeZig.printId(&w.interface, field_name);
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
                        try writeZig.write(&w.interface, depth, val.value);
                        try w.interface.writeAll(";\n");
                    },
                    .nbt => {},
                }
            },
            .directory => {
                if (!(last_depth < depth)) {
                    try w.interface.splatByteAll(' ', (depth - 1) * 3);
                    try w.interface.writeAll("};\n");
                }
                try w.interface.splatByteAll(' ', (depth - 1) * 3);
                try w.interface.writeAll("pub const ");
                try writeZig.printId(&w.interface, try std.fmt.bufPrint(&pbuf, "{s}/", .{f.basename}));
                try w.interface.writeAll(" = struct {\n");
            },

            else => return error.WrongFileType,
        }
        last_depth = depth;
    }
    while (last_depth > 0) : (last_depth -= 1) {
        try w.interface.splatByteAll(' ', (last_depth - 1) * 3);
        try w.interface.writeAll("};\n");
    }
}

pub fn parseData(alloc: std.mem.Allocator, mc_data_dir: std.fs.Dir, out: std.fs.Dir) !void {
    inline for (type_table.values()) |item| {
        try parseDataDir(alloc, item, mc_data_dir, out);
    }
}
