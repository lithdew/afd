const std = @import("std");
const list = @import("list.zig");
const afd = @import("afd.zig");
const windows = @import("windows.zig");
const ws2_32 = windows.ws2_32;

const math = std.math;
const testing = std.testing;

const assert = std.debug.assert;

pub const Handle = struct {
    const List = list.List(anyframe);
    const Self = @This();

    data: afd.Data,
    handle: windows.HANDLE,
    events: windows.ULONG,

    lock: std.Mutex = .{},

    read_ready: bool = false,
    readers: List = .{},

    write_ready: bool = false,
    writers: List = .{},

    pub fn init(handle: windows.HANDLE, events: windows.ULONG) !Self {
        const raw_handle = try windows.findUnderlyingSocket(@ptrCast(ws2_32.SOCKET, handle));

        return Self{
            .data = afd.Data.init(raw_handle, events),
            .handle = raw_handle,
            .events = events,
        };
    }

    pub fn deinit(self: *const Self) void {
        windows.closesocket(@ptrCast(ws2_32.SOCKET, self.unwrap())) catch return;
    }

    pub fn refresh(self: *Self) void {
        const held = self.lock.acquire();
        defer held.release();

        self.data = afd.Data.init(self.handle, self.events);
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

        _ = try windows.CreateIoCompletionPort(driver.handle, port, 0, 0);

        return Self{ .port = port, .driver = driver };
    }

    pub fn deinit(self: *const Self) void {
        self.driver.deinit();
        windows.CloseHandle(self.port);
    }

    pub fn register(self: *const Self, handle: *Handle) !void {
        self.driver.poll(&handle.data) catch |err| switch (err) {
            error.WouldBlock => {},
            else => return err,
        };
    }

    pub fn refresh(self: *const Self, handle: *Handle) !void {
        handle.refresh();

        self.driver.poll(&handle.data) catch |err| switch (err) {
            error.InvalidHandle => handle.release(),
            error.WouldBlock => {},
            else => return err,
        };
    }

    pub fn poll(self: *const Self) !void {
        var events: [1024]windows.OVERLAPPED_ENTRY = undefined;

        const num_events = try windows.GetQueuedCompletionStatusEx(self.port, &events, null, true);

        for (events[0..num_events]) |event| {
            const data = @fieldParentPtr(afd.Data, "request", event.lpOverlapped);
            const handle = @fieldParentPtr(Handle, "data", data);

            std.debug.print("IOCP Notification (Event: {}, State: {})\n", .{ event, data.state.Handles[0] });

            if (handle.markWritable()) |frame| {
                resume frame;
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
