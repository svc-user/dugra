const std = @import("std");
const FileParser = @import("../FileParser.zig");
const ModuleMapList = FileParser.ModuleMapList;
const LinkList = FileParser.LinkList;

pub fn write(output: std.fs.File.Writer, moduleMap: ModuleMapList, linkList: LinkList) !void {
    try output.print(
        \\{{
        \\  "type": "NetworkGraph",
        \\  "protocol": "static",
        \\  "version": null,
        \\  "metric": null,
        \\  
    , .{});
    try printNodes(moduleMap, output);
    try output.print(", \n", .{});
    try printLinks(linkList, output);
    try output.print(" }}\n", .{});
}

fn printNodes(nodes: ModuleMapList, output: std.fs.File.Writer) !void {
    try output.print("\"nodes\": [\n\t ", .{});
    var i: usize = 0;
    var it = nodes.valueIterator();
    while (it.next()) |node| {
        const dnode = node.*;
        try output.print("{{ \"id\": {d}, \"label\": \"{s}\", \"name\": \"{s}\", \"properties\": {{ \"type\": \"{s}\", \"usesCount\": {d} }} }}\n", .{ dnode.id, dnode.unitName.?, dnode.unitName.?, @tagName(dnode.unitType), dnode.uses.items.len });
        if (i != nodes.unmanaged.size - 1) {
            try output.print("\t,", .{});
        }
        i += 1;
    }

    try output.print("]", .{});
}

fn printLinks(links: LinkList, output: std.fs.File.Writer) !void {
    try output.print("\"links\": [\n\t ", .{});
    var i: usize = 0;
    for (links.items) |link| {
        try output.print("{{ \"source\": {d}, \"target\": {d}, \"cost\": {d:.5} }}\n", .{ link.source, link.target, link.cost });
        if (i != links.items.len - 1) {
            try output.print("\t,", .{});
        }
        i += 1;
    }

    try output.print("]", .{});
}
