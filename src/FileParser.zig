const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");

pub const ModuleMapList = std.StringHashMap(*Node); // Maps module names to their instances
pub const LinkList = std.ArrayList(Link);

/// Node represents a unit, which itself can contain other units.
pub const Node = struct {
    id: usize,
    unitName: ?[]const u8,
    fileName: ?[]const u8,
    section: Section,
    unitType: UnitType,
    parsed: bool = false,
    uses: std.ArrayList(*Node),
};

const Link = struct {
    source: usize,
    target: usize,
    cost: f32,
};

const UnitType = enum(u2) {
    program,
    library,
    unit,
};

const Section = enum(u2) {
    interface,
    implementation,
};

const State = enum(u2) {
    start,
    name,
    uses,
};

var _nodeIdCounter: usize = 1;
pub fn parse_file(allocator: std.mem.Allocator, project_root: []const u8, root_node: *Node, moduleMap: *ModuleMapList) !void {
    if (root_node.fileName == null) {
        return;
    }

    if (root_node.parsed) {
        //std.debug.print("already parsed {?s} in '{?s}'. skipping..\n", .{ root_node.unitName, root_node.fileName });
        return;
    }

    const project_file_path = try std.fs.path.join(allocator, &[_][]const u8{ project_root, std.fs.path.sep_str, root_node.fileName.? });
    defer allocator.free(project_file_path);

    // std.debug.print("{s}\n", .{project_file_path});

    const proj_file_hndl = try std.fs.openFileAbsolute(project_file_path, .{});

    const md = try proj_file_hndl.metadata();
    const file_buff = try allocator.allocSentinel(u8, md.size(), 0);
    defer allocator.free(file_buff);

    _ = try proj_file_hndl.readAll(file_buff);

    var state: State = .start;
    var tokenizer = Tokenizer.tokenize(file_buff);
    while (true) {
        var token = tokenizer.next();
        switch (state) {
            .name => { // kw_ident (sym_dot kw_ident)* -> until sym_semicolon
                var idx: usize = 0;
                var name_buff: [255]u8 = undefined;
                while (token.tag != .sym_semicolon) {
                    std.mem.copyForwards(u8, name_buff[idx..], file_buff[token.loc.start..token.loc.end]);
                    idx += token.loc.end - token.loc.start;

                    token = tokenizer.next();
                }

                if (root_node.unitName) |un| {
                    allocator.free(un); // use unit name from within unit. Free old name and assign new.
                }
                root_node.unitName = try allocator.dupe(u8, name_buff[0..idx]);
                state = .start;
            },
            .uses => { // kw_ident(sym_dot kw_ident)* (kw_in string_lit)? sym_comma? -> until sym_semicolon
                var idx: usize = 0;
                var fidx: usize = 0;
                var name_buff: [255]u8 = undefined;
                var file_name_buff: [255]u8 = undefined;

                while (true) {
                    switch (token.tag) {
                        .identifier, .sym_dot => {
                            std.mem.copyForwards(u8, name_buff[idx..], file_buff[token.loc.start..token.loc.end]);
                            idx += token.loc.end - token.loc.start;
                        },
                        .keyword_in => {
                            token = tokenizer.next();
                            if (token.tag != .string) {
                                unreachable;
                            }

                            std.mem.copyForwards(u8, &file_name_buff, file_buff[token.loc.start + 1 .. token.loc.end - 1]);
                            fidx += token.loc.end - token.loc.start - 2;
                        },
                        .sym_comma, .sym_semicolon => {
                            var lower_buff: [255]u8 = undefined;
                            const lower_unit_name = try allocator.dupe(u8, std.ascii.lowerString(&lower_buff, name_buff[0..idx]));

                            const child = gnc: {
                                if (moduleMap.get(lower_unit_name)) |unit| {
                                    allocator.free(lower_unit_name);

                                    if (fidx > 0) {
                                        if (unit.fileName) |ufn| {
                                            allocator.free(ufn); // use unit file name from within unit. Free old file name and assign new.
                                        }
                                        unit.fileName = try allocator.dupe(u8, file_name_buff[0..fidx]);
                                    }

                                    if (unit.unitName) |un| {
                                        allocator.free(un); // use unit name from within unit. Free old name and assign new.
                                    }
                                    unit.unitName = try allocator.dupe(u8, name_buff[0..idx]);
                                    unit.parsed = true;
                                    break :gnc unit;
                                } else {
                                    const new_child = try allocator.create(Node);
                                    new_child.* = .{
                                        .id = _nodeIdCounter,
                                        .fileName = if (fidx > 0)
                                            try allocator.dupe(u8, file_name_buff[0..fidx])
                                        else
                                            null,
                                        .section = root_node.section,
                                        .unitName = try allocator.dupe(u8, name_buff[0..idx]),
                                        .unitType = .unit,
                                        .uses = std.ArrayList(*Node).init(allocator),
                                    };
                                    _nodeIdCounter += 1;

                                    try moduleMap.put(lower_unit_name, new_child);

                                    break :gnc new_child;
                                }
                            };

                            idx = 0;
                            fidx = 0;
                            try root_node.uses.append(child);

                            if (token.tag == .sym_semicolon) {
                                break;
                            }
                        },
                        .block_comment, .line_comment, .compiler_directive => {}, // allowed "other stuff"
                        else => {
                            unreachable;
                        },
                    }

                    token = tokenizer.next();
                }

                state = .start;
            },
            else => {},
        }

        switch (token.tag) {
            .keyword_library => {
                state = .name;
                root_node.unitType = .library;
            },
            .keyword_unit => {
                state = .name;
                root_node.unitType = .unit;
            },
            .keyword_program => {
                state = .name;
                root_node.unitType = .program;
            },
            .keyword_uses => {
                state = .uses;
            },
            .keyword_interface => {
                root_node.section = .interface;
            },
            .keyword_implementation => {
                root_node.section = .implementation;
            },
            else => {},
        }

        if (token.tag == .invalid) {
            std.debug.print("{s}\\{?s}\n", .{ project_root, root_node.fileName });
            @panic("tokenizer failed.");
        }

        if (token.tag == .eof) {
            break;
        }
    }

    for (root_node.uses.items) |unit| {
        //std.debug.print("parsing {?s} in '{?s}' that's a child of {?s} in '{?s}'\n", .{ unit.unitName, unit.fileName, root_node.unitName, root_node.fileName });
        try parse_file(allocator, project_root, unit, moduleMap);
    }
}
