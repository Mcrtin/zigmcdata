const std = @import("std");
const utils = @import("utils.zig");
const Writer = @import("Writer.zig");

const FileData = struct {
    name: []const u8,
    import: []const u8,
};
gpa: std.mem.Allocator,
translatables: *std.StringArrayHashMapUnmanaged([]const u8),

pub fn parseMcData(self: @This(), w: *Writer, dir: std.fs.Dir, out_dir: std.fs.Dir, name: ?[]const u8) !void {
    var this_dir: ?std.fs.Dir = null;
    defer if (name != null and this_dir != null) this_dir.?.close();
    if (name == null) this_dir = out_dir;

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

                try self.parseMcData(&w_, next_dir, this_dir.?, f.name);
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

                    var r = std.json.Reader.init(self.gpa, &freader.interface);
                    defer r.deinit();
                    var json_obj = try std.json.parseFromTokenSource(std.json.Value, self.gpa, &r, .{});
                    defer json_obj.deinit();
                    const json_printer: JsonPrinter = .{ .translatables = self.translatables, .a = self.gpa, .w = w.interface };

                    try json_printer.printJson(0, json_obj.value);
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

const JsonPrinter = struct {
    translatables: *std.StringArrayHashMapUnmanaged([]const u8),
    a: std.mem.Allocator,
    w: *std.io.Writer,

    fn printJson(self: @This(), depth: u32, val: std.json.Value) !void {
        var d = depth;
        switch (val) {
            .null => try self.w.writeAll("null"),
            .bool => |v| try self.w.writeAll(if (v) "true" else "false"),
            .integer => |v| try self.w.printInt(v, 10, .lower, .{}),
            .float => |v| {
                try self.w.printFloat(v, .{ .mode = if (v > 1e6) .scientific else .decimal });
                if (std.math.floor(v) == v and v <= 1e6) try self.w.writeAll(".0");
            },
            .number_string => |v| try self.w.writeAll(v),
            .string => |v| if (self.translatables.contains(v)) try self.w.print("@import(\"root\").lang.Lang.@\"{s}\"", .{v}) else {
                if (std.mem.startsWith(u8, v, "#minecraft:")) {
                    try self.w.writeAll(".@");
                }
                try self.w.writeByte('"');
                try utils.writeEscaped(self.w, v);
                try self.w.writeByte('"');
            },
            .array => |v| {
                try self.w.writeAll("&.{\n");
                d += 1;
                for (v.items) |item| {
                    try self.w.splatByteAll(' ', (d) * 3);
                    try self.printJson(d + 1, item);
                    try self.w.writeAll(",\n");
                }
                d -= 1;
                try self.w.splatByteAll(' ', d * 3);
                try self.w.writeAll("}");
            },
            .object => |v| {
                const typed = if (v.get("type")) |t| t == .string else false;
                if (typed) {
                    try self.w.writeAll(".{\n");
                    d += 1;
                    try self.w.splatByteAll(' ', (d) * 3);
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
                    try self.w.splatByteAll(' ', (d) * 3);
                    if (utils.containsForbiddenChar(name))
                        try self.w.print(".@\"{s}\" = ", .{name})
                    else
                        try self.w.print(".{s} = ", .{name});

                    try self.printJson(d + 1, item.value_ptr.*);
                    try self.w.writeAll(",\n");
                }
                d -= 1;
                try self.w.splatByteAll(' ', d * 3);
                try self.w.writeAll("}");
                if (typed) {
                    d -= 1;
                    try self.w.splatByteAll(' ', d * 3);
                    try self.w.writeAll("}");
                }
            },
        }
    }
};
