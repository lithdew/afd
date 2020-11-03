const std = @import("std");

const windows = @import("windows.zig");
const ws2_32 = windows.ws2_32;

pub usingnamespace ws2_32;

pub extern "ws2_32" fn getsockopt(
    s: SOCKET,
    level: c_int,
    optname: c_int,
    optval: [*c]u8,
    optlen: *socklen_t,
) callconv(.Stdcall) c_int;
