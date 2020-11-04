const std = @import("std");
const windows = @import("windows.zig");
const ws2_32 = @import("ws2_32.zig");

const os = std.os;
const net = std.net;
const math = std.math;

const Handle = struct {
    const Self = @This();

    inner: windows.HANDLE,

    pub fn init(handle: windows.HANDLE) Self {
        return Self{ .inner = handle };
    }

    pub fn deinit(self: *const Self) void {
        windows.closesocket(@ptrCast(ws2_32.SOCKET, self.inner)) catch {};
    }

    pub fn unwrap(self: *const Self) windows.HANDLE {
        return self.inner;
    }
};

const Overlapped = struct {
    const Self = @This();

    inner: windows.OVERLAPPED,
    frame: anyframe,

    pub fn init(frame: anyframe) Self {
        return .{
            .inner = .{
                .Internal = 0,
                .InternalHigh = 0,
                .Offset = 0,
                .OffsetHigh = 0,
                .hEvent = null,
            },
            .frame = frame,
        };
    }
};

const Poller = struct {
    const Self = @This();

    port: windows.HANDLE,

    pub fn init() !Self {
        const port = try windows.CreateIoCompletionPort(
            windows.INVALID_HANDLE_VALUE,
            null,
            undefined,
            math.maxInt(windows.DWORD),
        );
        errdefer windows.CloseHandle(port);

        return Self{ .port = port };
    }

    pub fn deinit(self: *const Self) void {
        windows.CloseHandle(self.port);
    }

    pub fn register(self: *const Self, handle: *const Handle) !void {
        try windows.SetFileCompletionNotificationModes(handle.unwrap(), windows.FILE_SKIP_SET_EVENT_ON_HANDLE | windows.FILE_SKIP_SET_EVENT_ON_HANDLE);
        _ = try windows.CreateIoCompletionPort(handle.unwrap(), self.port, 0, 0);
    }

    pub fn poll(self: *const Self) !void {
        var events: [1024]windows.OVERLAPPED_ENTRY = undefined;

        const num_events = try windows.GetQueuedCompletionStatusEx(self.port, &events, null, false);

        for (events[0..num_events]) |event| {
            std.debug.print("IOCP Notification ({})\n", .{event});

            const overlapped = @fieldParentPtr(Overlapped, "inner", event.lpOverlapped);
            resume overlapped.frame;
        }
    }
};

pub fn bind(handle: *Handle, addr: *const ws2_32.sockaddr, addr_len: ws2_32.socklen_t) !void {
    try windows.bind_(@ptrCast(ws2_32.SOCKET, handle.unwrap()), addr, addr_len);
}

pub fn listen(handle: *Handle, backlog: usize) !void {
    try windows.listen_(@ptrCast(ws2_32.SOCKET, handle.unwrap()), backlog);
}

pub fn connect(handle: *Handle, addr: *const ws2_32.sockaddr, addr_len: ws2_32.socklen_t) callconv(.Async) !void {
    const bind_addr = ws2_32.sockaddr_in{
        .family = ws2_32.AF_INET,
        .port = 0,
        .addr = 0,
    };

    try bind(
        handle,
        @ptrCast(*const ws2_32.sockaddr, &bind_addr),
        @sizeOf(@TypeOf(bind_addr)),
    );

    var overlapped = Overlapped.init(@frame());

    windows.ConnectEx(
        @ptrCast(ws2_32.SOCKET, handle.unwrap()),
        addr,
        addr_len,
        &overlapped.inner,
    ) catch |err| switch (err) {
        error.WouldBlock => {
            suspend;
        },
        else => return err,
    };

    try windows.getsockoptError(@ptrCast(ws2_32.SOCKET, handle.unwrap()));

    try windows.setsockopt(
        @ptrCast(ws2_32.SOCKET, handle.unwrap()),
        ws2_32.SOL_SOCKET,
        ws2_32.SO_UPDATE_CONNECT_CONTEXT,
        null,
    );
}

pub fn accept(handle: *Handle) callconv(.Async) !Handle {
    var accepted = Handle.init(try windows.WSASocketW(
        ws2_32.AF_INET6,
        ws2_32.SOCK_STREAM,
        ws2_32.IPPROTO_TCP,
        null,
        0,
        ws2_32.WSA_FLAG_OVERLAPPED,
    ));
    errdefer accepted.deinit();

    var overlapped = Overlapped.init(@frame());

    windows.AcceptEx(
        @ptrCast(ws2_32.SOCKET, handle.unwrap()),
        @ptrCast(ws2_32.SOCKET, accepted.unwrap()),
        &overlapped.inner,
    ) catch |err| switch (err) {
        error.WouldBlock => {
            suspend;
        },
        else => return err,
    };

    var opt_val: []const u8 = undefined;
    opt_val.ptr = @ptrCast([*]const u8, &handle.unwrap());
    opt_val.len = @sizeOf(ws2_32.SOCKET);

    try windows.setsockopt(
        @ptrCast(ws2_32.SOCKET, accepted.unwrap()),
        ws2_32.SOL_SOCKET,
        ws2_32.SO_UPDATE_ACCEPT_CONTEXT,
        opt_val,
    );

    return accepted;
}

pub fn read(handle: *Handle, buf: []u8) callconv(.Async) !usize {
    var overlapped = Overlapped.init(@frame());

    windows.ReadFile_(handle.unwrap(), buf, &overlapped.inner) catch |err| switch (err) {
        error.WouldBlock => {
            suspend;
        },
        else => return err,
    };

    return overlapped.inner.InternalHigh;
}

pub fn write(handle: *Handle, buf: []const u8) callconv(.Async) !usize {
    var overlapped = Overlapped.init(@frame());

    windows.WriteFile_(handle.unwrap(), buf, &overlapped.inner) catch |err| switch (err) {
        error.WouldBlock => {
            suspend;
        },
        else => return err,
    };

    return overlapped.inner.InternalHigh;
}

pub fn runClient(poller: *Poller, stopped: *bool) callconv(.Async) !void {
    errdefer |err| std.debug.print("Got an error: {}\n", .{@errorName(err)});
    defer stopped.* = true;

    const addr = try net.Address.parseIp("127.0.0.1", 9000);

    var handle = Handle.init(
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

    _ = try write(&handle, "Hello world!");
}

pub fn runServer(poller: *Poller, stopped: *bool) callconv(.Async) !void {
    errdefer |err| std.debug.print("Got an error: {}\n", .{@errorName(err)});
    defer stopped.* = true;

    const addr = try net.Address.parseIp("127.0.0.1", 9000);

    var handle = Handle.init(
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

    try bind(&handle, &addr.any, addr.getOsSockLen());
    try listen(&handle, 128);

    std.debug.print("Listening for peers on: {}\n", .{addr});

    var client = try accept(&handle);
    defer client.deinit();

    try poller.register(&client);

    std.debug.print("A client has connected!\n", .{});

    var buf: [1024]u8 = undefined;

    std.debug.print("Got: {}", .{buf[0..try read(&client, buf[0..])]});
    std.debug.print("Got: {}", .{buf[0..try read(&client, buf[0..])]});
}

pub fn main() !void {
    _ = try windows.WSAStartup(2, 2);
    defer windows.WSACleanup() catch {};

    var poller = try Poller.init();
    defer poller.deinit();

    var stopped = false;
    var frame = async runServer(&poller, &stopped);

    while (!stopped) {
        try poller.poll();
    }

    nosuspend await frame catch |err| switch (err) {
        else => return err,
    };
}
