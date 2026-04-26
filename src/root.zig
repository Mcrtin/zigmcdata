const std = @import("std");
const lang = @import("lang.zig");
const Tags = @import("Tags.zig");
const mc = @import("mc.zig");
const block = @import("block.zig");
const biome_parameters = @import("biome_parameters.zig");

const VersionType = enum { snapshot, release, old_alpha, old_beta };
const VersionData = struct { id: []const u8, type: VersionType, url: []const u8, time: []const u8, releaseTime: []const u8 };
const Package = struct {
    arguments: struct {
        @"default-user-jvm": ?std.json.Value = null,
        game: std.json.Value,
        jvm: std.json.Value,
    },
    // assetIndex: struct { id: usize, sha1: []const u8, size: usize, totalSize: usize, url: []const u8 },
    assets: usize,
    complianceLevel: u8,
    downloads: struct {
        client: struct { sha1: []const u8, size: usize, url: []const u8 },
        server: struct { sha1: []const u8, size: usize, url: []const u8 },
    },
    javaVersion: struct { component: []const u8, majorVersion: u8 },
    libraries: []struct { downloads: struct { artifact: struct {
        path: []const u8,
        sha1: []const u8,
        size: usize,
        url: []const u8,
    } }, name: []const u8 },
    // logging: struct { client: struct { argument: []const u8, file: struct { id: []const u8, sha1: []const u8, size: usize, url: []const u8 }, type: []const u8 } },
    mainClass: []const u8,
    minimumLauncherVersion: u32,

    id: []const u8,
    type: VersionType,
    releaseTime: []const u8,
    time: []const u8,
};
const Versions = struct {
    latest: struct { release: []const u8, snapshot: []const u8 },
    versions: []VersionData,
};
const manifest_url = std.Uri.parse("https://launchermeta.mojang.com/mc/game/version_manifest.json") catch unreachable;

pub fn gen(io: std.Io, version: []const u8, out: std.Io.Dir, gpa: std.mem.Allocator, tmp: std.Io.Dir) !void {
    var json_out = try tmp.createDirPathOpen(io, "json", .{ .open_options = .{ .iterate = true } });
    defer json_out.close(io);
    var tmp_out = try tmp.createDirPathOpen(io, "server", .{});
    defer tmp_out.close(io);

    var it = json_out.iterateAssumeFirstIteration();
    if (try it.next(io) == null)
        try downloadAndExtractServer(io, gpa, version, json_out, tmp_out)
    else
        it = json_out.iterate();
    const translables: std.json.Parsed(std.json.ArrayHashMap([]const u8)) = blk: {
        const lang_file = try json_out.openFile(io, "assets/minecraft/lang/en_us.json", .{});
        defer lang_file.close(io);
        const out_lang = try out.createFile(io, "lang.zig", .{});
        defer out_lang.close(io);
        var buf: [1024]u8 = undefined;
        var wbuf: [1024]u8 = undefined;
        var w = out_lang.writer(io, &wbuf);
        defer w.interface.flush() catch {};
        var lang_reader = lang_file.reader(io, &buf);
        const lang_data = try readJson(gpa, std.json.ArrayHashMap([]const u8), &lang_reader.interface);
        errdefer lang_data.deinit();
        try lang.gen(&w.interface, &lang_data.value.map);
        break :blk lang_data;
    };
    defer translables.deinit();
    {
        const f = try json_out.openFile(io, "reports/blocks.json", .{});
        defer f.close(io);
        const out_lang = try out.createFile(io, "Block.zig", .{});
        defer out_lang.close(io);
        var buf: [1024]u8 = undefined;
        var wbuf: [1024]u8 = undefined;
        var w = out_lang.writer(io, &wbuf);
        defer w.interface.flush() catch {};
        var r = f.reader(io, &buf);
        try block.gen(gpa, &r.interface, &w.interface);
    }
    {
        var dir = try json_out.openDir(io, "reports/biome_parameters/minecraft", .{ .iterate = true });
        defer dir.close(io);
        const out_file = try out.createFile(io, "BiomeParameters.zig", .{});
        defer out_file.close(io);
        var wbuf: [1024]u8 = undefined;
        var w = out_file.writer(io, &wbuf);
        defer w.interface.flush() catch {};
        try biome_parameters.gen(io, gpa, &dir, &w.interface);
    }
    {
        var mc_data_dir = try json_out.openDir(io, "data/minecraft/", .{ .iterate = true });
        defer mc_data_dir.close(io);

        // var tags = try Tags.parseTags(io, gpa, mc_data_dir, out); TODO
        // defer tags.deinit();
        var file = try out.createFile(io, "root.zig", .{});
        defer file.close(io);
        var buf: [300]u8 = undefined;
        var w = file.writer(io, &buf);
        defer w.interface.flush() catch {};

        try w.interface.writeAll("pub const Lang = @import(\"lang.zig\").Lang;\n");
        // try w.interface.writeAll("pub const tags = @import(\"tags.zig\");\n");
        try w.interface.writeAll("pub const Block = @import(\"Block.zig\");\n");
        try w.interface.writeAll("pub const BiomeParameters = @import(\"BiomeParameters.zig\");\n");

        try mc.parseData(io, gpa, mc_data_dir, out, &w.interface);
    }
}

