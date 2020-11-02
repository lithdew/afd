const std = @import("std");

const os = std.os;
const windows = os.windows;
const ws2_32 = windows.ws2_32;

const kernel32 = struct {
    usingnamespace windows.kernel32;

    extern "kernel32" fn GetQueuedCompletionStatusEx(
        CompletionPort: windows.HANDLE,
        lpCompletionPortEntries: [*]OVERLAPPED_ENTRY,
        ulCount: windows.ULONG,
        ulNumEntriesRemoved: *windows.ULONG,
        dwMilliseconds: windows.DWORD,
        fAlertable: windows.BOOL,
    ) callconv(.Stdcall) windows.BOOL;
};

pub const OVERLAPPED_ENTRY = extern struct {
    lpCompletionKey: windows.ULONG_PTR,
    lpOverlapped: windows.LPOVERLAPPED,
    Internal: windows.ULONG_PTR,
    dwNumberOfBytesTransferred: windows.DWORD,
};

pub const GetQueuedCompletionStatusError = error{
    Aborted,
    Cancelled,
    EOF,
    Timeout,
} || os.UnexpectedError;

pub fn GetQueuedCompletionStatusEx(
    completion_port: windows.HANDLE,
    completion_port_entries: []OVERLAPPED_ENTRY,
    timeout_ms: ?windows.DWORD,
    alertable: bool,
) GetQueuedCompletionStatusError!u32 {
    var num_entries_removed: u32 = 0;

    const result = kernel32.GetQueuedCompletionStatusEx(
        completion_port,
        completion_port_entries.ptr,
        @intCast(windows.ULONG, completion_port_entries.len),
        &num_entries_removed,
        timeout_ms orelse windows.INFINITE,
        @boolToInt(alertable),
    );

    if (result == windows.FALSE) {
        return switch (kernel32.GetLastError()) {
            .ABANDONED_WAIT_0 => error.Aborted,
            .OPERATION_ABORTED => error.Cancelled,
            .HANDLE_EOF => error.EOF,
            .IMEOUT => error.Timeout,
            else => |err| windows.unexpectedError(err),
        };
    }

    return num_entries_removed;
}
