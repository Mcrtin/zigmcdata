const std = @import("std");
const utils = @import("utils.zig");
const Writer = @import("Writer.zig");

const FileData = struct {
    name: []const u8,
    import: []const u8,
};

pub fn parseMcData(w: *Writer, dir: std.fs.Dir, out_dir: std.fs.Dir, name: []const u8, gpa: std.mem.Allocator, translatables: *std.StringArrayHashMapUnmanaged([]const u8)) !void {
    // var decls = std.ArrayList([]const u8){};
    // defer {
    //     for (decls.items) |decl| {
    //         gpa.free(decl);
    //     }
    //     decls.deinit(gpa);
    // }
    var this_dir: ?std.fs.Dir = null;
    defer if (!std.mem.eql(u8, "root", name) and this_dir != null) this_dir.?.close();
    if (std.mem.eql(u8, "root", name)) this_dir = out_dir;

    var it = dir.iterate();
    while (try it.next()) |f| {
        switch (f.kind) {
            .directory => {
                if (std.mem.eql(u8, f.name, "tags")) continue;
                var next_dir = try dir.openDir(f.name, .{ .iterate = true });
                defer next_dir.close();
                const s_name = try std.fmt.allocPrint(gpa, "{s}/", .{f.name});
                defer gpa.free(s_name);
                w.assign(s_name, null, true);
                if (std.mem.eql(u8, "root", name))
                    try w.interface.print("@import(\"{s}.zig\");\n", .{f.name})
                else
                    try w.interface.print("@import(\"{s}/{s}.zig\");\n", .{ name, f.name });

                if (this_dir == null) {
                    try out_dir.makeDir(name);
                    this_dir = try out_dir.openDir(name, .{});
                }
                const filename = try std.fmt.allocPrint(gpa, "{s}.zig", .{f.name});
                defer gpa.free(filename);
                var file = try this_dir.?.createFile(filename, .{});
                defer file.close();
                var buf: [300]u8 = undefined;
                var wr = file.writer(&buf);
                var w_ = Writer{ .interface = &wr.interface };
                defer w_.interface.flush() catch {};

                try parseMcData(&w_, next_dir, this_dir.?, f.name, gpa, translatables);
            },
            .file => {
                const file = try dir.openFile(f.name, .{});
                defer file.close();

                var buf: [1024]u8 = undefined;
                var freader = file.reader(&buf);

                const ext = std.fs.path.extension(f.name);
                if (std.mem.eql(u8, ext, ".json") or std.mem.eql(u8, ext, ".mcmeta")) {
                    const field_name = std.fs.path.stem(f.name);
                    w.assign(field_name, null, true);
                    // try decls.append(gpa, try gpa.dupe(u8, field_name));

                    var r = std.json.Reader.init(gpa, &freader.interface);
                    defer r.deinit();
                    var json_obj = try std.json.parseFromTokenSource(std.json.Value, gpa, &r, .{});
                    defer json_obj.deinit();

                    try printJson(0, w.interface, json_obj.value, translatables, gpa);
                    w.endStatement();
                } else if (std.mem.eql(u8, ext, ".nbt")) { //TODO
                } else {
                    const path = try dir.realpathAlloc(gpa, f.name);
                    defer gpa.free(path);
                    std.debug.print("file {s} not parsed\n", .{path});
                }
            },
            else => return error.WrongFileType,
        }
    }
    // if (decls.items.len != 0) {
    //     var name_ = try utils.snakeToCamelAlloc(gpa, name);
    //     defer gpa.free(name_);
    //     name_[0] = std.ascii.toUpper(name_[0]);
    //
    //     w.assign(name_, null, true);
    //     w.@"enum"(decls.items, null, null);
    //     w.endStatement();
    // }
}

fn printJson(depth: u32, w: *std.io.Writer, val: std.json.Value, translatables: *std.StringArrayHashMapUnmanaged([]const u8), a: std.mem.Allocator) !void {
    switch (val) {
        .null => try w.writeAll("null"),
        .bool => |v| try w.writeAll(if (v) "true" else "false"),
        .integer => |v| try w.printInt(v, 10, .lower, .{}),
        .float => |v| {
            try w.printFloat(v, .{ .mode = if (v > 1e6) .scientific else .decimal });
            if (std.math.floor(v) == v and v <= 1e6) try w.writeAll(".0");
        },
        .number_string => |v| try w.writeAll(v),
        .string => |v| if (translatables.contains(v)) try w.print("@import(\"root\").lang.Lang.@\"{s}\"", .{v}) else {
            if (std.mem.startsWith(u8, v, "#minecraft:")) {
                try w.writeAll(".@");
            }
            try w.writeByte('"');
            try utils.writeEscaped(w, v);
            try w.writeByte('"');
        },
        .array => |v| {
            try w.writeAll("&.{\n");
            for (v.items) |item| {
                try w.splatByteAll(' ', (depth + 1) * 3);
                try printJson(depth + 2, w, item, translatables, a);
                try w.writeAll(",\n");
            }
            try w.splatByteAll(' ', depth * 3);
            try w.writeAll("}");
        },
        .object => |v| {
            try w.writeAll(".{\n");
            var it = v.iterator();
            while (it.next()) |item| {
                try w.splatByteAll(' ', (depth + 1) * 3);
                if (utils.containsForbiddenChar(item.key_ptr.*))
                    try w.print(".@\"{s}\" = ", .{item.key_ptr.*})
                else
                    try w.print(".{s} = ", .{item.key_ptr.*});

                try printJson(depth + 2, w, item.value_ptr.*, translatables, a);
                try w.writeAll(",\n");
            }
            try w.splatByteAll(' ', depth * 3);
            try w.writeAll("}");
        },
    }
}
