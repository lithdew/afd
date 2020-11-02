const std = @import("std");
const afd = @import("afd.zig");
const poll = @import("poll.zig");
const windows = @import("windows.zig");

const net = std.net;
const ws2_32 = windows.ws2_32;

usingnamespace poll;

pub fn main() !void {
    _ = try windows.WSAStartup(2, 2);
    defer windows.WSACleanup() catch {};

    var poller = try Poller.init("Test");
    defer poller.deinit();

    const addr = try net.Address.parseIp("127.0.0.1", 9000);

    var handle = Handle{
        .inner = try windows.WSASocketW(
            addr.any.family,
            ws2_32.SOCK_STREAM,
            ws2_32.IPPROTO_TCP,
            null,
            0,
            ws2_32.WSA_FLAG_OVERLAPPED,
        ),
        .events = afd.AFD_POLL_ALL,
    };
    defer windows.closesocket(@ptrCast(ws2_32.SOCKET, handle.inner)) catch {};

    try poller.register(&handle);

    try windows.connect(@ptrCast(ws2_32.SOCKET, handle.inner), &addr.any, addr.getOsSockLen());

    while (true) {
        try poller.poll();
    }
}
