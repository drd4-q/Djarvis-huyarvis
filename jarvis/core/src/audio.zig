const std = @import("std");
const c = @import("c.zig").c;

pub const CAPTURE_SAMPLE_RATE: u32 = 16000; // 16kHz for Whisper STT
pub const PLAYBACK_SAMPLE_RATE: u32 = 24000; // 24kHz for Piper TTS
pub const CHANNELS: u32 = 1;

// 512KB Ring buffer holds ~10.9 seconds of 24kHz 16-bit mono audio
pub const RING_BUFFER_CAPACITY: usize = 512 * 1024;

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
    capture_device: c.ma_device = undefined,
    playback_device: c.ma_device = undefined,
    capture_init: bool = false,
    playback_init: bool = false,
    
    // Callback function pointer for captured audio stream
    on_capture_chunk: ?*const fn (chunk: []const u8, user_data: ?*anyopaque) void = null,
    user_data: ?*anyopaque = null,

    fn captureCallback(
        pDevice: ?*c.ma_device,
        pOutput: ?*anyopaque,
        pInput: ?*const anyopaque,
        frameCount: c.ma_uint32,
    ) callconv(.c) void {
        _ = pOutput;
        if (pInput == null or frameCount == 0) return;

        const self: *AudioEngine = @ptrCast(@alignCast(pDevice.?.pUserData));
        const bytes_len = frameCount * @sizeOf(i16); // 16-bit mono
        const input_slice: [*]const u8 = @ptrCast(pInput.?);

        if (self.on_capture_chunk) |cb| {
            cb(input_slice[0..bytes_len], self.user_data);
        }
    }

    fn playbackCallback(
        pDevice: ?*c.ma_device,
        pOutput: ?*anyopaque,
        pInput: ?*const anyopaque,
        frameCount: c.ma_uint32,
    ) callconv(.c) void {
        _ = pInput;
        if (pOutput == null or frameCount == 0) return;

        const self: *AudioEngine = @ptrCast(@alignCast(pDevice.?.pUserData));
        const bytes_len = frameCount * @sizeOf(i16); // 16-bit mono
        const output_slice: [*]u8 = @ptrCast(pOutput.?);

        _ = self.playback_buffer.read(output_slice[0..bytes_len]);
    }

    pub fn init(
        self: *AudioEngine,
        on_capture: ?*const fn (chunk: []const u8, user_data: ?*anyopaque) void,
        user_data: ?*anyopaque,
    ) !void {
        self.on_capture_chunk = on_capture;
        self.user_data = user_data;
        self.playback_buffer.reset();

        // 1. Configure Capture Device (Microphone)
        var capture_config = c.ma_device_config_init(c.ma_device_type_capture);
        capture_config.capture.format = c.ma_format_s16;
        capture_config.capture.channels = CHANNELS;
        capture_config.sampleRate = CAPTURE_SAMPLE_RATE;
        capture_config.dataCallback = captureCallback;
        capture_config.pUserData = self;

        if (c.ma_device_init(null, &capture_config, &self.capture_device) != c.MA_SUCCESS) {
            return error.CaptureInitFailed;
        }
        self.capture_init = true;

        // 2. Configure Playback Device (Speakers / Headphones)
        var playback_config = c.ma_device_config_init(c.ma_device_type_playback);
        playback_config.playback.format = c.ma_format_s16;
        playback_config.playback.channels = CHANNELS;
        playback_config.sampleRate = PLAYBACK_SAMPLE_RATE;
        playback_config.dataCallback = playbackCallback;
        playback_config.pUserData = self;

        if (c.ma_device_init(null, &playback_config, &self.playback_device) != c.MA_SUCCESS) {
            self.deinit();
            return error.PlaybackInitFailed;
        }
        self.playback_init = true;
    }

    pub fn start(self: *AudioEngine) !void {
        if (self.capture_init) {
            if (c.ma_device_start(&self.capture_device) != c.MA_SUCCESS) {
                return error.CaptureStartFailed;
            }
        }
        if (self.playback_init) {
            if (c.ma_device_start(&self.playback_device) != c.MA_SUCCESS) {
                return error.PlaybackStartFailed;
            }
        }
    }

    pub fn pushPlaybackChunk(self: *AudioEngine, data: []const u8) void {
        _ = self.playback_buffer.write(data);
    }

    pub fn stopPlaybackImmediate(self: *AudioEngine) void {
        self.playback_buffer.reset();
    }

    pub fn deinit(self: *AudioEngine) void {
        if (self.playback_init) {
            _ = c.ma_device_stop(&self.playback_device);
            c.ma_device_uninit(&self.playback_device);
            self.playback_init = false;
        }
        if (self.capture_init) {
            _ = c.ma_device_stop(&self.capture_device);
            c.ma_device_uninit(&self.capture_device);
            self.capture_init = false;
        }
    }
};
