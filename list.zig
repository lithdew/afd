const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

pub fn List(comptime T: type) type {
    return packed struct {
        const Self = @This();

        pub const Node = struct {
            data: T,
            next: ?*Self.Node = null,
            prev: ?*Self.Node = null,
            tail: ?*Self.Node = null,
        };

        head: ?*Node = null,

        pub fn append(self: *Self, node: *Self.Node) void {
            assert(node.tail == null);
            assert(node.prev == null);
            assert(node.next == null);

            if (self.head) |head| {
                assert(head.prev == null);

                const tail = head.tail orelse unreachable;

                node.prev = tail;
                tail.next = node;

                head.tail = node;
            } else {
                node.tail = node;
                self.head = node;
            }
        }

        pub fn prepend(self: *Self, node: *Self.Node) void {
            assert(node.tail == null);
            assert(node.prev == null);
            assert(node.next == null);

            if (self.head) |head| {
                assert(head.prev == null);

                node.tail = head.tail;
                head.tail = null;

                node.next = head;
                head.prev = node;

                self.head = node;
            } else {
                node.tail = node;
                self.head = node;
            }
        }

        pub fn pop(self: *Self) ?T {
            if (self.head) |head| {
                assert(head.prev == null);

                self.head = head.next;
                if (self.head) |next| {
                    next.tail = head.tail;
                    next.prev = null;
                }

                return head.data;
            }

            return null;
        }
    };
}

test "List.append() / List.prepend() / List.pop()" {
    const U8List = List(u8);
    const Node = U8List.Node;

    var list: U8List = .{};

    var A = Node{ .data = 'A' };
    var B = Node{ .data = 'B' };
    var C = Node{ .data = 'C' };
    var D = Node{ .data = 'D' };

    list.append(&C);
    list.prepend(&B);
    list.append(&D);
    list.prepend(&A);

    const expected = "ABCD";

    var i: usize = 0;
    while (list.pop()) |data| : (i += 1) {
        testing.expectEqual(data, expected[i]);
    }
}
