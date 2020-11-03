const std = @import("std");
const windows = @import("windows.zig");
const kernel32 = @import("kernel32.zig");

const math = std.math;
const unicode = std.unicode;
const builtin = std.builtin;
const testing = std.testing;

const os = std.os;
const ws2_32 = windows.ws2_32;

const assert = std.debug.assert;

pub const AFD_NO_FAST_IO = 0x00000001;
pub const AFD_OVERLAPPED = 0x00000002;
pub const AFD_IMMEDIATE = 0x00000004;

pub const AFD_POLL_RECEIVE_BIT = 0;
pub const AFD_POLL_RECEIVE = 1 << AFD_POLL_RECEIVE_BIT;
pub const AFD_POLL_RECEIVE_EXPEDITED_BIT = 1;
pub const AFD_POLL_RECEIVE_EXPEDITED = 1 << AFD_POLL_RECEIVE_EXPEDITED_BIT;
pub const AFD_POLL_SEND_BIT = 2;
pub const AFD_POLL_SEND = 1 << AFD_POLL_SEND_BIT;
pub const AFD_POLL_DISCONNECT_BIT = 3;
pub const AFD_POLL_DISCONNECT = 1 << AFD_POLL_DISCONNECT_BIT;
pub const AFD_POLL_ABORT_BIT = 4;
pub const AFD_POLL_ABORT = 1 << AFD_POLL_ABORT_BIT;
pub const AFD_POLL_LOCAL_CLOSE_BIT = 5;
pub const AFD_POLL_LOCAL_CLOSE = 1 << AFD_POLL_LOCAL_CLOSE_BIT;
pub const AFD_POLL_CONNECT_BIT = 6;
pub const AFD_POLL_CONNECT = 1 << AFD_POLL_CONNECT_BIT;
pub const AFD_POLL_ACCEPT_BIT = 7;
pub const AFD_POLL_ACCEPT = 1 << AFD_POLL_ACCEPT_BIT;
pub const AFD_POLL_CONNECT_FAIL_BIT = 8;
pub const AFD_POLL_CONNECT_FAIL = 1 << AFD_POLL_CONNECT_FAIL_BIT;
pub const AFD_POLL_QOS_BIT = 9;
pub const AFD_POLL_QOS = 1 << AFD_POLL_QOS_BIT;
pub const AFD_POLL_GROUP_QOS_BIT = 10;
pub const AFD_POLL_GROUP_QOS = 1 << AFD_POLL_GROUP_QOS_BIT;

pub const AFD_NUM_POLL_EVENTS = 11;
pub const AFD_POLL_ALL = (1 << AFD_NUM_POLL_EVENTS) - 1;

pub fn AFD_CONTROL_CODE(function: u10, method: windows.TransferType) windows.DWORD {
    return (@as(windows.DWORD, windows.FILE_DEVICE_NETWORK) << 12) |
        (@as(windows.DWORD, function) << 2) |
        @enumToInt(method);
}

pub const AFD_RECEIVE = 5;
pub const AFD_RECEIVE_DATAGRAM = 6;
pub const AFD_POLL = 9;

pub const IOCTL_AFD_RECEIVE = AFD_CONTROL_CODE(AFD_RECEIVE, .METHOD_NEITHER);
pub const IOCTL_AFD_RECEIVE_DATAGRAM = AFD_CONTROL_CODE(AFD_RECEIVE_DATAGRAM, .METHOD_NEITHER);
pub const IOCTL_AFD_POLL = AFD_CONTROL_CODE(AFD_POLL, .METHOD_BUFFERED);

pub const AFD_POLL_HANDLE_INFO = extern struct {
    Handle: windows.HANDLE,
    Events: windows.ULONG,
    Status: windows.NTSTATUS,
};

pub const AFD_POLL_INFO = extern struct {
    Timeout: windows.LARGE_INTEGER,
    NumberOfHandles: windows.ULONG,
    Exclusive: windows.ULONG,
    // followed by an array of `NumberOfHandles` AFD_POLL_HANDLE_INFO
    // Handles[]: AFD_POLL_HANDLE_INFO,
};

pub const AFD_RECV_DATAGRAM_INFO = extern struct {
    BufferArray: *ws2_32.WSABUF,
    BufferCount: windows.ULONG,
    AfdFlags: windows.ULONG,
    TdiFlags: windows.ULONG,
    Address: *ws2_32.sockaddr,
    AddressLength: *usize,
};

pub const AFD_RECV_INFO = extern struct {
    BufferArray: *ws2_32.WSABUF,
    BufferCount: windows.ULONG,
    AfdFlags: windows.ULONG,
    TdiFlags: windows.ULONG,
};

pub const Data = struct {
    const Self = @This();

    state: extern struct {
        Base: AFD_POLL_INFO,
        Handles: [1]AFD_POLL_HANDLE_INFO,
    },
    request: windows.OVERLAPPED,

    pub fn init(handle: windows.HANDLE, events: windows.ULONG) Self {
        return .{
            .state = .{
                .Base = .{
                    .NumberOfHandles = 1,
                    .Timeout = math.maxInt(i64),
                    .Exclusive = windows.FALSE,
                },
                .Handles = .{
                    .{
                        .Handle = handle,
                        .Status = .SUCCESS,
                        .Events = events,
                    },
                },
            },
            .request = .{
                .Internal = 0,
                .InternalHigh = 0,
                .Offset = 0,
                .OffsetHigh = 0,
                .hEvent = null,
            },
        };
    }
};

pub const Driver = packed struct {
    const Self = @This();

    handle: windows.HANDLE,

    pub fn init(comptime name: []const u8) !Self {
        comptime assert(name.len > 0);

        const handle = kernel32.CreateFileW(
            unicode.utf8ToUtf16LeStringLiteral("\\\\.\\GLOBALROOT\\Device\\Afd\\" ++ name)[0..],
            windows.SYNCHRONIZE,
            windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE,
            null,
            windows.OPEN_EXISTING,
            windows.FILE_FLAG_OVERLAPPED,
            null,
        );

        if (handle == windows.INVALID_HANDLE_VALUE) {
            return windows.unexpectedError(kernel32.GetLastError());
        }

        return Self{ .handle = handle };
    }

    pub fn deinit(self: *const Self) void {
        windows.CloseHandle(self.handle);
    }

    pub fn poll(self: *const Self, data: anytype) !void {
        const ptr = @ptrCast(*c_void, &data.state);
        const len = @intCast(windows.DWORD, @sizeOf(@TypeOf(data.state)));

        const success = kernel32.DeviceIoControl(
            self.handle,
            IOCTL_AFD_POLL,
            ptr,
            len,
            ptr,
            len,
            null,
            &data.request,
        );

        if (success == windows.FALSE) {
            switch (kernel32.GetLastError()) {
                .IO_PENDING => return error.WouldBlock,
                .INVALID_HANDLE => return error.InvalidHandle,
                else => |err| return windows.unexpectedError(err),
            }
        }

        switch (@intToEnum(windows.Win32Error, @intCast(u16, data.request.Internal))) {
            .SUCCESS => {},
            .NO_MORE_ITEMS => return error.NoMoreItems,
            else => |err| return windows.unexpectedError(err),
        }
    }
};

test "" {
    testing.refAllDecls(@This());
}

test "Driver.init() / Driver.deinit()" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const driver = try Driver.init("AFD");
    defer driver.deinit();
}
