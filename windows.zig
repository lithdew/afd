const std = @import("std");

const math = std.math;

const os = std.os;
const windows = os.windows;

pub usingnamespace windows;

const IOC_VOID = 0x80000000;
const IOC_OUT = 0x40000000;
const IOC_IN = 0x80000000;
const IOC_WS2 = 0x08000000;

pub const SIO_BSP_HANDLE = IOC_OUT | IOC_WS2 | 27;
pub const SIO_BSP_HANDLE_SELECT = IOC_OUT | IOC_WS2 | 28;
pub const SIO_BSP_HANDLE_POLL = IOC_OUT | IOC_WS2 | 29;

pub const SIO_GET_EXTENSION_FUNCTION_POINTER = IOC_OUT | IOC_IN | IOC_WS2 | 6;

pub const FILE_SKIP_COMPLETION_PORT_ON_SUCCESS: windows.UCHAR = 0x1;
pub const FILE_SKIP_SET_EVENT_ON_HANDLE: windows.UCHAR = 0x2;

pub const WSAID_CONNECTEX = GUID{
    .Data1 = 0x25a207b9,
    .Data2 = 0xddf3,
    .Data3 = 0x4660,
    .Data4 = [8]u8{ 0x8e, 0xe9, 0x76, 0xe5, 0x8c, 0x74, 0x06, 0x3e },
};

pub fn loadExtensionFunction(comptime T: type, sock: ws2_32.SOCKET, guid: GUID) !T {
    var func: T = undefined;
    var num_bytes: DWORD = undefined;

    const rc = ws2_32.WSAIoctl(sock, SIO_GET_EXTENSION_FUNCTION_POINTER, @ptrCast(*const c_void, &guid), @sizeOf(GUID), &func, @sizeOf(T), &num_bytes, null, null);
    if (rc != 0) {
        return unexpectedWSAError(ws2_32.WSAGetLastError());
    }

    return func;
}

pub const OVERLAPPED_ENTRY = extern struct {
    lpCompletionKey: ULONG_PTR,
    lpOverlapped: LPOVERLAPPED,
    Internal: ULONG_PTR,
    dwNumberOfBytesTransferred: DWORD,
};

pub fn SetFileCompletionNotificationModes(handle: HANDLE, flags: UCHAR) !void {
    const success = @import("kernel32.zig").SetFileCompletionNotificationModes(handle, flags);

    if (success == FALSE) {
        return unexpectedError(kernel32.GetLastError());
    }
}

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

pub fn ConnectEx(sock: ws2_32.SOCKET, sock_addr: *const ws2_32.sockaddr, sock_len: ws2_32.socklen_t, overlapped: *OVERLAPPED) !void {
    const func = try loadExtensionFunction(@import("ws2_32.zig").LPFN_CONNECTEX, sock, WSAID_CONNECTEX);

    const success = func(sock, sock_addr, @intCast(c_int, sock_len), null, 0, null, overlapped);
    if (success == windows.FALSE) {
        return switch (ws2_32.WSAGetLastError()) {
            .WSAEADDRINUSE => error.AddressInUse,
            .WSAEADDRNOTAVAIL => error.AddressNotAvailable,
            .WSAECONNREFUSED => error.ConnectionRefused,
            .WSAETIMEDOUT => error.ConnectionTimedOut,
            .WSAEFAULT => error.BadAddress,
            .WSAEINVAL => error.NotYetBound,
            .WSAEISCONN => error.AlreadyConnected,
            .WSAENOTSOCK => error.NotASocket,
            .WSAEACCES => error.BroadcastNotEnabled,
            .WSAENOBUFS => error.SystemResources,
            .WSAEAFNOSUPPORT => error.AddressFamilyNotSupported,
            .WSA_IO_PENDING, .WSAEINPROGRESS, .WSAEWOULDBLOCK => error.WouldBlock,
            .WSAEHOSTUNREACH, .WSAENETUNREACH => error.NetworkUnreachable,
            else => |err| unexpectedWSAError(err),
        };
    }
}

