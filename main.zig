const std = @import("std");
const afd = @import("afd.zig");
const poll = @import("poll.zig");
const windows = @import("windows.zig");
const ws2_32 = @import("ws2_32.zig");

const net = std.net;

usingnamespace poll;

pub fn connect(handle: *Handle, addr: *const ws2_32.sockaddr, addr_len: ws2_32.socklen_t) callconv(.Async) !void {
    try windows.connect(@ptrCast(ws2_32.SOCKET, handle.unwrap()), addr, addr_len);
    handle.waitUntilWritable();
    try windows.getsockoptError(@ptrCast(ws2_32.SOCKET, handle.unwrap()));
}

pub fn run(poller: *Poller, stopped: *bool) callconv(.Async) !void {
    defer stopped.* = true;

    const addr = try net.Address.parseIp("127.0.0.1", 9000);

    var handle = try Handle.init(
        try windows.WSASocketW(
            addr.any.family,
            ws2_32.SOCK_STREAM,
            ws2_32.IPPROTO_TCP,
            null,
            0,
            ws2_32.WSA_FLAG_OVERLAPPED,
        ),
        afd.AFD_POLL_ALL,
    );
    defer handle.deinit();

    try poller.register(&handle);

    try connect(&handle, &addr.any, addr.getOsSockLen());

    std.debug.print("Connected to {}!\n", .{addr});
}

pub fn main() !void {
    _ = try windows.WSAStartup(2, 2);
    defer windows.WSACleanup() catch {};

    var poller = try Poller.init("Test");
    defer poller.deinit();

    var stopped = false;
    var frame = async run(&poller, &stopped);

    while (!stopped) {
        try poller.poll();
    }

    try nosuspend await frame;
}
