const std = @import("std");
const Tag = struct {
    values: []usize,

    pub fn deinit(self: Tag, gpa: std.mem.Allocator) void {
        gpa.free(self.values);
    }
};
const utils = @import("utils.zig");
const Writer = @import("Writer.zig");

const Self = @This();

namespaces: std.ArrayList([]const u8) = .empty,
identifiers: std.StringHashMapUnmanaged(usize) = .empty,
tag_path: std.StringHashMapUnmanaged([]const u8) = .empty,
tags: std.StringHashMapUnmanaged(Tag) = .empty,
arena: std.heap.ArenaAllocator,

pub fn deinit(self: Self) void {
    self.arena.deinit();
}

const DirType = enum { dir, has_files, is_sub };

pub fn parseTags(allocator: std.mem.Allocator, data_dir: std.fs.Dir, out_dir: std.fs.Dir) !Self {
    var start_dir = try data_dir.openDir("tags", .{ .iterate = true });
    var file = try out_dir.createFile("tags.zig", .{});
    defer file.close();
    var buf: [1024]u8 = undefined;
    var fw = file.writer(&buf);
    var w: Writer = .{ .interface = &fw.interface };
    defer w.interface.flush() catch {};

    var tags: Self = .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    errdefer tags.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    const a = arena.allocator();
    defer arena.deinit();
    var name_stack: std.ArrayList([]const u8) = .empty;
    defer {
        std.debug.assert(name_stack.items.len == 0);
        name_stack.deinit(a);
    }
    var waiting_tags: std.ArrayList(struct { []const u8, std.json.Parsed(JsonType) }) = .{};
    defer {
        std.debug.assert(waiting_tags.items.len == 0);
        waiting_tags.deinit(a);
    }

    var dirs: std.ArrayList(struct { std.fs.Dir.Iterator, DirType }) = .{};
    defer {
        std.debug.assert(dirs.items.len == 0);
        dirs.deinit(a);
    }
    try dirs.append(a, .{ start_dir.iterateAssumeFirstIteration(), .dir });
    while (dirs.items.len > 0) {
        var it: *std.fs.Dir.Iterator = @constCast(&dirs.items[dirs.items.len - 1][0]);
        const dir_type = dirs.items[dirs.items.len - 1][1];
        const dir = it.dir;
        if (try it.next()) |f| {
            switch (f.kind) {
                .directory => {
                    const s_name = try a.dupe(u8, f.name);
                    if (dir_type == .dir) {
                        w.assign(s_name, null, true);
                        try w.interface.writeAll("struct {\n");
                        w.indentation += 1;
                    }
                    try name_stack.append(a, s_name);
                    var next_dir = try dir.openDir(f.name, .{ .iterate = true });
                    var it_: std.fs.Dir.Iterator = next_dir.iterateAssumeFirstIteration();
                    const next_dir_type: DirType = switch (dir_type) {
                        .dir => blk: {
                            while (try it_.next()) |item| if (item.kind == .file) {
                                it_.reset();
                                break :blk .has_files;
                            };
                            it_.reset();
                            break :blk .dir;
                        },
                        .has_files => .is_sub,
                        .is_sub => std.debug.panic("Sub dir in sub dir is not supported!", .{}),
                    };
                    try dirs.append(a, .{ it_, next_dir_type });
                },
                .file => {
                    const data = try dir.readFileAlloc(
                        a,
                        f.name,
                        1 << 20,
                    );
                    defer a.free(data);
                    const json_obj = try std.json.parseFromSlice(JsonType, a, data, .{ .allocate = .alloc_always });
                    const field_name = std.fs.path.stem(f.name);
                    const tag_name = switch (dir_type) {
                        .has_files => try std.fmt.allocPrint(a, "#minecraft:{s}", .{field_name}),
                        .is_sub => try std.fmt.allocPrint(a, "#minecraft:{s}/{s}", .{ name_stack.getLast(), field_name }),
                        .dir => unreachable,
                    };
                    const path = try utils.join(u8, a, if (dir_type == .is_sub) name_stack.items[0 .. name_stack.items.len - 1] else name_stack.items, '.');
                    try tags.tag_path.put(a, tag_name, path);
                    try waiting_tags.append(a, .{ tag_name, json_obj });

                    var changed = true;
                    while (changed) {
                        changed = false;
                        var i = waiting_tags.items.len;
                        while (i > 0) {
                            i -= 1;
                            const name, const parsed = waiting_tags.items[i];
                            if (try tags.fromJsonType(a, parsed.value)) |new_tag| {
                                defer parsed.deinit();
                                changed = true;
                                _ = waiting_tags.swapRemove(i);
                                w.assign(name, null, true);

                                try printTag(&w, new_tag, tags.namespaces.items);
                                w.endStatement();
                                try tags.tags.put(a, name, new_tag);
                            }
                        }
                    }
                },
                else => return error.WrongFileType,
            }
        } else {
            var it_, const dir_type_ = dirs.pop().?;
            it_.dir.close();
            if (name_stack.pop()) |name| a.free(name);
            if (dir_type_ != .is_sub) {
                if (w.indentation > 0) {
                    try w.interface.writeAll("}");
                    w.endStatement();
                    w.indentation -= 1;
                }
            }
        }
    }

    w.assign("TagId", null, true);
    try w.interface.writeAll("enum {\n");
    w.indentation += 1;
    {
        var it = tags.tag_path.keyIterator();
        while (it.next()) |item| {
            w.enumField(item.*, null, null);
        }
    }
    // try w.interface.writeAll(
    //     \\
    //     \\pub fn tag(self: TagId) Tag {
    //     \\    return switch(self) {
    //     \\
    // );
    // var it = tags.tag_path.iterator();
    // while (it.next()) |item| {
    //     try w.interface.print("      .@\"{s}\" => {s}.@\"{s}\",\n", .{ item.key_ptr.*, item.value_ptr.*, item.key_ptr.* });
    // }
    // try w.interface.writeAll(
    //     \\  };
    //     \\}
    // );

    w.indentation -= 1;
    w.indent();
    w.interface.writeAll("}") catch unreachable;
    w.endStatement();

    return tags;
}

pub fn getOrCreateId(self: *Self, gpa: std.mem.Allocator, val: []const u8) !usize {
    std.debug.assert(val[0] != '#');
    if (self.identifiers.get(val)) |v| return v else {
        const id: usize = @intCast(self.namespaces.items.len);
        const key = try gpa.dupe(u8, val);
        try self.namespaces.append(gpa, key);
        try self.identifiers.put(gpa, key, id);
        return id;
    }
}

pub const JsonType = struct { values: [][]const u8 };
fn fromJsonType(tags: *Self, gpa: std.mem.Allocator, json: JsonType) !?Tag {
    var list = try std.ArrayList(usize).initCapacity(gpa, json.values.len);
    defer list.deinit(gpa);
    for (json.values) |val| {
        if (val[0] == '#')
            try list.appendSlice(gpa, (tags.tags.get(val) orelse return null).values)
        else
            try list.append(gpa, try tags.getOrCreateId(gpa, val));
    }
    return .{ .values = try list.toOwnedSlice(gpa) };
}

fn printTag(w: *Writer, tag: Tag, identifieres: [][]const u8) !void {
    try w.interface.writeAll(".{\n");
    w.indent();
    try w.interface.writeAll("   .values = &.{\n");
    for (tag.values) |val| {
        w.indent();
        try w.interface.print("    .@\"{s}\",\n", .{identifieres[val]});
    }
    w.indent();
    try w.interface.writeAll("   },\n");

    w.indent();
    try w.interface.writeAll("}");
}
