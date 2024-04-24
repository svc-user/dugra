const std = @import("std");

const FileParser = @import("../FileParser.zig");
const ModuleMapList = FileParser.ModuleMapList;
const LinkList = FileParser.LinkList;

pub fn write(output: std.fs.File.Writer, moduleMap: ModuleMapList, rootName: []const u8, includeRoot: bool, includeLeafs: bool) !void {
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

    std.debug.print("writing output for {d} nodes\n", .{moduleMap.count()});

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
            std.debug.print("skipping node {?s}\n", .{left_unit.unitName});
            continue;
        }

        for (left_unit.uses.items) |right_unit| {
            if (right_unit.uses.items.len > 0 or includeLeafs) {
                if (!left_unit.parsed) {
                    std.debug.print("writing class {?s}..\n", .{left_unit.unitName});
                    try output.print("\tclass `{?s}`\n", .{left_unit.unitName});
                }
                left_unit.parsed = true;

                std.debug.print("writing relation between {?s} and {?s}..\n", .{ left_unit.unitName, right_unit.unitName });
                try output.print("\t`{?s}` ..> `{?s}`\n", .{ left_unit.unitName, right_unit.unitName });
            }
        }
    }
}
