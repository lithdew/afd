const std = @import("std");

const windows = @import("windows.zig");
const ws2_32 = windows.ws2_32;

pub usingnamespace ws2_32;

pub const SO_UPDATE_CONNECT_CONTEXT = 0x7010;

pub extern "ws2_32" fn getsockopt(
    s: SOCKET,
    level: c_int,
    optname: c_int,
    optval: [*c]u8,
    optlen: *socklen_t,
) callconv(.Stdcall) c_int;

pub extern "ws2_32" fn recv(
    s: SOCKET,
    buf: [*]u8,
    len: c_int,
    flags: c_int,
) callconv(.Stdcall) c_int;

pub const LPFN_CONNECTEX = fn ConnectEx(
    s: SOCKET,
    name: *const sockaddr,
    namelen: c_int,
    lpSendBuffer: ?*c_void,
    dwSendDataLength: windows.DWORD,
    lpdwBytesSent: ?*windows.DWORD,
    lpOverlapped: *windows.OVERLAPPED,
) callconv(.C) windows.BOOL;
