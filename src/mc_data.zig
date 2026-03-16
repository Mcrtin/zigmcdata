const std = @import("std");
const utils = @import("utils.zig");
const Writer = @import("Writer.zig");

const FileData = struct {
    name: []const u8,
    type_data: []const u8,
    type_location: ?[]const u8,
    nullable: []const []const u8,
    references: []const struct {
        refs: []const []const u8,
        to: []const u8,
        name: []const u8,
    },
};
gpa: std.mem.Allocator,
translatables: *const std.StringArrayHashMapUnmanaged([]const u8),

const type_table = std.StaticStringMap(FileData).initComptime(.{
    .{ "noise_settings", FileData{
        .name = "NoiseSettings",
        .type_data = @embedFile("embeded/NoiseSettings.zig"),
        .type_location = null,
        .nullable = &.{
            "barrier",
            "continents",
            "depth",
            "erosion",
            "final_density",
            "fluid_level_floodedness",
            "fluid_level_spread",
            "lava",
            "preliminary_surface_level",
            "ridges",
            "temperature",
            "vegetation",
            "vein_gap",
            "vein_ridged",
            "vein_toggle",
            "depth",
            "offset",
        },
        .references = &.{.{
            .refs = &.{
                "argument",
                "argument1",
                "argument2",
                "input",
                "shift_x",
                "shift_y",
                "shift_z",
                "lower_bound",
                "upper_bound",
                "density",
                "when_in_range",
                "when_out_of_range",
                "coordinate",
                "barrier",
                "continents",
                "depth",
                "erosion",
                "final_density",
                "fluid_level_floodedness",
                "fluid_level_spread",
                "lava",
                "preliminary_surface_level",
                "ridges",
                "temperature",
                "vegetation",
                "vein_gap",
                "vein_ridged",
                "vein_toggle",
                "depth",
                "offset",
            },
            .to = ".@\"worldgen/\".@\"density_function/\".DensityF",
            .name = "Df",
        }},
    } },
    .{ "density_function", FileData{
        .name = "DensityFunction",
        .type_data = @embedFile("embeded/DensityFunction.zig"),
        .type_location = ".@\"worldgen/\".@\"density_function/\"",
        .nullable = &.{},
        .references = &.{.{
            .refs = &.{
                "argument",
                "argument1",
                "argument2",
                "input",
                "shift_x",
                "shift_y",
                "shift_z",
                "lower_bound",
                "upper_bound",
                "density",
                "when_in_range",
                "when_out_of_range",
                "coordinate",
            },
            .to = ".@\"worldgen/\".@\"density_function/\".DensityF",
            .name = "Df",
        }},
    } },
});

