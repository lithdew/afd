const std = @import("std");
const afd = @import("afd.zig");
const ws2_32 = @import("ws2_32.zig");
const windows = @import("windows.zig");

const net = std.net;

pub fn work(stopped: *bool) !void {
    defer stopped.* = true;

    const bind_addr = try net.Address.parseIp("0.0.0.0", 0);
    const dest_addr = try net.Address.parseIp("8.8.8.8", 53);

    var handle = try windows.WSASocketW(
        dest_addr.any.family,
        ws2_32.SOCK_STREAM,
        ws2_32.IPPROTO_TCP,
        null,
        0,
        ws2_32.WSA_FLAG_OVERLAPPED,
    );
    defer windows.closesocket(handle) catch {};
    
    const socket = try windows.findUnderlyingSocket(handle);

    try afd.bind(socket, &bind_addr.any, bind_addr.getOsSockLen());
    try afd.connect(handle, &dest_addr.any, dest_addr.getOsSockLen());
}

pub fn main() !void {
    _ = try windows.WSAStartup(2, 2);
    defer windows.WSACleanup() catch {};

    var stopped = false;
    var frame = async work(&stopped);

    while (!stopped) {}

    try nosuspend await frame;
}
