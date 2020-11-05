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

pub const AFD_SKIP_FIO = 0x00000001;
pub const AFD_OVERLAPPED = 0x00000002;
pub const AFD_IMMEDIATE = 0x00000004;

pub const AFD_EVENT_RECEIVE_BIT = 0;
pub const AFD_EVENT_RECEIVE = 1 << AFD_EVENT_RECEIVE_BIT;
pub const AFD_EVENT_RECEIVE_EXPEDITED_BIT = 1;
pub const AFD_EVENT_RECEIVE_EXPEDITED = 1 << AFD_EVENT_RECEIVE_EXPEDITED_BIT;
pub const AFD_EVENT_SEND_BIT = 2;
pub const AFD_EVENT_SEND = 1 << AFD_EVENT_SEND_BIT;
pub const AFD_EVENT_DISCONNECT_BIT = 3;
pub const AFD_EVENT_DISCONNECT = 1 << AFD_EVENT_DISCONNECT_BIT;
pub const AFD_EVENT_ABORT_BIT = 4;
pub const AFD_EVENT_ABORT = 1 << AFD_EVENT_ABORT_BIT;
pub const AFD_EVENT_LOCAL_CLOSE_BIT = 5;
pub const AFD_EVENT_LOCAL_CLOSE = 1 << AFD_EVENT_LOCAL_CLOSE_BIT;
pub const AFD_EVENT_CONNECT_BIT = 6;
pub const AFD_EVENT_CONNECT = 1 << AFD_EVENT_CONNECT_BIT;
pub const AFD_EVENT_ACCEPT_BIT = 7;
pub const AFD_EVENT_ACCEPT = 1 << AFD_EVENT_ACCEPT_BIT;
pub const AFD_EVENT_CONNECT_FAIL_BIT = 8;
pub const AFD_EVENT_CONNECT_FAIL = 1 << AFD_EVENT_CONNECT_FAIL_BIT;
pub const AFD_EVENT_QOS_BIT = 9;
pub const AFD_EVENT_QOS = 1 << AFD_EVENT_QOS_BIT;
pub const AFD_EVENT_GROUP_QOS_BIT = 10;
pub const AFD_EVENT_GROUP_QOS = 1 << AFD_EVENT_GROUP_QOS_BIT;

pub const AFD_NUM_POLL_EVENTS = 11;
pub const AFD_EVENT_ALL = (1 << AFD_NUM_POLL_EVENTS) - 1;

pub const AFD_SHARE_UNIQUE = 0x00000000;
pub const AFD_SHARE_REUSE = 0x00000001;
pub const AFD_SHARE_WILDCARD = 0x00000002;
pub const AFD_SHARE_EXCLUSIVE = 0x00000003;

pub fn AFD_CONTROL_CODE(function: u10, method: windows.TransferType) windows.DWORD {
    return (@as(windows.DWORD, windows.FILE_DEVICE_NETWORK) << 12) |
        (@as(windows.DWORD, function) << 2) |
        @enumToInt(method);
}

pub const AFD_BIND = 0;
pub const AFD_CONNECT = 1;
pub const AFD_START_LISTEN = 2;
pub const AFD_WAIT_FOR_LISTEN = 3;
pub const AFD_ACCEPT = 4;
pub const AFD_RECV = 5;
pub const AFD_RECV_DATAGRAM = 6;
pub const AFD_SEND = 7;
pub const AFD_SEND_DATAGRAM = 8;
pub const AFD_SELECT = 9;
pub const AFD_DISCONNECT = 10;
pub const AFD_GET_SOCK_NAME = 11;
pub const AFD_GET_PEER_NAME = 12;
pub const AFD_GET_TDI_HANDLES = 13;
pub const AFD_SET_INFO = 14;

pub const IOCTL_AFD_BIND = AFD_CONTROL_CODE(AFD_BIND, .METHOD_NEITHER);
pub const IOCTL_AFD_CONNECT = AFD_CONTROL_CODE(AFD_CONNECT, .METHOD_NEITHER);
pub const IOCTL_AFD_RECV = AFD_CONTROL_CODE(AFD_RECV, .METHOD_NEITHER);
pub const IOCTL_AFD_RECV_DATAGRAM = AFD_CONTROL_CODE(AFD_RECV_DATAGRAM, .METHOD_NEITHER);
pub const IOCTL_AFD_SELECT = AFD_CONTROL_CODE(AFD_SELECT, .METHOD_BUFFERED);

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

