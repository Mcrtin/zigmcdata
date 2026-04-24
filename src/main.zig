const std = @import("std");
const zigmcdata = @import("zigmcdata");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    _ = args.skip();
    const version = args.next().?;
    var out = try std.Io.Dir.cwd().createDirPathOpen(init.io, args.next().?, .{});
    defer out.close(init.io);
    var tmp = try std.Io.Dir.cwd().createDirPathOpen(init.io, args.next().?, .{});
    defer tmp.close(init.io);

    try zigmcdata.gen(init.io, version, out, init.gpa, tmp);
}
