const std = @import("std");
const builtin = @import("builtin");

extern fn popen(command: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern fn pclose(stream: ?*anyopaque) c_int;
extern fn fopen(filename: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern fn fclose(stream: ?*anyopaque) c_int;
extern fn fwrite(ptr: [*]const u8, size: usize, nmemb: usize, stream: ?*anyopaque) usize;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, stream: ?*anyopaque) usize;

var g_wav_seq = std.atomic.Value(u32).init(0);

pub const SttEngine = struct {
    allocator: std.mem.Allocator,
    whisper_exe: []const u8 = "bin\\whisper\\whisper-cli.exe",
    model_path: []const u8 = "models\\ggml-base.bin",

    // VAD & Buffering state
    speech_samples: std.ArrayList(i16) = .empty,
    preroll_buf: [4800]i16 = std.mem.zeroes([4800]i16), // 300ms pre-roll to preserve first syllable
    preroll_pos: usize = 0,
    preroll_count: usize = 0,
    is_speaking: bool = false,
    silence_frames: usize = 0,
    energy_threshold: i32 = 300, // RMS energy threshold for speech (sensitive and crisp)
    min_speech_frames: usize = 16000 * 4 / 10, // ~400ms minimum speech
    max_silence_frames: usize = 16000 * 7 / 10, // ~700ms silence to conclude utterance

    on_speech_recognized: ?*const fn (text: []const u8, udata: ?*anyopaque) void = null,
    user_data: ?*anyopaque = null,
    lock: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    fn acquireLock(self: *SttEngine) void {
        while (self.lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    fn releaseLock(self: *SttEngine) void {
        self.lock.store(false, .release);
    }

    pub fn init(allocator: std.mem.Allocator) SttEngine {
        var m_path: []const u8 = "models\\ggml-base.bin";
        const f_small = fopen("models\\ggml-small.bin", "rb");
        if (f_small != null) {
            _ = fclose(f_small);
            m_path = "models\\ggml-small.bin";
        }

        return .{
            .allocator = allocator,
            .whisper_exe = "bin\\whisper\\whisper-cli.exe",
            .model_path = m_path,
            .speech_samples = .empty,
        };
    }

    pub fn deinit(self: *SttEngine) void {
        self.speech_samples.deinit(self.allocator);
    }

    pub fn setCallback(self: *SttEngine, cb: *const fn (text: []const u8, udata: ?*anyopaque) void, udata: ?*anyopaque) void {
        self.on_speech_recognized = cb;
        self.user_data = udata;
    }

    pub fn processMicChunk(self: *SttEngine, chunk: []const u8) void {
        if (chunk.len < 2) return;
        const num_samples = chunk.len / 2;
        const samples_ptr: [*]const i16 = @ptrCast(@alignCast(chunk.ptr));
        const samples = samples_ptr[0..num_samples];

        // 1. Calculate RMS energy of this chunk
        var sum_sq: u64 = 0;
        for (samples) |s| {
            const val: i64 = @as(i64, s);
            sum_sq += @intCast(val * val);
        }
        const rms: i32 = @intCast(std.math.sqrt(sum_sq / @as(u64, @max(1, num_samples))));

        self.acquireLock();
        defer self.releaseLock();

        if (rms > self.energy_threshold) {
            // Speech detected
            if (!self.is_speaking) {
                self.is_speaking = true;
                self.silence_frames = 0;

                // Prepend 300ms pre-roll buffer so the beginning of the word is never chopped
                if (self.preroll_count > 0) {
                    var read_idx: usize = if (self.preroll_count < 4800) 0 else self.preroll_pos;
                    var copied: usize = 0;
                    while (copied < self.preroll_count) : (copied += 1) {
                        self.speech_samples.append(self.allocator, self.preroll_buf[read_idx]) catch break;
                        read_idx = (read_idx + 1) % 4800;
                    }
                }
            }
            self.speech_samples.appendSlice(self.allocator, samples) catch return;
            self.silence_frames = 0;
        } else if (self.is_speaking) {
            // Currently in speech, but this chunk is silent
            self.speech_samples.appendSlice(self.allocator, samples) catch return;
            self.silence_frames += num_samples;

            if (self.silence_frames >= self.max_silence_frames) {
                // Utterance finished!
                const total_samples = self.speech_samples.items.len;
                self.is_speaking = false;
                self.silence_frames = 0;
                self.preroll_count = 0;
                self.preroll_pos = 0;

                if (total_samples >= self.min_speech_frames) {
                    const samples_copy = self.allocator.dupe(i16, self.speech_samples.items) catch return;
                    self.speech_samples.clearRetainingCapacity();

                    // Spawn worker to transcribe without blocking audio capture thread
                    const Worker = struct {
                        fn run(alloc: std.mem.Allocator, w_exe: []const u8, m_path: []const u8, s_data: []const i16, cb: ?*const fn (text: []const u8, udata: ?*anyopaque) void, udata: ?*anyopaque) void {
                            defer alloc.free(s_data);
                            const seq = g_wav_seq.fetchAdd(1, .monotonic) % 8;
                            var wav_name_buf: [64]u8 = undefined;
                            const wav_file = std.fmt.bufPrint(&wav_name_buf, "cache_mic_{d}.wav", .{seq}) catch "cache_mic.wav";

                            // Write normalized WAV file
                            writeWavFile(wav_file, s_data);

                            // Transcribe with whisper-cli using optimal beam search and Russian assistant prompt
                            var cmd_buf: [1024]u8 = undefined;
                            const cmd_str = std.fmt.bufPrint(&cmd_buf,
                                "{s} -m {s} -l ru -nt -np -nf -sns --best-of 5 --beam-size 5 -tp 0.0 --prompt \"Джарвис — умный голосовой помощник. Джарвис, сколько времени? Джарвис, открой браузер, включи музыку, сделай громкость.\" -f {s}",
                                .{ w_exe, m_path, wav_file }
                            ) catch return;

                            var cmd_z = alloc.allocSentinel(u8, cmd_str.len, 0) catch return;
                            defer alloc.free(cmd_z);
                            @memcpy(cmd_z[0..cmd_str.len], cmd_str);

                            const stream = popen(cmd_z.ptr, "r") orelse return;
                            defer _ = pclose(stream);

                            var out_buf = alloc.alloc(u8, 4096) catch return;
                            defer alloc.free(out_buf);

                            var total_read: usize = 0;
                            while (total_read < 4090) {
                                const n = fread(out_buf[total_read..].ptr, 1, 4090 - total_read, stream);
                                if (n == 0) break;
                                total_read += n;
                            }

                            const raw_text = out_buf[0..total_read];
                            const cleaned = cleanWhisperOutput(alloc, raw_text) catch return;
                            defer alloc.free(cleaned);

                            if (cleaned.len >= 2) {
                                if (cb) |callback| {
                                    callback(cleaned, udata);
                                }
                            }
                        }
                    };

                    const thread = std.Thread.spawn(.{}, Worker.run, .{
                        self.allocator,
                        self.whisper_exe,
                        self.model_path,
                        samples_copy,
                        self.on_speech_recognized,
                        self.user_data,
                    }) catch return;
                    thread.detach();
                } else {
                    self.speech_samples.clearRetainingCapacity();
                }
            }
        } else {
            // Silence before speech: store into circular pre-roll buffer
            for (samples) |s| {
                self.preroll_buf[self.preroll_pos] = s;
                self.preroll_pos = (self.preroll_pos + 1) % 4800;
                if (self.preroll_count < 4800) self.preroll_count += 1;
            }
        }
    }

    fn writeWavFile(filename: []const u8, samples: []const i16) void {
        var fn_z: [256:0]u8 = undefined;
        if (filename.len >= 256) return;
        @memcpy(fn_z[0..filename.len], filename);
        fn_z[filename.len] = 0;

        const f = fopen(&fn_z, "wb") orelse return;
        defer _ = fclose(f);

        const data_len: u32 = @intCast(samples.len * @sizeOf(i16));
        const chunk_size: u32 = 36 + data_len;
        const sample_rate: u32 = 16000;
        const byte_rate: u32 = sample_rate * 2;
        const block_align: u16 = 2;
        const bits_per_sample: u16 = 16;
        const num_channels: u16 = 1;
        const audio_format: u16 = 1; // PCM

        var header: [44]u8 = undefined;
        @memcpy(header[0..4], "RIFF");
        std.mem.writeInt(u32, header[4..8], chunk_size, .little);
        @memcpy(header[8..12], "WAVE");
        @memcpy(header[12..16], "fmt ");
        std.mem.writeInt(u32, header[16..20], 16, .little);
        std.mem.writeInt(u16, header[20..22], audio_format, .little);
        std.mem.writeInt(u16, header[22..24], num_channels, .little);
        std.mem.writeInt(u32, header[24..28], sample_rate, .little);
        std.mem.writeInt(u32, header[28..32], byte_rate, .little);
        std.mem.writeInt(u16, header[32..34], block_align, .little);
        std.mem.writeInt(u16, header[34..36], bits_per_sample, .little);
        @memcpy(header[36..40], "data");
        std.mem.writeInt(u32, header[40..44], data_len, .little);

        _ = fwrite(&header, 1, 44, f);

        // Normalize peak audio volume to ~24000 for crystal-clear Whisper decoding
        var max_val: i32 = 1;
        for (samples) |s| {
            const abs_s: i32 = if (s < 0) -@as(i32, s) else @as(i32, s);
            if (abs_s > max_val) max_val = abs_s;
        }

        const gain: f32 = if (max_val > 400 and max_val < 18000)
            @min(4.0, 24000.0 / @as(f32, @floatFromInt(max_val)))
        else
            1.0;

        if (gain > 1.05) {
            for (samples) |s| {
                const scaled: f32 = @as(f32, @floatFromInt(s)) * gain;
                const clamped: i16 = @intCast(std.math.clamp(@as(i32, @intFromFloat(scaled)), -32768, 32767));
                var s_bytes: [2]u8 = undefined;
                std.mem.writeInt(i16, &s_bytes, clamped, .little);
                _ = fwrite(&s_bytes, 1, 2, f);
            }
        } else {
            _ = fwrite(@as([*]const u8, @ptrCast(samples.ptr)), 1, data_len, f);
        }
    }

    fn cleanWhisperOutput(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
        var trimmed = std.mem.trim(u8, raw, " \r\n\t");
        while (std.mem.indexOf(u8, trimmed, "\n")) |nl| {
            if (std.mem.startsWith(u8, trimmed, "load_backend:") or
                std.mem.startsWith(u8, trimmed, "read_audio_data:") or
                std.mem.startsWith(u8, trimmed, "whisper_") or
                std.mem.startsWith(u8, trimmed, "system_info:")) {
                trimmed = std.mem.trim(u8, trimmed[nl + 1 ..], " \r\n\t");
            } else {
                break;
            }
        }
        // Ignore hallucinations like [музыка], (музыка), [Субтитры], etc.
        if (std.mem.startsWith(u8, trimmed, "[") and std.mem.endsWith(u8, trimmed, "]")) return try allocator.dupe(u8, "");
        if (std.mem.startsWith(u8, trimmed, "(") and std.mem.endsWith(u8, trimmed, ")")) return try allocator.dupe(u8, "");

        var current = try allocator.dupe(u8, trimmed);

        const replacements = [_][2][]const u8{
            .{ "джарга", "джарвис" },
            .{ "Джарга", "Джарвис" },
            .{ "джаррис", "джарвис" },
            .{ "Джаррис", "Джарвис" },
            .{ "дарвис", "джарвис" },
            .{ "Дарвис", "Джарвис" },
            .{ "жарвис", "джарвис" },
            .{ "Жарвис", "Джарвис" },
            .{ "гарвис", "джарвис" },
            .{ "Гарвис", "Джарвис" },
            .{ "jarvis", "джарвис" },
            .{ "Jarvis", "Джарвис" },
            .{ "сключи", "включи" },
            .{ "потищи", "потише" },
            .{ "погромчи", "погромче" },
        };

        for (replacements) |pair| {
            if (std.mem.indexOf(u8, current, pair[0])) |_| {
                const replaced = try std.mem.replaceOwned(u8, allocator, current, pair[0], pair[1]);
                allocator.free(current);
                current = replaced;
            }
        }

        return current;
    }
};
