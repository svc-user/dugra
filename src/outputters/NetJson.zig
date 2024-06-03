const std = @import("std");
const FileParser = @import("../FileParser.zig");
const ModuleMapList = FileParser.ModuleMapList;

pub fn write(output: std.io.AnyWriter, moduleMap: ModuleMapList) !void {
    try output.print("[\n\t ", .{});
    try printNodes(moduleMap, output);
    try output.print("]\n", .{});
}

fn printNodes(nodes: ModuleMapList, output: std.io.AnyWriter) !void {
    var i: usize = 0;
    var it = nodes.valueIterator();
    while (it.next()) |node| {
        const dnode = node.*;
        try output.print("{{ \"id\": {d}, \"name\": \"{s}\", \"parent\": {?d}, \"properties\": {{ \"type\": \"{s}\", \"usesCount\": {d} }} }}\n", .{ dnode.id, dnode.unitName.?, dnode.parent, @tagName(dnode.unitType), dnode.uses.items.len });
        if (i != nodes.unmanaged.size - 1) {
            try output.print("\t,", .{});
        }
        i += 1;
    }
}