pub fn bind_(sock: ws2_32.SOCKET, sock_addr: *const ws2_32.sockaddr, sock_len: ws2_32.socklen_t) !void {
    const rc = ws2_32.bind(sock, sock_addr, @intCast(c_int, sock_len));
    if (rc == ws2_32.SOCKET_ERROR) {
        return switch (ws2_32.WSAGetLastError()) {
            .WSAENETDOWN => error.NetworkSubsystemFailed,
            .WSAEACCES => error.AccessDenied,
            .WSAEADDRINUSE => error.AddressInUse,
            .WSAEADDRNOTAVAIL => error.AddressNotAvailable,
            .WSAEFAULT => error.BadAddress,
            .WSAEINPROGRESS => error.WouldBlock,
            .WSAEINVAL => error.AlreadyBound,
            .WSAENOBUFS => error.NoEphemeralPortsAvailable,
            .WSAENOTSOCK => error.NotASocket,
            else => |err| unexpectedWSAError(err),
        };
    }
}

pub fn connect(sock: ws2_32.SOCKET, sock_addr: *const ws2_32.sockaddr, len: ws2_32.socklen_t) !void {
    const rc = ws2_32.connect(sock, sock_addr, @intCast(i32, len));
    if (rc == ws2_32.SOCKET_ERROR) {
        return switch (ws2_32.WSAGetLastError()) {
            .WSAEADDRINUSE => error.AddressInUse,
            .WSAEADDRNOTAVAIL => error.AddressNotAvailable,
            .WSAECONNREFUSED => error.ConnectionRefused,
            .WSAETIMEDOUT => error.ConnectionTimedOut,
            .WSAEFAULT => error.BadAddress,
            .WSAEINVAL => error.ListeningSocket,
            .WSAEISCONN => error.AlreadyConnected,
            .WSAENOTSOCK => error.NotASocket,
            .WSAEACCES => error.BroadcastNotEnabled,
            .WSAENOBUFS => error.SystemResources,
            .WSAEAFNOSUPPORT => error.AddressFamilyNotSupported,
            .WSAEINPROGRESS, .WSAEWOULDBLOCK => error.WouldBlock,
            .WSAEHOSTUNREACH, .WSAENETUNREACH => error.NetworkUnreachable,
            else => |err| unexpectedWSAError(err),
        };
    }
}

pub fn recv(sock: ws2_32.SOCKET, buf: []u8) !usize {
    const rc = @import("ws2_32.zig").recv(sock, buf.ptr, @intCast(c_int, buf.len), 0);
    if (rc == ws2_32.SOCKET_ERROR) {
        return switch (ws2_32.WSAGetLastError()) {
            .WSANOTINITIALISED => error.WinsockNotInitialized,
            .WSAENETDOWN => error.NetworkSubsystemFailed,
            .WSAEFAULT => error.BadBuffer,
            .WSAENOTCONN => error.SocketNotConnected,
            .WSAEINTR => error.Cancelled,
            .WSAEINPROGRESS, .WSAEWOULDBLOCK => error.WouldBlock,
            .WSAENETRESET => error.ConnectionResetted,
            .WSAENOTSOCK => error.NotASocket,
            .WSAEOPNOTSUPP => error.FlagNotSupported,
            .WSAESHUTDOWN => error.EndOfFile,
            .WSAEMSGSIZE => error.MessageTooLarge,
            .WSAEINVAL => error.SocketNotBound,
            .WSAECONNABORTED => error.ConnectionAborted,
            .WSAETIMEDOUT => error.Timeout,
            .WSAECONNRESET => error.Refused,
            else => |err| unexpectedWSAError(err),
        };
    }

    return @intCast(usize, rc);
}

pub fn getsockoptError(fd: ws2_32.SOCKET) !void {
    var errno: usize = undefined;
    var errno_size: ws2_32.socklen_t = @sizeOf(@TypeOf(errno));

    const result = @import("ws2_32.zig").getsockopt(fd, ws2_32.SOL_SOCKET, ws2_32.SO_ERROR, @ptrCast([*c]u8, &errno), &errno_size);
    if (result == ws2_32.SOCKET_ERROR) {
        switch (ws2_32.WSAGetLastError()) {
            .WSAEFAULT => unreachable,
            .WSAENOPROTOOPT => unreachable,
            .WSAENOTSOCK => unreachable,
            else => |err| return windows.unexpectedWSAError(err),
        }
    }

    if (errno != 0) {
        return switch (@intToEnum(ws2_32.WinsockError, @truncate(u16, errno))) {
            .WSAEACCES => error.PermissionDenied,
            .WSAEADDRINUSE => error.AddressInUse,
            .WSAEADDRNOTAVAIL => error.AddressNotAvailable,
            .WSAEAFNOSUPPORT => error.AddressFamilyNotSupported,
            .WSAEALREADY => unreachable, // The socket is nonblocking and a previous connection attempt has not yet been completed.
            .WSAEBADF => unreachable, // sockfd is not a valid open file descriptor.
            .WSAECONNREFUSED => error.ConnectionRefused,
            .WSAEFAULT => unreachable, // The socket structure address is outside the user's address space.
            .WSAEISCONN => unreachable, // The socket is already connected.
            .WSAENETUNREACH => error.NetworkUnreachable,
            .WSAENOTSOCK => unreachable, // The file descriptor sockfd does not refer to a socket.
            .WSAEPROTOTYPE => unreachable, // The socket type does not support the requested communications protocol.
            .WSAETIMEDOUT => error.ConnectionTimedOut,
            else => |err| windows.unexpectedWSAError(err),
        };
    }
}

