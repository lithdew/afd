# afd

Experimenting with Windows AFD in [Zig](https://ziglang.org).

## Notes

1. AFD is oneshot-triggered. AFD needs to be rearmed after every reported event.
2. The completion of a `connect()` syscall reports `AFD_POLL_SEND | AFD_POLL_CONNECT`.