pub const AFD_BIND_DATA = extern struct {
    ShareType: windows.ULONG,
    Address: ws2_32.sockaddr,
};

pub const AFD_CONNECT_INFO = extern struct {
    UseSAN: windows.BOOLEAN,
    Root: windows.ULONG,
    Unknown: windows.ULONG,
    RemoteAddress: ws2_32.sockaddr,
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

const Context = struct {
    frame: anyframe,
};

fn handleContextRoutine(user_data: windows.PVOID, io_status_block: *windows.IO_STATUS_BLOCK, d: windows.ULONG) callconv(.C) void {
    const context = @ptrCast(*Context, @alignCast(@alignOf(Context), user_data));
    resume context.frame;
}

pub extern "NtDll" fn NtTestAlert() callconv(.Stdcall) windows.NTSTATUS;

pub fn bind(socket: windows.HANDLE, addr: *const ws2_32.sockaddr, addr_len: ws2_32.socklen_t) !void {
    var bind_data = AFD_BIND_DATA{
        .ShareType = AFD_SHARE_UNIQUE,
        .Address = addr.*,
    };

    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var context = Context{ .frame = @frame() };

    var status = windows.ntdll.NtDeviceIoControlFile(
        socket,
        null,
        handleContextRoutine,
        @ptrCast(*c_void, &context),
        &io_status_block,
        IOCTL_AFD_BIND,
        @ptrCast(*const c_void, &bind_data),
        @sizeOf(@TypeOf(bind_data)),
        @ptrCast(*c_void, &bind_data),
        @sizeOf(@TypeOf(bind_data)),
    );

    if (status == @intToEnum(windows.NTSTATUS, 259)) { // STATUS_PENDING
        suspend {
            assert(NtTestAlert() == .SUCCESS);
        }
        status = io_status_block.u.Status;
    }

    if (status != .SUCCESS) {
        return windows.unexpectedStatus(status);
    }
}

pub fn connect(socket: windows.HANDLE, addr: *const ws2_32.sockaddr, addr_len: ws2_32.socklen_t) !void {
    // var connect_info: extern struct {
    //     UseSAN: windows.BOOLEAN,
    //     Root: windows.ULONG,
    //     Unknown: windows.ULONG,
    //     RemoteAddress: extern struct {
    //         TAAddressCount: windows.LONG,
    //         Address: [1]extern struct {
    //             AddressLength: windows.USHORT,
    //             AddressType: windows.USHORT,
    //             Address: [14]u8,
    //         },
    //     },
    // } = .{
    //     .UseSAN = windows.FALSE,
    //     .Root = 0,
    //     .Unknown = 0,
    //     .RemoteAddress = .{
    //         .TAAddressCount = 1,
    //         .Address = .{
    //             .{
    //                 .AddressLength = 14,
    //                 .AddressType = addr.family,
    //                 .Address = addr.data,
    //             }
    //         }
    //     }
    // };

    // var connect_info = AFD_CONNECT_INFO{
    //     .UseSAN = windows.FALSE,
    //     .Root = 0,
    //     .Unknown = 0,
    //     .RemoteAddress = addr.*,
    // };

    var connect_info = [_]u8{
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x90, 0xe3,
        0x9f, 0x60, 0xd4, 0x00, 0x00, 0x00, 0x02, 0x00, 0x23, 0x28, 0x7f, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    };

    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var context = Context{ .frame = @frame() };

    var status = windows.ntdll.NtDeviceIoControlFile(
        socket,
        null,
        handleContextRoutine,
        @ptrCast(*c_void, &context),
        &io_status_block,
        IOCTL_AFD_CONNECT,
        @ptrCast(*const c_void, &connect_info),
        @sizeOf(@TypeOf(connect_info)),
        null,
        0,
    );

    if (status == @intToEnum(windows.NTSTATUS, 259)) { // STATUS_PENDING
        suspend {
            assert(NtTestAlert() == .SUCCESS);
        }
        status = io_status_block.u.Status;
    }

    if (status != .SUCCESS) {
        return windows.unexpectedStatus(status);
    }
}

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
            IOCTL_AFD_SELECT,
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