pub fn parseMcData(self: @This(), w: *Writer, dir: std.fs.Dir, out_dir: std.fs.Dir, name: ?[]const u8, data: ?FileData, depth: u8) !void {
    var this_dir: ?std.fs.Dir = null;
    defer if (name != null and this_dir != null) this_dir.?.close();
    if (name == null) this_dir = out_dir;
    const is_child = data != null;
    const file_data = if (name) |n| data orelse type_table.get(n) else null;
    var map: std.StringHashMapUnmanaged(void) = .empty;
    defer map.deinit(self.gpa);
    if (file_data) |fd|
        for (fd.nullable) |nullable| try map.put(self.gpa, nullable, {});
    if (file_data) |fd| {
        if (!is_child) try w.interface.writeAll(fd.type_data);
    }
    var map2: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer map2.deinit(self.gpa);

    if (file_data) |fd| {
        for (fd.references) |ref| {
            w.assign(ref.name, null, true);
            try w.interface.writeAll("@import(\"");
            try w.interface.splatBytesAll("../", depth - 1);
            try w.interface.writeAll("root.zig\")");
            try w.interface.writeAll(ref.to);
            w.endStatement();
            for (ref.refs) |r| try map2.put(self.gpa, r, ref.name);
        }
    }

    var it = dir.iterate();
    while (try it.next()) |f| {
        switch (f.kind) {
            .directory => {
                if (std.mem.eql(u8, f.name, "tags")) continue;
                var next_dir = try dir.openDir(f.name, .{ .iterate = true });
                defer next_dir.close();
                const s_name = try std.fmt.allocPrint(self.gpa, "{s}/", .{f.name});
                defer self.gpa.free(s_name);
                w.assign(s_name, null, true);
                if (name == null)
                    try w.interface.print("@import(\"{s}.zig\");\n", .{f.name})
                else
                    try w.interface.print("@import(\"{s}/{s}.zig\");\n", .{ name.?, f.name });

                if (this_dir == null) {
                    try out_dir.makeDir(name.?);
                    this_dir = try out_dir.openDir(name.?, .{});
                }
                const filename = try std.fmt.allocPrint(self.gpa, "{s}.zig", .{f.name});
                defer self.gpa.free(filename);
                var file = try this_dir.?.createFile(filename, .{});
                defer file.close();
                var buf: [300]u8 = undefined;
                var wr = file.writer(&buf);
                var w_ = Writer{ .interface = &wr.interface };
                defer w_.interface.flush() catch {};

                try self.parseMcData(&w_, next_dir, this_dir.?, f.name, data, depth + 1);
            },
            .file => {
                const file = try dir.openFile(f.name, .{});
                defer file.close();

                var buf: [1024]u8 = undefined;
                var freader = file.reader(&buf);

                const ext = std.fs.path.extension(f.name);
                if (std.mem.eql(u8, ext, ".json") or std.mem.eql(u8, ext, ".mcmeta")) {
                    const field_name = std.fs.path.stem(f.name);

                    w.assign(field_name, if (file_data) |fd| fd.name else null, true);

                    var r = std.json.Reader.init(self.gpa, &freader.interface);
                    defer r.deinit();
                    var json_obj = try std.json.parseFromTokenSource(std.json.Value, self.gpa, &r, .{});
                    defer json_obj.deinit();
                    const json_printer: JsonPrinter = .{
                        .translatables = self.translatables,
                        .a = self.gpa,
                        .w = w.interface,
                        .nullable = &map,
                        .references = &map2,
                        .value_union = file_data != null and std.mem.eql(u8, file_data.?.name, "DensityFunction"),
                    };

                    try json_printer.printJson(0, json_obj.value, false, null, true);
                    w.endStatement();
                } else if (std.mem.eql(u8, ext, ".nbt")) { //TODO
                } else {
                    const path = try dir.realpathAlloc(self.gpa, f.name);
                    defer self.gpa.free(path);
                    std.debug.print("file {s} not parsed\n", .{path});
                }
            },
            else => return error.WrongFileType,
        }
    }
}