pub fn downloadAndExtractServer(
    io: std.Io,
    gpa: std.mem.Allocator,
    version: []const u8,
    out_dir: std.Io.Dir,
    tmp_dir: std.Io.Dir,
) !void {
    var client = std.http.Client{ .allocator = gpa, .io = io };
    defer client.deinit();

    // ------------------------------------------------------------
    // Step 1: Download version manifest
    // ------------------------------------------------------------
    std.debug.print("downloading manifest\n", .{});
    const versions = try requestJson(Versions, gpa, &client, manifest_url);
    defer versions.deinit();
    var version_data: ?VersionData = null;
    for (versions.value.versions) |v|
        if (std.mem.eql(u8, v.id, version)) {
            version_data = v;
            break;
        };

    if (version_data == null) return error.VersionNotFouud;
    const version_url = try std.Uri.parse(version_data.?.url);

    // ------------------------------------------------------------
    // Step 2: Download version metadata
    // ------------------------------------------------------------
    std.debug.print("downloading metadata\n", .{});
    const package = try requestJson(Package, gpa, &client, version_url);
    defer package.deinit();
    const server_url = try std.Uri.parse(package.value.downloads.server.url);

    // ------------------------------------------------------------
    // Step 3: Download server jar
    // ------------------------------------------------------------
    var tmp_server_jar = try tmp_dir.createFile(io, "server.jar", .{ .read = true });
    {
        std.debug.print("downloading server.jar\n", .{});
        var wbuf: [1024]u8 = undefined;
        var w = tmp_server_jar.writer(io, &wbuf);
        const s = try client.fetch(.{ .location = .{ .uri = server_url }, .response_writer = &w.interface });
        if (s.status.class() != .success) return error.ServerJarFetchFailed;
        try w.interface.flush();
    }

    // // ------------------------------------------------------------
    // // Step 4: Extract jar (zip archive)
    // // ------------------------------------------------------------
    // const path = try std.fmt.allocPrint(gpa, "META-INF/versions/{s}/server-{s}.jar", .{ version, version });
    // defer gpa.free(path);
    // {
    //     std.debug.print("extracting inner server.jar\n", .{});
    //     var buf: [1024]u8 = undefined;
    //     var r = tmp_server_jar.reader(io, &buf);
    //
    //     var iter = try std.zip.Iterator.init(&r);
    //     var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
    //     while (try iter.next()) |item| {
    //         try r.seekTo(item.header_zip_offset + @sizeOf(std.zip.CentralDirectoryFileHeader));
    //         const filename = filename_buf[0..item.filename_len];
    //         try r.interface.readSliceAll(filename);
    //         if (std.mem.eql(u8, filename, path))
    //             try item.extract(&r, .{}, &filename_buf, tmp_dir);
    //     }
    // }

    {
        std.debug.print("generating reports\n", .{});
        const res = try std.process.run(gpa, io, .{
            .cwd = .{ .dir = tmp_dir },
            .expand_arg0 = .expand,
            .argv = &.{ "java", "-DbundlerMainClass=net.minecraft.data.Main", "-jar", "server.jar", "--reports", "--output", "../json" },
        });
        defer gpa.free(res.stderr);
        defer gpa.free(res.stdout);
        if (res.term.exited != 0) {
            std.debug.print("something went wrong when running java; error trace:\n{s}", .{res.stderr});
            return error.JavaErrored;
        }
    }

    {
        std.debug.print("extracting server.jar\n", .{});
        var buf: [1024]u8 = undefined;
        const path = try std.fmt.allocPrint(gpa, "versions/{s}/server-{s}.jar", .{ version, version });
        defer gpa.free(path);
        var f = try tmp_dir.openFile(io, path, .{});
        defer f.close(io);
        var r = f.reader(io, &buf);
        try std.zip.extract(out_dir, &r, .{});
        //
        // var iter = try std.zip.Iterator.init(&r);
        // var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
        // while (try iter.next()) |item| {
        //     try r.seekTo(item.header_zip_offset + @sizeOf(std.zip.CentralDirectoryFileHeader));
        //     const filename = filename_buf[0..item.filename_len];
        //     try r.interface.readSliceAll(filename);
        //     if (std.mem.startsWith(u8, filename, "data") or std.mem.startsWith(u8, filename, "asset"))
        //         try item.extract(&r, .{}, &filename_buf, out_dir);
        // }
    }
}

fn requestJson(T: type, gpa: std.mem.Allocator, client: *std.http.Client, url: std.Uri) !std.json.Parsed(T) {
    var req = try client.request(.GET, url, .{});

    defer req.deinit();
    try req.sendBodiless();
    var redirect_buf: [8 * 1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buf);

    var transfer_buf: [64]u8 = undefined;
    var compress_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buf, &decompress, &compress_buf);

    return readJson(gpa, T, reader);
}

pub fn readJson(gpa: std.mem.Allocator, T: type, reader: *std.Io.Reader) !std.json.Parsed(T) {
    var r = std.json.Reader.init(gpa, reader);
    defer r.deinit();
    return try std.json.parseFromTokenSource(T, gpa, &r, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
