const std = @import("std");
const utils = @import("utils.zig");
pub const Block = struct {
    definition: std.json.ArrayHashMap(std.json.Value),
    properties: std.json.ArrayHashMap([]const []const u8) = .{ .map = .empty },
    states: []const struct {
        id: usize,
        properties: std.json.ArrayHashMap([]const u8) = .{ .map = .empty },
        default: ?bool = null,
    },
};
pub fn gen(gpa: std.mem.Allocator, reader: *std.Io.Reader, out: *std.Io.Writer) !void {
    var r = std.json.Reader.init(gpa, reader);
    defer r.deinit();
    const parsed = try std.json.parseFromTokenSource(std.json.ArrayHashMap(Block), gpa, &r, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const blocks: std.json.ArrayHashMap(Block) = parsed.value;
    var properties: std.StringArrayHashMapUnmanaged([]const []const u8) = .empty;
    defer properties.deinit(gpa);
    const embedded_block = @embedFile("embeded/Block.zig");
    const line_len, const remaining = try split(out, embedded_block, "//__insert_blocks_here__");
    var max_state: usize = 0;
    for (blocks.map.keys(), blocks.map.values()) |k, v| {
        var variants: usize = 1;
        for (v.properties.map.keys(), v.properties.map.values()) |name, prop| {
            try properties.put(gpa, name, prop);
            variants *= prop.len;
        }
        const first = v.states[0].id;
        const last = first + variants - 1;
        max_state = @max(max_state, last);

        try out.splatByteAll(' ', line_len);
        try out.print("{d}...{d} => &@\"{s}\",\n", .{ first, last, k });
    }
    const line_len2, const remaining2 = try split(out, remaining, "//__insert_properties_here__");

    for (properties.keys(), properties.values()) |k, v| {
        try out.splatByteAll(' ', line_len2);
        try out.print("{s}: ", .{k});
        if (v.len == 2 and std.mem.eql(u8, v[0], "true") and std.mem.eql(u8, v[1], "false"))
            try out.writeAll("bool")
        else {
            try out.writeAll("enum { ");
            for (v, 0..) |val, i| {
                if (utils.containsForbiddenChar(val)) {
                    try out.writeAll("@\"");
                    try utils.writeEscaped(out, val);
                    try out.writeByte('"');
                } else try out.writeAll(val);
                if (i + 1 == v.len)
                    try out.writeAll(" ")
                else
                    try out.writeAll(", ");
            }
            try out.writeByte('}');
        }
        try out.writeAll(",\n");
    }
    _, _ = try split(out, remaining2, "//__cut_here__");

    try out.print("pub const MaxState = {d};\n", .{max_state});

    for (blocks.map.keys(), blocks.map.values()) |k, v| {
        var default: usize = undefined;
        for (v.states) |state| {
            if (state.default) |def|
                if (def) {
                    default = state.id;
                    break;
                };
        } else return error.DefaultNotFound;
        var defs = v.definition.map;
        try out.print(
            \\
            \\
            \\pub const @"{s}": Block = .{{
            \\    .name = "{s}",
            \\    .@"type" = "{s}",
            \\    .first_instance = @enumFromInt({d}),
            \\    .default_instance = @enumFromInt({d}),
            \\    .properties = &.{{ 
        , .{ k, k, defs.fetchOrderedRemove("type").?.value.string, v.states[0].id, default });
        for (v.properties.map.keys()) |prop_k| {
            try out.print(".{s}, ", .{prop_k});
        }
        try out.writeAll("},\n");
        std.debug.assert(defs.fetchOrderedRemove("properties").?.value.object.values().len == 0);
        if (defs.values().len > 0) {
            try out.print("    .other = .initComptime(.{{\n", .{});
            for (defs.keys(), defs.values()) |def_k, def_v| {
                try out.print("    .{{ \"{s}\", @as(*const anyopaque, @ptrCast(&", .{def_k});
                try printJson(1, out, def_v, gpa);
                try out.writeAll(")) },\n");
            }
            try out.writeAll("    }),\n");
        }
        try out.writeAll("};");
    }
}

fn split(out: *std.Io.Writer, str: []const u8, splitter: []const u8) !struct { usize, []const u8 } {
    const blocks_start = std.mem.indexOf(u8, str, splitter).?;
    const last_newline = std.mem.lastIndexOfScalar(u8, str[0..blocks_start], '\n').?;
    const line_len = blocks_start - last_newline - 1;
    try out.writeAll(str[0 .. last_newline + 1]);
    return .{ line_len, str[blocks_start + splitter.len ..] };
}

fn printJson(depth: u32, w: *std.Io.Writer, val: std.json.Value, a: std.mem.Allocator) !void {
    switch (val) {
        .null => try w.writeAll("null"),
        .bool => |v| try w.writeAll(if (v) "true" else "false"),
        .integer => |v| try w.printInt(v, 10, .lower, .{}),
        .float => |v| try w.printFloat(v, .{ .precision = 1 }),
        .number_string => |v| try w.writeAll(v),
        .string => |v| {
            try w.writeAll("@as([]const u8, \"");
            try utils.writeEscaped(w, v);
            try w.writeAll("\")");
        },
        .array => |v| {
            try w.writeAll("&.{\n");
            for (v.items) |item| {
                try w.splatByteAll(' ', depth * 3);
                try printJson(depth + 1, w, item, a);
                try w.writeAll(",\n");
            }
            try w.splatByteAll(' ', depth * 3);
            try w.writeAll("}");
        },
        .object => |v| {
            try w.writeAll(".{\n");
            var it = v.iterator();
            while (it.next()) |item| {
                try w.splatByteAll(' ', depth * 3);
                if (utils.containsForbiddenChar(item.key_ptr.*))
                    try w.print(".@\"{s}\" = ", .{item.key_ptr.*})
                else
                    try w.print(".{s} = ", .{item.key_ptr.*});

                try printJson(depth + 1, w, item.value_ptr.*, a);
                try w.writeAll(",\n");
            }
            try w.splatByteAll(' ', depth * 3);
            try w.writeAll("}");
        },
    }
}
