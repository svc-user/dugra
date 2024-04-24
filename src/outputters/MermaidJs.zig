const std = @import("std");

const FileParser = @import("../FileParser.zig");
const ModuleMapList = FileParser.ModuleMapList;
const LinkList = FileParser.LinkList;

pub fn write(output: std.fs.File.Writer, moduleMap: ModuleMapList, rootName: []const u8, includeRoot: bool) !void {
    const meta_1 =
        \\---
        \\title: Uses graph for 
    ;

    const meta_2 =
        \\
        \\---
        \\classDiagram
        \\
    ;

    try output.print("{s}{s}{s}", .{ meta_1, rootName, meta_2 });

    var val_iter_classes = moduleMap.valueIterator();
    while (val_iter_classes.next()) |punit| {
        const unit = punit.*;
        unit.parsed = false;
    }

    var val_iter = moduleMap.valueIterator();
    while (val_iter.next()) |punit| {
        const left_unit = punit.*;

        if (!includeRoot and std.mem.eql(u8, rootName, left_unit.unitName.?)) {
            continue;
        }

        for (left_unit.uses.items) |right_unit| {
            if (right_unit.uses.items.len > 0) {
                if (!left_unit.parsed) {
                    try output.print("\tclass `{?s}`\n", .{left_unit.unitName});
                }
                left_unit.parsed = true;

                try output.print("\t`{?s}` ..> `{?s}`\n", .{ left_unit.unitName, right_unit.unitName });
            }
        }
    }
}
