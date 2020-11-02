const std = @import("std");
const afd = @import("afd.zig");
const poll = @import("poll.zig");
const windows = @import("windows.zig");

const net = std.net;
const ws2_32 = windows.ws2_32;

usingnamespace poll;

pub fn connect(sock: ws2_32.SOCKET, sock_addr: *const ws2_32.sockaddr, len: ws2_32.socklen_t) !void {
    const rc = ws2_32.connect(sock, sock_addr, @intCast(i32, len));
    if (rc == 0) return;
    switch (ws2_32.WSAGetLastError()) {
        .WSAEADDRINUSE => return error.AddressInUse,
        .WSAEADDRNOTAVAIL => return error.AddressNotAvailable,
        .WSAECONNREFUSED => return error.ConnectionRefused,
        .WSAETIMEDOUT => return error.ConnectionTimedOut,
        .WSAEHOSTUNREACH, .WSAENETUNREACH => return error.NetworkUnreachable,
        .WSAEFAULT => unreachable,
        .WSAEINVAL => unreachable,
        .WSAEISCONN => unreachable,
        .WSAENOTSOCK => unreachable,
        .WSAEINPROGRESS, .WSAEWOULDBLOCK => return error.WouldBlock,
        .WSAEACCES => unreachable,
        .WSAENOBUFS => return error.SystemResources,
        .WSAEAFNOSUPPORT => return error.AddressFamilyNotSupported,
        else => |err| return windows.unexpectedWSAError(err),
    }
    return;
}

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

    try connect(@ptrCast(ws2_32.SOCKET, handle.inner), &addr.any, addr.getOsSockLen());

    while (true) {
        try poller.poll();
    }
}
