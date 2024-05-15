const std = @import("std");

const Argparser = @import("Argparser.zig");
const NetJson = @import("outputters/NetJson.zig");

const FileParser = @import("FileParser.zig");
const Node = FileParser.Node;
const ModuleMapList = FileParser.ModuleMapList;
const LinkList = FileParser.LinkList;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // var fixed_buffer: [32 * 1024000]u8 = undefined;
    // var fba = std.heap.FixedBufferAllocator.init(&fixed_buffer);
    // defer fba.reset();

    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer aa.deinit();

    // const allocator = fba.allocator();
    //const allocator = gpa.allocator();
    const allocator = aa.allocator();

    const arg_serve_web = "serve";
    const arg_serve_files = "web_files";
    const arg_force_create_file = "force";
    const arg_project_file = "project";
    const arg_output_file = "file";
    const argparser = Argparser.Parser(
        "Render the 'uses' graph of a delphi project (.dpr-file)",
        &[_]Argparser.Arg{
            .{ .longName = arg_project_file, .shortName = 'p', .description = "The project file. Must be a .dpr file.", .argType = .string },
            .{ .longName = arg_output_file, .shortName = 'o', .description = "Output file. If omitted stdout is used.", .default = "", .isOptional = true, .argType = .string },
            .{ .longName = arg_force_create_file, .description = "Truncate output file if exists.", .default = "false", .isOptional = true, .argType = .bool },
            .{ .longName = arg_serve_web, .description = "Start webserver to visualize graph.", .default = "false", .isOptional = true, .argType = .bool },
            .{ .longName = arg_serve_files, .description = "The directory in which web files reside. Path is relative to the current working directory.", .default = "web_files", .isOptional = true, .argType = .string },
        },
    );

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    var parsedargs = argparser.parse(allocator, argv) catch |err| {
        try std.io.getStdErr().writer().print("error: {s}\n", .{@errorName(err)});
        try argparser.printHelp(std.io.getStdErr());
        std.process.exit(1);
    };
    defer parsedargs.deinit();

    const project_file = try getAbsPath(allocator, parsedargs.getArgVal(arg_project_file).string);
    const output_file = try getAbsPath(allocator, parsedargs.getArgVal(arg_output_file).string);
    defer {
        allocator.free(output_file);
        allocator.free(project_file);
    }

    const project_directory = std.fs.path.dirname(project_file).?;

    const rootNode = try allocator.create(FileParser.Node);
    rootNode.* = .{
        .id = 0,
        .unitName = try allocator.dupe(u8, std.fs.path.stem(project_file)), // assume file name matches unit - will be updated later
        .fileName = try allocator.dupe(u8, std.fs.path.basename(project_file)),
        .section = .interface,
        .unitType = .program,
        .uses = std.ArrayList(*FileParser.Node).init(allocator),
    };

    var moduleMap = ModuleMapList.init(allocator);
    var linkList = LinkList.init(allocator);
    defer {
        var mi = moduleMap.iterator();
        while (mi.next()) |ent| {
            const node = ent.value_ptr.*;

            if (node.fileName) |fln| {
                allocator.free(fln);
            }

            if (node.unitName) |un| {
                allocator.free(un);
            }

            node.uses.deinit();

            allocator.free(ent.key_ptr.*);
            allocator.destroy(ent.value_ptr.*);
        }
        moduleMap.deinit();
        linkList.deinit();
    }

    var lkb: [255]u8 = undefined;
    const root_key = try allocator.dupe(u8, std.ascii.lowerString(&lkb, rootNode.unitName.?));
    try moduleMap.put(root_key, rootNode);

    std.debug.print("parsing {s}{c}{?s}\n", .{ project_directory, std.fs.path.sep, rootNode.fileName });
    const start_time = std.time.nanoTimestamp();
    try FileParser.parse_file(allocator, project_directory, rootNode, &moduleMap);
    const elapsed = std.time.nanoTimestamp() - start_time;
    std.debug.print("parsing dependency graph took {d:.3}ms\n", .{@as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(std.time.ns_per_ms))});

    var it = moduleMap.valueIterator();
    while (it.next()) |n| {
        n.*.parsed = false;
    }
    try generateLinkList(rootNode, &linkList);

    const out_stream = os: {
        if (parsedargs.getArgVal(arg_output_file).string.len == 0) {
            break :os std.io.getStdOut();
        } else {
            const flags: std.fs.File.CreateFlags = if (parsedargs.getArgVal(arg_force_create_file).bool) .{ .truncate = true } else .{ .exclusive = true };
            const file = try std.fs.createFileAbsolute(output_file, flags);
            break :os file;
        }
    };
    defer out_stream.close();

    if (parsedargs.getArgVal(arg_serve_web).bool) {
        const Server = @import("server.zig");
        var server = Server.init(allocator, moduleMap, linkList, parsedargs.getArgVal(arg_serve_files).string);
        try server.serve("127.0.0.1", 65353);
    } else {
        try NetJson.write(out_stream.writer().any(), moduleMap, linkList);
    }
}

fn getAbsPath(allocator: std.mem.Allocator, pathArg: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(pathArg)) {
        return try allocator.dupe(u8, pathArg);
    } else {
        const cwd = try std.fs.cwd().realpathAlloc(allocator, "");
        defer allocator.free(cwd);

        const resolvedPath = try std.fs.path.resolve(allocator, &[_][]const u8{pathArg});
        defer allocator.free(resolvedPath);

        return try std.fs.path.join(allocator, &[_][]const u8{ cwd, resolvedPath });
    }
}

fn generateLinkList(node: *FileParser.Node, linkList: *LinkList) !void {
    try generateLinkListInner(node, linkList);

    // normalize link cost to a value between 0 and 1.
    var maxCost: f32 = 0;
    for (linkList.items) |itm| {
        if (itm.cost > maxCost) {
            maxCost = itm.cost;
        }
    }

    for (linkList.items) |*itm| {
        itm.cost = itm.cost / maxCost;
        itm.cost = if (std.math.isNan(itm.cost)) 0 else itm.cost;
    }
}

fn generateLinkListInner(node: *FileParser.Node, linkList: *LinkList) !void {
    if (node.parsed) {
        return;
    }

    node.parsed = true;
    for (node.uses.items) |u| {
        try linkList.append(.{
            .source = node.id,
            .target = u.id,
            .cost = @floatFromInt(u.uses.items.len), // it cost more to use a unit, that includes many units
        });
        try generateLinkListInner(u, linkList);
    }
}

test {
    _ = @import("Argparser.zig");
    _ = @import("Tokenizer.zig");
    _ = @import("FileParser.zig");
}
