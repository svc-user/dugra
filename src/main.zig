const std = @import("std");
const Argparser = @import("Argparser.zig");
const Tokenizer = @import("Tokenizer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // var fixed_buffer: [8 * 1024000]u8 = undefined;
    // var fba = std.heap.FixedBufferAllocator.init(&fixed_buffer);

    var aa = std.heap.ArenaAllocator.init(gpa.allocator());
    defer aa.deinit();

    // const allocator = fba.allocator();
    const allocator = gpa.allocator();
    // const allocator = aa.allocator();

    const arg_project_file = "project";
    const argparser = Argparser.Parser(
        "Render the 'uses' graph of a delphi project (.dpr-file)",
        &[_]Argparser.Arg{
            .{ .argType = .string, .longName = arg_project_file, .shortName = 'p', .description = "The project file" },
        },
    );

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    var parsedargs = argparser.parse(allocator, argv) catch {
        try argparser.printHelp(std.io.getStdErr());
        std.process.exit(1);
    };
    defer parsedargs.deinit();

    var dispose_project_path: bool = false;
    const project_path: []const u8 = gp: {
        const pp = parsedargs.get(arg_project_file).?.value().string;
        if (std.fs.path.isAbsolute(pp)) {
            break :gp pp;
        } else {
            dispose_project_path = true;
            const abs = try std.fs.cwd().realpathAlloc(allocator, pp);
            break :gp abs;
        }
    };

    defer {
        if (dispose_project_path) {
            allocator.free(project_path);
        }
    }

    const project_directory = std.fs.path.dirname(project_path).?;

    var rootNode = try allocator.create(Node);
    rootNode.* = .{
        .unitName = undefined,
        .fileName = try allocator.dupe(u8, std.fs.path.basename(project_path)),
        .section = .interface,
        .unitType = .program,
        .uses = std.ArrayList(*Node).init(allocator),
    };

    defer rootNode.deinit(allocator, 0);

    try parse_file(allocator, project_directory, rootNode);
}

const ModuleNameMap = std.StringHashMap([]const u8);
const Node = struct {
    unitName: ?[]const u8,
    fileName: ?[]const u8,
    section: Section,
    unitType: UnitType,
    uses: std.ArrayList(*Node),

    pub fn deinit(self: *Node, allocator: std.mem.Allocator, level: usize) void {
        var i: usize = 0;
        while (i < level) : (i += 1) {
            std.debug.print(" ", .{});
        }
        std.debug.print("deinit {?s} in '{?s}' with {d} uses\n", .{ self.unitName, self.fileName, self.uses.items.len });
        if (self.unitName) |un| {
            allocator.free(un);
        }

        if (self.fileName) |fln| {
            allocator.free(fln);
        }

        for (self.uses.items) |cn| {
            cn.deinit(allocator, level + 1);
        }

        self.uses.deinit();
        allocator.destroy(self);
    }
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

fn parse_file(allocator: std.mem.Allocator, project_root: []const u8, root_node: *Node) !void {
    if (root_node.fileName == null) {
        return;
    }

    const project_path = try std.fs.path.join(allocator, &[_][]const u8{ project_root, root_node.fileName.? });
    defer allocator.free(project_path);

    const proj_file_hndl = try std.fs.openFileAbsolute(project_path, .{});

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
                            const child = try allocator.create(Node);
                            child.* = .{
                                .fileName = if (fidx > 0)
                                    try allocator.dupe(u8, file_name_buff[0..fidx])
                                else
                                    null,
                                .section = root_node.section,
                                .unitName = try allocator.dupe(u8, name_buff[0..idx]),
                                .unitType = .unit,
                                .uses = std.ArrayList(*Node).init(allocator),
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
        try parse_file(allocator, project_root, unit);
    }
}

test {
    _ = Tokenizer;
}
