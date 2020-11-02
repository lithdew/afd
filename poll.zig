const std = @import("std");
const afd = @import("afd.zig");

const math = std.math;

const os = std.os;
const windows = os.windows;
const ws2_32 = windows.ws2_32;

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
};

test "Poller.init() / Poller.deinit()" {
    const poller = try Poller.init("Test");
    defer poller.deinit();
}