//TODO: doesn't resolve references?! dfs should be nullable (zero) if in references -- remove nullable
const JsonPrinter = struct {
    translatables: *const std.StringArrayHashMapUnmanaged([]const u8),
    a: std.mem.Allocator,
    w: *std.io.Writer,
    nullable: *const std.StringHashMapUnmanaged(void),
    references: *const std.StringHashMapUnmanaged([]const u8),
    value_union: bool,

    fn printJson(self: @This(), depth: u32, val: std.json.Value, nullable: bool, ref: ?[]const u8, first: bool) !void {
        var d = depth;
        switch (val) {
            .null => try self.w.writeAll("null"),
            .bool => |v| try self.w.writeAll(if (v) "true" else "false"),
            .integer => |v| if (nullable and v == 0) try self.w.writeAll("null") else try self.w.printInt(v, 10, .lower, .{}),
            .float => |v| {
                if (ref) |_| {
                    try self.w.writeAll(".{\n");
                    d += 1;
                    try self.w.splatByteAll(' ', d * 3);
                    try self.w.writeAll(".float = ");
                }
                if (nullable and v == 0) try self.w.writeAll("null") else {
                    try self.w.printFloat(v, .{ .mode = if (v > 1e6) .scientific else .decimal });
                    if (std.math.floor(v) == v and v <= 1e6) try self.w.writeAll(".0");
                }
                if (ref) |_| {
                    d -= 1;
                    try self.w.writeAll(",\n");
                    try self.w.splatByteAll(' ', d * 3);
                    try self.w.writeAll("}");
                }
            },
            .number_string => |v| try self.w.writeAll(v),
            .string => |v| if (ref) |_| {
                try self.w.writeAll(".{\n");
                d += 1;
                try self.w.splatByteAll(' ', d * 3);
                try self.w.writeAll(".string = ");
                std.debug.assert(std.mem.startsWith(u8, v, "minecraft:"));
                // try self.w.writeByte('&');
                // try self.w.writeAll(r);
                // var it = std.mem.splitScalar(u8, v["minecraft:".len..], '/');
                // var i = it.index.?;
                // while (it.next()) |_| : (i = it.index orelse 0) {
                //     const next = it.buffer[i .. it.index orelse it.buffer.len];
                //     try self.w.writeByte('.');
                //     try utils.writeId(self.w, next);
                // }
                try self.w.writeByte('"');
                try utils.writeEscaped(self.w, v);
                try self.w.writeByte('"');
                d -= 1;
                try self.w.writeAll(",\n");
                try self.w.splatByteAll(' ', d * 3);
                try self.w.writeAll("}");
            } else {
                if (self.translatables.contains(v)) try self.w.print("@import(\"root\").lang.Lang.@\"{s}\"", .{v}) else {
                    if (std.mem.startsWith(u8, v, "#minecraft:")) {
                        try self.w.writeAll(".@");
                    }
                    try self.w.writeByte('"');
                    try utils.writeEscaped(self.w, v);
                    try self.w.writeByte('"');
                }
            },
            .array => |v| {
                try self.w.writeAll("&.{\n");
                d += 1;
                for (v.items) |item| {
                    try self.w.splatByteAll(' ', (d) * 3);
                    try self.printJson(d, item, false, null, false);
                    try self.w.writeAll(",\n");
                }
                d -= 1;
                try self.w.splatByteAll(' ', d * 3);
                try self.w.writeAll("}");
            },
            .object => |v| {
                if (ref) |_| {
                    try self.w.writeAll(".{\n");
                    d += 1;
                    try self.w.splatByteAll(' ', d * 3);
                    try self.w.writeAll(".object = ");
                }
                const typed = if (v.get("type")) |t| t == .string else false;
                if (typed) {
                    if (!first) try self.w.writeByte('&');
                    try self.w.writeAll(".{\n");
                    d += 1;
                    try self.w.splatByteAll(' ', d * 3);
                    const name = v.get("type").?.string;
                    if (utils.containsForbiddenChar(name))
                        try self.w.print(".@\"{s}\" = ", .{name})
                    else
                        try self.w.print(".{s} = ", .{name});
                }
                try self.w.writeAll(".{\n");
                var it = v.iterator();
                d += 1;
                while (it.next()) |item| {
                    const name = item.key_ptr.*;
                    if (typed and std.mem.eql(u8, name, "type")) continue;
                    try self.w.splatByteAll(' ', d * 3);
                    if (utils.containsForbiddenChar(name))
                        try self.w.print(".@\"{s}\" = ", .{name})
                    else
                        try self.w.print(".{s} = ", .{name});

                    if (self.value_union and std.mem.eql(u8, name, "value"))
                        try self.w.print(".{{ .{s} = ", .{@tagName(item.value_ptr.*)});

                    try self.printJson(d, item.value_ptr.*, self.nullable.get(name), self.references.get(name), false);
                    if (self.value_union and std.mem.eql(u8, name, "value"))
                        try self.w.writeAll(" }");
                    try self.w.writeAll(",\n");
                }
                d -= 1;
                try self.w.splatByteAll(' ', d * 3);
                try self.w.writeAll("}");
                if (typed) {
                    d -= 1;
                    try self.w.writeAll(",\n");
                    try self.w.splatByteAll(' ', d * 3);
                    try self.w.writeAll("}");
                }
                if (ref) |_| {
                    d -= 1;
                    try self.w.writeAll(",\n");
                    try self.w.splatByteAll(' ', d * 3);
                    try self.w.writeAll("}");
                }
            },
        }
    }
};
