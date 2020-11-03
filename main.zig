const std = @import("std");
const afd = @import("afd.zig");
const poll = @import("poll.zig");
const windows = @import("windows.zig");
const ws2_32 = @import("ws2_32.zig");

const net = std.net;

usingnamespace poll;

pub fn connect(handle: *Handle, addr: *const ws2_32.sockaddr, addr_len: ws2_32.socklen_t) callconv(.Async) !void {
    windows.connect(@ptrCast(ws2_32.SOCKET, handle.unwrap()), addr, addr_len) catch |err| switch (err) {
        error.WouldBlock => {},
        else => return err,
    };

    handle.waitUntilWritable();

    try windows.getsockoptError(@ptrCast(ws2_32.SOCKET, handle.unwrap()));
}

pub fn read(handle: *Handle, buf: []u8) callconv(.Async) !usize {
    var overlapped: windows.OVERLAPPED = .{
        .Internal = 0,
        .InternalHigh = 0,
        .Offset = 0,
        .OffsetHigh = 0,
        .hEvent = null,
    };

    while (true) {
        windows.ReadFile_(handle.unwrap(), buf, &overlapped) catch |err| switch (err) {
            error.WouldBlock => {
                try windows.CancelIoEx(handle.unwrap(), &overlapped);

                if (windows.GetOverlappedResult_(handle.unwrap(), &overlapped, true)) |_| {
                    break;
                } else |cancel_err| {
                    if (cancel_err != error.OperationAborted) {
                        return cancel_err;
                    }
                }

                handle.waitUntilReadable();
                continue;
            },
            else => return err,
        };

        break;
    }

    return overlapped.InternalHigh;
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
    );
    defer handle.deinit();

    try poller.register(&handle);

    try connect(&handle, &addr.any, addr.getOsSockLen());

    std.debug.print("Connected to {}!\n", .{addr});

    var buf: [1024]u8 = undefined;

    std.debug.print("Got: {}", .{buf[0..try read(&handle, buf[0..])]});
    std.debug.print("Got: {}", .{buf[0..try read(&handle, buf[0..])]});
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

    nosuspend await frame catch |err| switch (err) {
        error.EndOfFile => {},
        else => return err,
    };
}
