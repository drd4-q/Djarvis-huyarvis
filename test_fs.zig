const std = @import("std");

test "check types" {
    @compileLog(@typeInfo(std.fs));
}
