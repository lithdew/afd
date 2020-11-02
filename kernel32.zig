const std = @import("std");

const os = std.os;
const windows = os.windows;
const kernel32 = windows.kernel32;

pub usingnamespace kernel32;

pub extern "kernel32" fn GetQueuedCompletionStatusEx(
    CompletionPort: windows.HANDLE,
    lpCompletionPortEntries: [*]OVERLAPPED_ENTRY,
    ulCount: windows.ULONG,
    ulNumEntriesRemoved: *windows.ULONG,
    dwMilliseconds: windows.DWORD,
    fAlertable: windows.BOOL,
) callconv(.Stdcall) windows.BOOL;
