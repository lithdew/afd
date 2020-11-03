const std = @import("std");
const list = @import("list.zig");
const afd = @import("afd.zig");
const windows = @import("windows.zig");
const ws2_32 = windows.ws2_32;

const math = std.math;
const testing = std.testing;

const assert = std.debug.assert;

pub const READ_EVENTS = afd.AFD_POLL_RECEIVE | afd.AFD_POLL_CONNECT_FAIL | afd.AFD_POLL_ACCEPT | afd.AFD_POLL_DISCONNECT | afd.AFD_POLL_ABORT | afd.AFD_POLL_LOCAL_CLOSE;
pub const WRITE_EVENTS = afd.AFD_POLL_SEND | afd.AFD_POLL_CONNECT_FAIL | afd.AFD_POLL_ABORT | afd.AFD_POLL_LOCAL_CLOSE;

pub const Handle = struct {
    const List = list.List(anyframe);
    const Self = @This();

    handle: windows.HANDLE,

    lock: std.Mutex = .{},
    data: afd.Data,

    read_ready: bool = false,
    readers: List = .{},

    write_ready: bool = false,
    writers: List = .{},

    pub fn init(handle: windows.HANDLE) !Self {
        const raw_handle = try windows.findUnderlyingSocket(@ptrCast(ws2_32.SOCKET, handle));

        return Self{
            .handle = raw_handle,
            .data = afd.Data.init(raw_handle, READ_EVENTS | WRITE_EVENTS),
        };
    }

    pub fn deinit(self: *const Self) void {
        windows.closesocket(@ptrCast(ws2_32.SOCKET, self.unwrap())) catch return;
    }

    pub fn refresh(self: *Self) void {
        const held = self.lock.acquire();
        defer held.release();

        self.data = afd.Data.init(self.handle, READ_EVENTS | WRITE_EVENTS);
    }

    pub inline fn unwrap(self: *const Self) windows.HANDLE {
        return self.handle;
    }

    pub fn release(self: *Self) void {
        const held = self.lock.acquire();
        defer held.release();

        self.write_ready = true;
        self.read_ready = true;

        while (self.writers.pop()) |frame| resume frame;
        while (self.readers.pop()) |frame| resume frame;
    }

    pub fn markReadable(self: *Self) ?anyframe {
        const held = self.lock.acquire();
        defer held.release();

        if (self.read_ready) return null;
        if (self.readers.pop()) |frame| return frame;

        self.read_ready = true;
        return null;
    }

    pub fn waitUntilReadable(self: *Self) callconv(.Async) void {
        const held = self.lock.acquire();

        if (self.read_ready) {
            self.read_ready = false;
            held.release();
            return;
        }

        suspend {
            self.readers.append(&List.Node{ .data = @frame() });
            held.release();
        }
    }

    pub fn markWritable(self: *Self) ?anyframe {
        const held = self.lock.acquire();
        defer held.release();

        if (self.write_ready) return null;
        if (self.writers.pop()) |frame| return frame;

        self.write_ready = true;
        return null;
    }

    pub fn waitUntilWritable(self: *Self) callconv(.Async) void {
        const held = self.lock.acquire();

        if (self.write_ready) {
            self.write_ready = false;
            held.release();
            return;
        }

        suspend {
            self.writers.append(&List.Node{ .data = @frame() });
            held.release();
        }
    }
};

pub const Poller = struct {
    const Self = @This();

    port: windows.HANDLE,
    driver: afd.Driver,

    pub fn init(comptime driver_name: []const u8) !Self {
        const port = try windows.CreateIoCompletionPort(
            windows.INVALID_HANDLE_VALUE,
            null,
            undefined,
            math.maxInt(windows.DWORD),
        );
        errdefer windows.CloseHandle(port);

        const driver = try afd.Driver.init(driver_name);
        errdefer driver.deinit();

        try windows.SetFileCompletionNotificationModes(driver.handle, windows.FILE_SKIP_SET_EVENT_ON_HANDLE);

        _ = try windows.CreateIoCompletionPort(driver.handle, port, 0, 0);

        return Self{ .port = port, .driver = driver };
    }

    pub fn deinit(self: *const Self) void {
        self.driver.deinit();
        windows.CloseHandle(self.port);
    }

    pub fn register(self: *const Self, handle: *Handle) !void {
        self.driver.poll(&handle.data) catch |err| switch (err) {
            error.WouldBlock, error.NoMoreItems => {},
            else => return err,
        };
    }

    pub fn refresh(self: *const Self, handle: *Handle) !void {
        _ = windows.kernel32.CancelIoEx(handle.unwrap(), &handle.data.request);

        handle.refresh();

        self.driver.poll(&handle.data) catch |err| switch (err) {
            error.InvalidHandle => handle.release(),
            error.WouldBlock, error.NoMoreItems => {},
            else => return err,
        };
    }

    pub fn poll(self: *const Self) !void {
        var events: [1024]windows.OVERLAPPED_ENTRY = undefined;

        const num_events = try windows.GetQueuedCompletionStatusEx(self.port, &events, null, false);

        for (events[0..num_events]) |event| {
            const data = @fieldParentPtr(afd.Data, "request", event.lpOverlapped);
            const handle = @fieldParentPtr(Handle, "data", data);

            const read_ready = data.state.Handles[0].Events & READ_EVENTS != 0;
            const write_ready = data.state.Handles[0].Events & WRITE_EVENTS != 0;

            std.debug.print("IOCP Notification (read: {}, write: {}, state: {})\n", .{
                read_ready,
                write_ready,
                data.state.Handles[0],
            });

            if (read_ready) {
                if (handle.markReadable()) |frame| resume frame;
            }

            if (write_ready) {
                if (handle.markWritable()) |frame| resume frame;
            }

            try self.refresh(handle);
        }
    }
};

test "" {
    testing.refAllDecls(@This());
}

test "Poller.init() / Poller.deinit()" {
    const poller = try Poller.init("Test");
    defer poller.deinit();
}
