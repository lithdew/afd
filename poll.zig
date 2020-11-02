const std = @import("std");
const afd = @import("afd.zig");
const windows = @import("windows.zig");
const ws2_32 = windows.ws2_32;

const math = std.math;
const testing = std.testing;

pub const Handle = struct {
    inner: windows.HANDLE,
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

        return Self{ .port = port, .driver = driver };
    }

    pub fn deinit(self: *const Self) void {
        self.driver.deinit();
        windows.CloseHandle(self.port);
    }

    pub fn register(self: *const Self, handle: *const Handle, events: windows.ULONG) !void {
        try self.driver.poll(try windows.findUnderlyingSocket(@ptrCast(ws2_32.SOCKET, handle.inner)), events, {});
    }

    pub fn poll(self: *const Self) !void {
        var events: [1024]iocp.OVERLAPPED_ENTRY = undefined;

        const num_events = try windows.GetQueuedCompletionStatusEx(self.port, &events, null, true);

        for (events[0..num_events]) |event| {
            std.debug.print("IOCP Notification {}\n", .{event});
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
