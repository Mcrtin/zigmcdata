const std = @import("std");
const zigmcdata = @import("zigmcdata");

pub fn main() !void {
    var alloc: std.heap.DebugAllocator(.{}) = .{};
    defer _ = alloc.deinit();
    const gpa = alloc.allocator();

    var args = std.process.args();
    _ = args.skip();
    const version = args.next().?;
    var out = try std.fs.cwd().makeOpenPath(args.next().?, .{});
    defer out.close();
    var tmp = try std.fs.cwd().makeOpenPath(args.next().?, .{});
    defer tmp.close();

    try zigmcdata.gen(version, out, gpa, tmp);
}
