const std = @import("std");
const builtin = @import("builtin");
const audio = @import("audio.zig");
const llm = @import("llm.zig");
const router_mod = @import("router.zig");
const config_mod = @import("config.zig");
const tray_mod = @import("tray.zig");

// Direct libc bindings for minimal overhead
extern fn getenv(name: [*:0]const u8) ?[*:0]const u8;

const win_c = if (builtin.os.tag == .windows) @cImport({
    @cInclude("windows.h");
    @cInclude("shellapi.h");
}) else struct {};

fn checkStartMinimized() bool {
    if (getenv("JARVIS_HIDE") != null or getenv("JARVIS_TRAY") != null or getenv("JARVIS_MINIMIZED") != null) {
        return true;
    }
    if (builtin.os.tag == .windows) {
        const cmd_line = win_c.GetCommandLineW();
        if (cmd_line != null) {
            var num_args: c_int = 0;
            const argv = win_c.CommandLineToArgvW(cmd_line, &num_args);
            if (argv != null) {
                defer _ = win_c.LocalFree(@as(?*anyopaque, @ptrCast(argv)));
                var i: usize = 0;
                while (i < @as(usize, @intCast(num_args))) : (i += 1) {
                    const arg_slice = std.mem.span(argv[i]);
                    if (std.mem.indexOf(u16, arg_slice, std.unicode.utf8ToUtf16LeStringLiteral("--tray")) != null or
                        std.mem.indexOf(u16, arg_slice, std.unicode.utf8ToUtf16LeStringLiteral("--hide")) != null or
                        std.mem.indexOf(u16, arg_slice, std.unicode.utf8ToUtf16LeStringLiteral("--minimized")) != null)
                    {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

// Global context for audio streaming and state
const AppState = struct {
    audio_engine: audio.AudioEngine = .{},
};

var global_app: AppState = .{};

fn onMicCapture(chunk: []const u8, user_data: ?*anyopaque) void {
    _ = user_data;
    _ = chunk;
    // Real-time audio stream ready for VAD / STT engine (Silero / Whisper)
}

fn readStdinLine(buf: []u8) ?[]const u8 {
    if (builtin.os.tag == .windows) {
        const h_stdin = win_c.GetStdHandle(win_c.STD_INPUT_HANDLE);
        if (h_stdin == win_c.INVALID_HANDLE_VALUE or h_stdin == null) return null;
        var bytes_read: win_c.DWORD = 0;
        const ok = win_c.ReadFile(h_stdin, buf.ptr, @as(win_c.DWORD, @intCast(buf.len)), &bytes_read, null);
        if (ok == 0 or bytes_read == 0) return null;
        return buf[0..bytes_read];
    } else {
        const n = std.posix.read(0, buf) catch return null;
        if (n == 0) return null;
        return buf[0..n];
    }
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    // Load configuration (from config.json if present)
    const app_cfg = config_mod.AppConfig.loadFromFile(allocator, "config.json");

    std.debug.print("==============================================================\n", .{});
    std.debug.print("  JARVIS AI ASSISTANT (Monolithic Unified Engine - Zig 0.16) \n", .{});
    std.debug.print("  [Profile]: {s}\n", .{app_cfg.resource_profile});
    std.debug.print("  [LLM]: {s} @ {s}:{d}\n", .{ app_cfg.llm_model, app_cfg.llm_host, app_cfg.llm_port });
    std.debug.print("  [Audio]: Miniaudio (16kHz Capture, 24kHz Playback)          \n", .{});
    std.debug.print("  [Tools]: Direct Win32 / POSIX In-Memory Control             \n", .{});
    std.debug.print("==============================================================\n\n", .{});

    // 1. Initialize Audio Engine
    std.debug.print("[Audio] Initializing capture & playback devices...\n", .{});
    global_app.audio_engine.init(onMicCapture, null) catch |err| {
        std.debug.print("[Audio] Warning: Audio init failed ({any}), continuing in text mode\n", .{err});
    };
    defer global_app.audio_engine.deinit();

    global_app.audio_engine.start() catch |err| {
        std.debug.print("[Audio] Warning: Audio start failed ({any})\n", .{err});
    };

    // 2. Initialize LLM Client
    var llm_cfg: llm.Config = .{
        .host = app_cfg.llm_host,
        .port = app_cfg.llm_port,
        .model_name = app_cfg.llm_model,
        .temperature = app_cfg.llm_temperature,
    };
    if (getenv("LLAMA_SERVER_PORT")) |port_str| {
        const port_slice = std.mem.span(port_str);
        if (std.fmt.parseInt(u16, port_slice, 10)) |p| {
            llm_cfg.port = p;
        } else |_| {}
    }
    if (getenv("LLAMA_SERVER_HOST")) |host_str| {
        llm_cfg.host = std.mem.span(host_str);
    }

    const llm_client = llm.Client.init(llm_cfg);

    // 3. Initialize Tray Icon
    std.debug.print("[Tray] Initializing system tray notification icon...\n", .{});
    const tray_thread: ?std.Thread = tray_mod.startTrayThread() catch |err| blk: {
        std.debug.print("[Tray] Warning: Tray thread init failed ({any})\n", .{err});
        break :blk null;
    };
    defer if (tray_thread) |t| t.detach();

    // 4. Initialize Router
    var router = router_mod.Router.init(allocator, llm_client);
    defer router.deinit();

    // Check if launched with --tray or --hide to start minimized in tray
    if (checkStartMinimized()) {
        tray_mod.showConsole(false);
    }

    std.debug.print("[Jarvis] Ready. Enter your command or type 'exit'/'quit' to stop.\n", .{});
    std.debug.print("[Jarvis] (You can minimize/restore window via System Tray icon)\n\n", .{});

    // 5. Interactive REPL loop
    var line_buf: [4096]u8 = undefined;
    while (!tray_mod.should_exit.load(.acquire)) {
        std.debug.print("[User]: ", .{});
        const line = readStdinLine(&line_buf);
        if (line == null) break; // EOF

        if (tray_mod.should_exit.load(.acquire)) break;

        const trimmed = std.mem.trim(u8, line.?, " \r\n\t");
        if (trimmed.len == 0) continue;

        if (std.mem.eql(u8, trimmed, "exit") or std.mem.eql(u8, trimmed, "quit")) {
            std.debug.print("\n[Jarvis] Выключение. До свидания!\n", .{});
            break;
        }

        const reply = router.processUserText(trimmed) catch |err| {
            std.debug.print("[Jarvis Error]: Failed to get response: {any}\n", .{err});
            continue;
        };

        std.debug.print("[Jarvis]: {s}\n\n", .{reply});
    }
}

