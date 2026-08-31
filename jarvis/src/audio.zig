const std = @import("std");

pub const CAPTURE_SAMPLE_RATE: u32 = 16000;
pub const PLAYBACK_SAMPLE_RATE: u32 = 24000;
pub const CHANNELS: u32 = 1;

pub const RING_BUFFER_CAPACITY: usize = 512 * 1024;

pub const AudioCaptureCallback = ?*const fn (samples: [*c]const i16, frame_count: u32, user_data: ?*anyopaque) callconv(.c) void;
pub const AudioPlaybackCallback = ?*const fn (samples: [*c]i16, frame_count: u32, user_data: ?*anyopaque) callconv(.c) void;

pub extern fn audio_bridge_init(
    on_capture: AudioCaptureCallback,
    on_playback: AudioPlaybackCallback,
    user_data: ?*anyopaque,
) c_int;

pub extern fn audio_bridge_start() c_int;
pub extern fn audio_bridge_stop() void;
pub extern fn audio_bridge_deinit() void;

pub const SpinLock = struct {
    state: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn lock(self: *SpinLock) void {
        while (self.state.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *SpinLock) void {
        self.state.store(false, .release);
    }
};

pub const AudioRingBuffer = struct {
    buffer: [RING_BUFFER_CAPACITY]u8 = undefined,
    read_pos: usize = 0,
    write_pos: usize = 0,
    available: usize = 0,
    lock: SpinLock = .{},

    pub fn write(self: *AudioRingBuffer, data: []const u8) usize {
        self.lock.lock();
        defer self.lock.unlock();

        const space_left = RING_BUFFER_CAPACITY - self.available;
        const to_write = @min(data.len, space_left);
        if (to_write == 0) return 0;

        var written: usize = 0;
        while (written < to_write) {
            const chunk = @min(to_write - written, RING_BUFFER_CAPACITY - self.write_pos);
            @memcpy(self.buffer[self.write_pos .. self.write_pos + chunk], data[written .. written + chunk]);
            self.write_pos = (self.write_pos + chunk) % RING_BUFFER_CAPACITY;
            written += chunk;
        }

        self.available += to_write;
        return to_write;
    }

    pub fn read(self: *AudioRingBuffer, dest: []u8) usize {
        self.lock.lock();
        defer self.lock.unlock();

        const to_read = @min(dest.len, self.available);
        if (to_read == 0) {
            @memset(dest, 0);
            return 0;
        }

        var read_bytes: usize = 0;
        while (read_bytes < to_read) {
            const chunk = @min(to_read - read_bytes, RING_BUFFER_CAPACITY - self.read_pos);
            @memcpy(dest[read_bytes .. read_bytes + chunk], self.buffer[self.read_pos .. self.read_pos + chunk]);
            self.read_pos = (self.read_pos + chunk) % RING_BUFFER_CAPACITY;
            read_bytes += chunk;
        }

        self.available -= to_read;

        if (to_read < dest.len) {
            @memset(dest[to_read..], 0);
        }

        return to_read;
    }

    pub fn reset(self: *AudioRingBuffer) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.read_pos = 0;
        self.write_pos = 0;
        self.available = 0;
    }
};

pub const AudioEngine = struct {
    playback_buffer: AudioRingBuffer = .{},
    on_capture_chunk: ?*const fn (chunk: []const u8, user_data: ?*anyopaque) void = null,
    user_data: ?*anyopaque = null,

    fn cCaptureCallback(samples: [*c]const i16, frame_count: u32, udata: ?*anyopaque) callconv(.c) void {
        if (udata == null or samples == null or frame_count == 0) return;
        const self: *AudioEngine = @ptrCast(@alignCast(udata.?));
        const bytes_len = frame_count * @sizeOf(i16);
        const ptr_u8: [*]const u8 = @ptrCast(samples);

        if (self.on_capture_chunk) |cb| {
            cb(ptr_u8[0..bytes_len], self.user_data);
        }
    }

    fn cPlaybackCallback(samples: [*c]i16, frame_count: u32, udata: ?*anyopaque) callconv(.c) void {
        if (udata == null or samples == null or frame_count == 0) return;
        const self: *AudioEngine = @ptrCast(@alignCast(udata.?));
        const bytes_len = frame_count * @sizeOf(i16);
        const ptr_u8: [*]u8 = @ptrCast(samples);

        _ = self.playback_buffer.read(ptr_u8[0..bytes_len]);
    }

    pub fn init(
        self: *AudioEngine,
        on_capture: ?*const fn (chunk: []const u8, user_data: ?*anyopaque) void,
        user_data: ?*anyopaque,
    ) !void {
        self.on_capture_chunk = on_capture;
        self.user_data = user_data;
        self.playback_buffer.reset();

        const ret = audio_bridge_init(cCaptureCallback, cPlaybackCallback, self);
        if (ret != 0) {
            return error.AudioInitFailed;
        }
    }

    pub fn start(self: *AudioEngine) !void {
        _ = self;
        if (audio_bridge_start() != 0) {
            return error.AudioStartFailed;
        }
    }

    pub fn pushPlaybackChunk(self: *AudioEngine, data: []const u8) void {
        _ = self.playback_buffer.write(data);
    }

    pub fn stopPlaybackImmediate(self: *AudioEngine) void {
        self.playback_buffer.reset();
    }

    pub fn deinit(self: *AudioEngine) void {
        _ = self;
        audio_bridge_deinit();
    }
};
