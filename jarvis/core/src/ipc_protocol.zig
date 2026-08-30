const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig").c;

pub const MAGIC: u16 = 0x4A56; // 'JV' in little endian

pub const MsgType = enum(u16) {
    ping = 0x0001,
    pong = 0x0002,
    audio_in_chunk = 0x0010,
    audio_out_chunk = 0x0011,
    audio_out_stop = 0x0012,
    exec_action = 0x0020,
    action_result = 0x0021,
    system_event = 0x0030,
    _,
};

pub const HEADER_SIZE: usize = 8;
pub const MAX_PAYLOAD_SIZE: u32 = 4 * 1024 * 1024; // 4 MB

pub const Packet = struct {
    msg_type: MsgType,
    payload: []u8,

    pub fn deinit(self: *Packet, allocator: std.mem.Allocator) void {
        if (self.payload.len > 0) {
            allocator.free(self.payload);
        }
    }
};

pub const IpcError = error{
    InvalidMagic,
    PayloadTooLarge,
    StreamClosed,
    WriteFailed,
    ReadFailed,
};

pub const HandleType = if (builtin.os.tag == .windows) c.HANDLE else c_int;

pub fn readFull(handle: HandleType, buf: []u8) !void {
    var total_read: usize = 0;
    while (total_read < buf.len) {
        if (builtin.os.tag == .windows) {
            var bytes_read: c.DWORD = 0;
            const res = c.ReadFile(
                handle,
                @as(?*anyopaque, @ptrCast(buf[total_read..].ptr)),
                @as(c.DWORD, @intCast(buf.len - total_read)),
                &bytes_read,
                null,
            );
            if (res == 0 or bytes_read == 0) return IpcError.StreamClosed;
            total_read += bytes_read;
        } else {
            const n = std.c.read(handle, buf[total_read..].ptr, buf.len - total_read);
            if (n <= 0) return IpcError.StreamClosed;
            total_read += @as(usize, @intCast(n));
        }
    }
}

pub fn writeAll(handle: HandleType, data: []const u8) !void {
    var total_written: usize = 0;
    while (total_written < data.len) {
        if (builtin.os.tag == .windows) {
            var bytes_written: c.DWORD = 0;
            const res = c.WriteFile(
                handle,
                @as(?*const anyopaque, @ptrCast(data[total_written..].ptr)),
                @as(c.DWORD, @intCast(data.len - total_written)),
                &bytes_written,
                null,
            );
            if (res == 0) return IpcError.WriteFailed;
            total_written += bytes_written;
        } else {
            const n = std.c.write(handle, data[total_written..].ptr, data.len - total_written);
            if (n <= 0) return IpcError.WriteFailed;
            total_written += @as(usize, @intCast(n));
        }
    }
}

pub fn readPacket(handle: HandleType, allocator: std.mem.Allocator) !Packet {
    var header_bytes: [HEADER_SIZE]u8 = undefined;
    try readFull(handle, &header_bytes);

    const magic = std.mem.readInt(u16, header_bytes[0..2], .little);
    if (magic != MAGIC) return IpcError.InvalidMagic;

    const raw_type = std.mem.readInt(u16, header_bytes[2..4], .little);
    const payload_len = std.mem.readInt(u32, header_bytes[4..8], .little);

    if (payload_len > MAX_PAYLOAD_SIZE) return IpcError.PayloadTooLarge;

    var payload: []u8 = &[_]u8{};
    if (payload_len > 0) {
        payload = try allocator.alloc(u8, payload_len);
        errdefer allocator.free(payload);

        try readFull(handle, payload);
    }

    return Packet{
        .msg_type = @enumFromInt(raw_type),
        .payload = payload,
    };
}

pub fn writePacket(handle: HandleType, msg_type: MsgType, payload: []const u8) !void {
    if (payload.len > MAX_PAYLOAD_SIZE) return IpcError.PayloadTooLarge;

    var header_bytes: [HEADER_SIZE]u8 = undefined;
    std.mem.writeInt(u16, header_bytes[0..2], MAGIC, .little);
    std.mem.writeInt(u16, header_bytes[2..4], @intFromEnum(msg_type), .little);
    std.mem.writeInt(u32, header_bytes[4..8], @as(u32, @intCast(payload.len)), .little);

    try writeAll(handle, &header_bytes);
    if (payload.len > 0) {
        try writeAll(handle, payload);
    }
}
