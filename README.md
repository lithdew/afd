# afd

Experimenting with Windows AFD in [Zig](https://ziglang.org).

## Notes

1. AFD is oneshot-triggered. AFD needs to be rearmed after every reported event.
2. The completion of a `connect()` syscall reports `AFD_POLL_SEND | AFD_POLL_CONNECT`.
3. If there are no more async frames to be resumed, and we receive an IOCP notification that a file handle is ready to be read from yet not ready to be written to, request the AFD driver to stop reporting that the file handle may be ready to be read from. Vice versa in the case that the file handle may be ready to be written to.

   In the case that a file handle is ready to be both read from and written to, we do not request for any further notifications from AFD for the specified file handle. This allows us to emulate edge-triggered notifications when it comes to whether or not a file handle is ready to be read to/written from.