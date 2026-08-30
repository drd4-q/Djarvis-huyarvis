const std = @import("std");

test "check thread" {
    @compileLog(@typeInfo(std.Thread));
}