pub const SetSockOptError = error{
    /// The socket is already connected, and a specified option cannot be set while the socket is connected.
    AlreadyConnected,

    /// The option is not supported by the protocol.
    InvalidProtocolOption,

    /// The send and receive timeout values are too big to fit into the timeout fields in the socket structure.
    TimeoutTooBig,

    /// Insufficient resources are available in the system to complete the call.
    SystemResources,

    NetworkSubsystemFailed,
    FileDescriptorNotASocket,
    SocketNotBound,
} || std.os.UnexpectedError;

pub fn setsockopt(sock: ws2_32.SOCKET, level: u32, opt: u32, val: ?[]u8) SetSockOptError!void {
    const rc = ws2_32.setsockopt(sock, level, opt, if (val) |v| v.ptr else null, if (val) |v| @intCast(ws2_32.socklen_t, v.len) else 0);
    if (rc == ws2_32.SOCKET_ERROR) {
        switch (ws2_32.WSAGetLastError()) {
            .WSANOTINITIALISED => unreachable,
            .WSAENETDOWN => return error.NetworkSubsystemFailed,
            .WSAEFAULT => unreachable,
            .WSAENOTSOCK => return error.FileDescriptorNotASocket,
            .WSAEINVAL => return error.SocketNotBound,
            else => |err| return unexpectedWSAError(err),
        }
    }
}

pub fn ReadFile_(handle: HANDLE, buf: []u8, overlapped: *OVERLAPPED) !void {
    const len = math.cast(DWORD, buf.len) catch math.maxInt(DWORD);

    const success = kernel32.ReadFile(handle, buf.ptr, len, null, overlapped);
    if (success == FALSE) {
        return switch (kernel32.GetLastError()) {
            .IO_PENDING => error.WouldBlock,
            .OPERATION_ABORTED => error.OperationAborted,
            .BROKEN_PIPE => error.BrokenPipe,
            .HANDLE_EOF, .NETNAME_DELETED => error.EndOfFile,
            else => |err| unexpectedError(err),
        };
    }
}

pub fn WriteFile_(handle: HANDLE, buf: []const u8, overlapped: *OVERLAPPED) !void {
    const len = math.cast(DWORD, buf.len) catch math.maxInt(DWORD);

    const success = kernel32.WriteFile(handle, buf.ptr, len, null, overlapped);
    if (success == FALSE) {
        return switch (kernel32.GetLastError()) {
            .IO_PENDING => error.WouldBlock,
            .OPERATION_ABORTED => error.OperationAborted,
            .BROKEN_PIPE => error.BrokenPipe,
            .HANDLE_EOF, .NETNAME_DELETED => error.EndOfFile,
            else => |err| unexpectedError(err),
        };
    }
}

pub fn CancelIoEx(handle: HANDLE, overlapped: *OVERLAPPED) !void {
    const rc = kernel32.CancelIoEx(handle, overlapped);
    if (rc == 0) {
        return switch (kernel32.GetLastError()) {
            .NOT_FOUND => error.RequestNotFound,
            else => |err| unexpectedError(err),
        };
    }
}

pub fn GetOverlappedResult_(h: HANDLE, overlapped: *OVERLAPPED, wait: bool) !DWORD {
    var bytes: DWORD = undefined;
    if (kernel32.GetOverlappedResult(h, overlapped, &bytes, @boolToInt(wait)) == 0) {
        return switch (kernel32.GetLastError()) {
            .IO_INCOMPLETE => if (!wait) error.WouldBlock else unreachable,
            .OPERATION_ABORTED => error.OperationAborted,
            else => |err| unexpectedError(err),
        };
    }
    return bytes;
}
