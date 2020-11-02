const std = @import("std");
const afd = @import("afd.zig");
const iocp = @import("iocp.zig");

const math = std.math;
const testing = std.testing;

const os = std.os;
const windows = os.windows;
const ws2_32 = windows.ws2_32;

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

    pub fn poll(self: *const Self) !void {
        var events: [1024]iocp.OVERLAPPED_ENTRY = undefined;

        const num_events = try iocp.GetQueuedCompletionStatusEx(self.port, &events, null, true);

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
