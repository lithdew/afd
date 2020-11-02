const std = @import("std");

const os = std.os;
const windows = os.windows;
const ws2_32 = windows.ws2_32;

const testing = std.testing;

const IOC_VOID = 0x80000000;
const IOC_OUT = 0x40000000;
const IOC_IN = 0x80000000;
const IOC_WS2 = 0x08000000;

pub const SIO_BSP_HANDLE = IOC_OUT | IOC_WS2 | 27;
pub const SIO_BSP_HANDLE_SELECT = IOC_OUT | IOC_WS2 | 28;
pub const SIO_BSP_HANDLE_POLL = IOC_OUT | IOC_WS2 | 29;

pub fn getUnderlyingSocket(socket: ws2_32.SOCKET, ioctl_code: windows.DWORD) !ws2_32.SOCKET {
    var raw_socket: ws2_32.SOCKET = undefined;

    const num_bytes = try windows.WSAIoctl(
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

test "" {
    testing.refAllDecls(@This());
}