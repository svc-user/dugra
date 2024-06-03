const std = @import("std");

const NetJson = @import("outputters/NetJson.zig");

const FileParser = @import("FileParser.zig");
const Node = FileParser.Node;
const ModuleMapList = FileParser.ModuleMapList;

modules: ModuleMapList,
allocator: std.mem.Allocator,
web_files: []const u8,

listen_addr: std.net.Address = undefined,
threads: usize = 0,

const Self = @This();
pub fn init(allocator: std.mem.Allocator, moduleMap: ModuleMapList, web_files: []const u8) Self {
    return .{
        .modules = moduleMap,
        .allocator = allocator,
        .web_files = web_files,
    };
}

pub fn serve(self: *Self, address: []const u8, port: u16) !void {
    self.listen_addr = try std.net.Address.parseIp(address, port);

    std.debug.print("listening on http://{s}:{d}\n", .{ address, port });

    while (true) {
        while (self.threads >= 8) {
            std.atomic.spinLoopHint();
        }

        self.threads += 1;
        var thread = try std.Thread.spawn(.{}, handleConnection, .{self});
        thread.detach();
    }
}

fn handleConnection(self: *Self) !void {
    const tid = std.Thread.getCurrentId();
    defer {
        self.threads -= 1;
        std.debug.print("[{d: >8}] Handler done\n", .{tid});
    }

    const read_buffer = try self.allocator.alloc(u8, 16000);
    defer self.allocator.free(read_buffer);

    std.debug.print("[{d: >8}] Handler waiting\n", .{tid});

    var tcp_srv = try self.listen_addr.listen(.{
        .reuse_address = true,
    });
    defer tcp_srv.deinit();
    const tcp_conn = try tcp_srv.accept();
    defer tcp_conn.stream.close();
    // std.debug.print("[{d: >8}] incoming connection...\n", .{tid});

    var server = std.http.Server.init(tcp_conn, read_buffer);
    var request = server.receiveHead() catch return;

    std.debug.print("[{d: >8}] Accepted connection: {s} {s}\n", .{ tid, @tagName(request.head.method), request.head.target });

    const full_target = try std.mem.concat(self.allocator, u8, &[_][]const u8{ "http://0.0.0.0", request.head.target });
    defer self.allocator.free(full_target);

    const uri = try std.Uri.parse(full_target);
    // Special case
    if (std.mem.eql(u8, uri.path.percent_encoded, "/")) {
        self.handleStatic(&request, "/html/index.html") catch handleHandlerError();
    }
    // Virtual file
    else if (std.mem.eql(u8, uri.path.percent_encoded, "/data.json")) {
        self.handleData(&request, self.modules) catch handleHandlerError();
    }
    // check the file system
    // If no file is found `handleNotFound()` is returned
    else {
        self.handleStatic(&request, uri.path.percent_encoded) catch handleHandlerError();
    }

    std.debug.print("[{d: >8}] Handler successfully executed\n", .{tid});
}

inline fn handleHandlerError() void {
    std.debug.print("[{d: >8}] Error handling request!\n", .{std.Thread.getCurrentId()});
    return;
}

fn handleStatic(self: *Self, req: *std.http.Server.Request, path: []const u8) !void {
    const tid = std.Thread.getCurrentId();

    const sub_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.web_files, path });
    defer self.allocator.free(sub_path);

    const cwd_path = try std.fs.cwd().realpathAlloc(self.allocator, "");
    defer self.allocator.free(cwd_path);

    std.debug.print("[{d: >8}] CWD: '{s}'. Serving file '{s}'\n", .{ tid, cwd_path, sub_path });

    const fd = std.fs.cwd().openFile(sub_path, .{}) catch return self.handleNotFound(req);
    defer fd.close();

    const send_buffer = try self.allocator.alloc(u8, 16000);
    defer self.allocator.free(send_buffer);

    const file_cont = fd.readToEndAlloc(self.allocator, std.math.maxInt(u32)) catch return self.handleNotFound(req);
    defer self.allocator.free(file_cont);

    const file_ext = std.fs.path.extension(path);
    var resp = req.respondStreaming(.{
        .send_buffer = send_buffer,
        .respond_options = .{ .extra_headers = &[_]std.http.Header{
            .{ .name = "X-Handler", .value = "Static" },
            .{ .name = "Content-Type", .value = getMimeType(file_ext) },
        } },
    });

    try resp.writeAll(file_cont);
    try resp.end();
}

fn handleData(self: *Self, req: *std.http.Server.Request, moduleMap: ModuleMapList) !void {
    const send_buffer = try self.allocator.alloc(u8, 16000);
    defer self.allocator.free(send_buffer);

    var resp = req.respondStreaming(.{
        .send_buffer = send_buffer,
        .respond_options = .{ .extra_headers = &[_]std.http.Header{
            .{ .name = "X-Handler", .value = "Data" },
            .{ .name = "Content-Type", .value = "application/json" },
        } },
    });
    try NetJson.write(resp.writer(), moduleMap);
    try resp.end();
}

fn handleNotFound(_: *Self, req: *std.http.Server.Request) !void {
    try req.respond("", .{ .status = .not_found, .extra_headers = &[_]std.http.Header{
        .{ .name = "X-Handler", .value = "NotFound" },
    } });
}

fn getMimeType(ext: []const u8) []const u8 {
    if (ext.len < 2) return "application/octet-stream";

    var ext_buff: [16]u8 = undefined;
    const ext_lower = std.ascii.lowerString(&ext_buff, ext[1..]);

    const ext_e = std.meta.stringToEnum(Extension, ext_lower);
    if (ext_e == null) return "application/octet-stream";

    return switch (ext_e.?) {
        .js, .json => "text/javascript",
        .jpeg, .jpg => "image/jpeg",
        .png => "image/png",
        .svg => "image/svg+xml",
        .css => "text/css",
        .html => "text/html",
        .ico => "image/x-icon",
        .gif => "image/gif",
        .pdf => "application/pdf",
        .xml => "application/xml",
        .mp4 => "video/mp4",
        .mp3 => "audio/mpeg",
        .txt => "text/plain",
        .doc, .docx => "application/msword",
        .xls, .xlsx => "application/vnd.ms-excel",
        .ppt, .pptx => "application/vnd.ms-powerpoint",
        .zip => "application/zip",
        .rar => "application/x-rar-compressed",
        .tar => "application/x-tar",
    };
}

const Extension = enum {
    // Image types
    jpeg,
    jpg,
    png,
    svg,
    gif,

    // Text types
    css,
    html,
    js,
    json,
    xml,
    txt,

    // Multimedia types
    mp4,
    mp3,

    // Document types
    pdf,
    doc,
    docx,
    xls,
    xlsx,
    ppt,
    pptx,

    // Archive types
    zip,
    rar,

    // Other types
    ico,
    tar,
};
