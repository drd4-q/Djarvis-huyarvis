const std = @import("std");
const builtin = @import("builtin");

const win_c = if (builtin.os.tag == .windows) @cImport({
    @cInclude("windows.h");
    @cInclude("mmsystem.h");
}) else struct {};

extern fn popen(command: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern fn pclose(stream: ?*anyopaque) c_int;
extern fn fopen(filename: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern fn fclose(stream: ?*anyopaque) c_int;
extern fn fwrite(ptr: [*]const u8, size: usize, nmemb: usize, stream: ?*anyopaque) usize;

pub const TtsEngine = struct {
    allocator: std.mem.Allocator,
    piper_exe: []const u8 = "bin\\piper\\piper.exe",
    model_path: []const u8 = "models\\ru_RU-dmitri-medium.onnx",

    fn checkFileExists(path: []const u8) bool {
        var p_z: [256:0]u8 = undefined;
        if (path.len >= 256) return false;
        @memcpy(p_z[0..path.len], path);
        p_z[path.len] = 0;
        const fp = fopen(&p_z, "rb");
        if (fp) |f| {
            _ = fclose(f);
            return true;
        }
        return false;
    }

    pub fn init(allocator: std.mem.Allocator) TtsEngine {
        return .{
            .allocator = allocator,
            .piper_exe = "bin\\piper\\piper.exe",
            .model_path = "models\\ru_RU-dmitri-medium.onnx",
        };
    }

    pub fn speakAsync(self: *const TtsEngine, text: []const u8) void {
        const text_trimmed = std.mem.trim(u8, text, " \r\n\t*`#_");
        if (text_trimmed.len == 0 or std.mem.eql(u8, text_trimmed, "None") or std.mem.eql(u8, text_trimmed, "null")) return;

        // Clean up and normalize formatting for speech
        var clean_text: std.ArrayList(u8) = .empty;
        defer clean_text.deinit(self.allocator);

        for (text_trimmed) |c| {
            switch (c) {
                '%' => clean_text.appendSlice(self.allocator, " процентов ") catch {},
                '+' => clean_text.appendSlice(self.allocator, " плюс ") catch {},
                '=' => clean_text.appendSlice(self.allocator, " равно ") catch {},
                '*', '`', '#', '_', '^', '<', '>', '|', '&', '~', '{', '}', '[', ']' => {},
                '"', '\'' => clean_text.append(self.allocator, ' ') catch {},
                else => clean_text.append(self.allocator, c) catch {},
            }
        }

        const normalized = std.mem.trim(u8, clean_text.items, " \r\n\t");
        if (normalized.len == 0) return;

        const speech_copy = self.allocator.dupe(u8, normalized) catch return;

        const Worker = struct {
            fn run(alloc: std.mem.Allocator, piper_path: []const u8, m_path: []const u8, speech: []const u8) void {
                defer alloc.free(speech);

                const txt_file = "cache_tts.txt";
                const wav_file = "cache_tts.wav";

                // Check if piper exists
                var piper_z: [256:0]u8 = undefined;
                if (piper_path.len < 256) {
                    @memcpy(piper_z[0..piper_path.len], piper_path);
                    piper_z[piper_path.len] = 0;
                    const f_test = fopen(&piper_z, "rb");
                    if (f_test != null) {
                        _ = fclose(f_test);

                        // 1. Write clean UTF-8 text file directly to disk to prevent Windows CP866/1251 mangling
                        var txt_z: [256:0]u8 = undefined;
                        @memcpy(txt_z[0..txt_file.len], txt_file);
                        txt_z[txt_file.len] = 0;

                        const f_txt = fopen(&txt_z, "wb");
                        if (f_txt != null) {
                            _ = fwrite(speech.ptr, 1, speech.len, f_txt);
                            _ = fclose(f_txt);
                        }

                        // 2. Synthesize via Piper with clear, natural pace
                        var cmd_buf: [1024]u8 = undefined;
                        const cmd = std.fmt.bufPrint(&cmd_buf,
                            "cmd /c \"type {s} | {s} -m {s} --length-scale 1.02 --sentence-silence 0.2 -f {s}\"",
                            .{ txt_file, piper_path, m_path, wav_file }
                        ) catch return;

                        var cmd_z = alloc.allocSentinel(u8, cmd.len, 0) catch return;
                        defer alloc.free(cmd_z);
                        @memcpy(cmd_z[0..cmd.len], cmd);

                        if (popen(cmd_z.ptr, "r")) |st| {
                            _ = pclose(st);
                        }

                        // 3. Play synthesized WAV on Windows
                        if (builtin.os.tag == .windows) {
                            var wav_w: [256:0]u16 = undefined;
                            if (std.unicode.utf8ToUtf16Le(&wav_w, wav_file)) |w_len| {
                                wav_w[w_len] = 0;
                                _ = win_c.PlaySoundW(@as([*:0]const u16, @ptrCast(&wav_w)), null, win_c.SND_FILENAME | win_c.SND_ASYNC);
                            } else |_| {}
                        }
                        return;
                    }
                }

                // Fallback to Windows built-in SAPI via PowerShell
                if (builtin.os.tag == .windows) {
                    const ps_cmd_buf = alloc.alloc(u8, speech.len + 512) catch return;
                    defer alloc.free(ps_cmd_buf);

                    const ps_script = std.fmt.bufPrint(ps_cmd_buf,
                        "powershell -NoProfile -NonInteractive -Command \"Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Speak('{s}')\"",
                        .{ speech }
                    ) catch return;

                    var ps_z = alloc.allocSentinel(u8, ps_script.len, 0) catch return;
                    defer alloc.free(ps_z);
                    @memcpy(ps_z[0..ps_script.len], ps_script);

                    if (popen(ps_z.ptr, "r")) |st| {
                        _ = pclose(st);
                    }
                }
            }
        };

        const t = std.Thread.spawn(.{}, Worker.run, .{ self.allocator, self.piper_exe, self.model_path, speech_copy }) catch {
            self.allocator.free(speech_copy);
            return;
        };
        t.detach();
    }
};
