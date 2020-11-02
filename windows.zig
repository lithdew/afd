const std = @import("std");

pub usingnamespace std.os.windows;

const IOC_VOID = 0x80000000;
const IOC_OUT = 0x40000000;
const IOC_IN = 0x80000000;
const IOC_WS2 = 0x08000000;

pub const SIO_BSP_HANDLE = IOC_OUT | IOC_WS2 | 27;
pub const SIO_BSP_HANDLE_SELECT = IOC_OUT | IOC_WS2 | 28;
pub const SIO_BSP_HANDLE_POLL = IOC_OUT | IOC_WS2 | 29;

pub const OVERLAPPED_ENTRY = extern struct {
    lpCompletionKey: ULONG_PTR,
    lpOverlapped: LPOVERLAPPED,
    Internal: ULONG_PTR,
    dwNumberOfBytesTransferred: DWORD,
};

pub const GetQueuedCompletionStatusError = error{
    Aborted,
    Cancelled,
    EOF,
    Timeout,
} || os.UnexpectedError;

pub fn GetQueuedCompletionStatusEx(
    completion_port: HANDLE,
    completion_port_entries: []OVERLAPPED_ENTRY,
    timeout_ms: ?DWORD,
    alertable: bool,
) GetQueuedCompletionStatusError!u32 {
    var num_entries_removed: u32 = 0;

    const result = @import("kernel32.zig").GetQueuedCompletionStatusEx(
        completion_port,
        completion_port_entries.ptr,
        @intCast(ULONG, completion_port_entries.len),
        &num_entries_removed,
        timeout_ms orelse INFINITE,
        @boolToInt(alertable),
    );

    if (result == FALSE) {
        return switch (kernel32.GetLastError()) {
            .ABANDONED_WAIT_0 => error.Aborted,
            .OPERATION_ABORTED => error.Cancelled,
            .HANDLE_EOF => error.EOF,
            .IMEOUT => error.Timeout,
            else => |err| unexpectedError(err),
        };
    }

    return num_entries_removed;
}

pub fn getUnderlyingSocket(socket: ws2_32.SOCKET, ioctl_code: DWORD) !ws2_32.SOCKET {
    var raw_socket: ws2_32.SOCKET = undefined;

    const num_bytes = try WSAIoctl(
        socket,
        ioctl_code,
        null,
        @ptrCast([*]u8, &raw_socket)[0..@sizeOf(ws2_32.SOCKET)],
        null,
        null,
    );

    if (num_bytes != @sizeOf(ws2_32.SOCKET)) {
        return error.ShortRead;
    }

    return raw_socket;
}

pub fn findUnderlyingSocket(socket: ws2_32.SOCKET) !ws2_32.SOCKET {
    const err = if (getUnderlyingSocket(socket, ws2_32.SIO_BASE_HANDLE)) |result| return result else |err| err;

    inline for (.{ SIO_BSP_HANDLE_SELECT, SIO_BSP_HANDLE_POLL, SIO_BSP_HANDLE }) |ioctl_code| {
        if (getUnderlyingSocket(socket, ioctl_code)) |result| return result else |_| {}
    }

    return err;
}
