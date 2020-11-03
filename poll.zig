const std = @import("std");
const afd = @import("afd.zig");
const windows = @import("windows.zig");
const ws2_32 = windows.ws2_32;

const math = std.math;
const testing = std.testing;

pub const Handle = struct {
    const Self = @This();

    events: windows.ULONG,
    data: afd.Data(anyframe),

    pub fn init(handle: windows.HANDLE, events: windows.ULONG) !Self {
        const socket = try windows.findUnderlyingSocket(@ptrCast(ws2_32.SOCKET, handle));

        return Self{
            .events = events,
            .data = afd.Data(anyframe).init(socket, events),
        };
    }

    pub inline fn unwrap(self: *const Self) windows.HANDLE {
        return self.data.state.Handles[0].Handle;
    }
};

// pub fn List(comptime T: type) type {
//     return struct {
//         const Self = @This();

//         next: ?*Self,
//         prev: ?*Self,
//         tail: ?*Self,

//         inline fn isHead(self: *const Self) bool {
//             return self.tail != null;
//         }
//     };
// }

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

    pub fn poll(self: *const Self) !void {
        var events: [1024]windows.OVERLAPPED_ENTRY = undefined;

        const num_events = try windows.GetQueuedCompletionStatusEx(self.port, &events, null, true);

        for (events[0..num_events]) |event| {
            const handle = @fieldParentPtr(Handle, "data", @fieldParentPtr(afd.Data(anyframe), "request", event.lpOverlapped));
            std.debug.print("IOCP Notification (Event: {}, Handle: {}, User Events: {})\n", .{ event, handle.unwrap(), handle.events });
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
