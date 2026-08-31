const std = @import("std");
const builtin = @import("builtin");
const audio = @import("audio.zig");
const llm = @import("llm.zig");
const router_mod = @import("router.zig");
const config_mod = @import("config.zig");
const tray_mod = @import("tray.zig");
const tts_mod = @import("tts.zig");
const stt_mod = @import("stt.zig");
const win32 = @import("win32.zig");

// Direct libc bindings for minimal overhead
extern fn getenv(name: [*:0]const u8) ?[*:0]const u8;
extern fn fopen(filename: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern fn fclose(stream: ?*anyopaque) c_int;

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
    stt_engine: ?*stt_mod.SttEngine = null,
    router: ?*router_mod.Router = null,
    tts_engine: ?*const tts_mod.TtsEngine = null,
    busy_lock: audio.SpinLock = .{},
};

var global_app: AppState = .{};

fn onMicCapture(chunk: []const u8, user_data: ?*anyopaque) void {
    _ = user_data;
    // Suppress microphone input while TTS is playing sound through speakers to prevent echo loop
    if (tts_mod.isPlayingAudio()) return;
    if (global_app.stt_engine) |stt| {
        stt.processMicChunk(chunk);
    }
}

fn onVoiceCommandRecognized(text: []const u8, udata: ?*anyopaque) void {
    _ = udata;
    const trimmed = std.mem.trim(u8, text, " \r\n\t.,!?");
    if (trimmed.len == 0) return;

    if (std.mem.eql(u8, trimmed, ".") or std.mem.eql(u8, trimmed, "?") or std.mem.eql(u8, trimmed, "!")) return;

    std.debug.print("\n[Voice Input]: {s}\n", .{trimmed});

    if (global_app.router) |r| {
        const reply = r.processUserText(trimmed) catch |err| {
            std.debug.print("[Jarvis Voice Error]: {any}\n", .{err});
            return;
        };

        std.debug.print("[Jarvis]: {s}\n\n", .{reply});

        if (global_app.tts_engine) |tts| {
            tts.speakAsync(reply);
        }
    }
}

fn sleepMs(ms: u32) void {
    if (builtin.os.tag == .windows) {
        win_c.Sleep(ms);
    } else {
        const req = std.posix.timespec{
            .sec = @intCast(ms / 1000),
            .nsec = @intCast((ms % 1000) * 1_000_000),
        };
        _ = std.posix.nanosleep(&req, null);
    }
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

fn printHelp() void {
    std.debug.print("\n", .{});
    std.debug.print("========================================================================\n", .{});
    std.debug.print("                СПИСОК КОМАНД И ВОЗМОЖНОСТЕЙ JARVIS                     \n", .{});
    std.debug.print("========================================================================\n", .{});
    std.debug.print("  🔊 ЗВУК И МУЛЬТИМЕДИА:\n", .{});
    std.debug.print("    • «Сделай громкость 50%» / «Звук на максимум» / «Потише»\n", .{});
    std.debug.print("    • «Выключи звук» (Mute) / «Включи звук»\n", .{});
    std.debug.print("    • «Поставь на паузу» / «Продолжи воспроизведение»\n", .{});
    std.debug.print("    • «Следующий трек» / «Предыдущий трек»\n\n", .{});

    std.debug.print("  👁️ ЗРЕНИЕ ЭКРАНА (SmolVLM-256M):\n", .{});
    std.debug.print("    • «Что сейчас на экране?» / «Посмотри на экран»\n", .{});
    std.debug.print("    • «Опиши, что открыто на компьютере» / «Прочитай текст с экрана»\n\n", .{});

    std.debug.print("  🚀 ПРИЛОЖЕНИЯ И ИНТЕРНЕТ:\n", .{});
    std.debug.print("    • «Открой Блокнот / Калькулятор / Диспетчер задач / Paint»\n", .{});
    std.debug.print("    • «Открой браузер» / «Открой YouTube / GitHub / Telegram»\n", .{});
    std.debug.print("    • «Найди в интернете: курс биткоина» / «Кто такой Илон Маск?»\n", .{});
    std.debug.print("    • «Посмотри, что на сайте https://...»\n\n", .{});

    std.debug.print("  💻 УПРАВЛЕНИЕ ОКНАМИ:\n", .{});
    std.debug.print("    • «Сверни все окна» / «Покажи рабочий стол»\n", .{});
    std.debug.print("    • «Закрой окно» / «Закрой вкладку»\n", .{});
    std.debug.print("    • «Переключись на окно Telegram / Chrome / VS Code»\n\n", .{});

    std.debug.print("  ⚡ СИСТЕМА И ПИТАНИЕ:\n", .{});
    std.debug.print("    • «Заблокируй компьютер»\n", .{});
    std.debug.print("    • «Выключи компьютер через 5 минут» / «Перезагрузи ПК»\n", .{});
    std.debug.print("    • «Отмени выключение компьютера»\n", .{});
    std.debug.print("    • «Переведи компьютер в спящий режим»\n\n", .{});

    std.debug.print("  🛠️ УТИЛИТЫ И ИНФОРМАЦИЯ:\n", .{});
    std.debug.print("    • «Сделай скриншот» (сохраняется в папку Изображения)\n", .{});
    std.debug.print("    • «Очисти корзину»\n", .{});
    std.debug.print("    • «Сколько сейчас времени?» / «Какой сегодня день?»\n", .{});
    std.debug.print("    • «Сколько заряда батареи?»\n", .{});
    std.debug.print("    • «Какая нагрузка на систему / сколько свободной памяти?»\n", .{});
    std.debug.print("    • «Выполни команду: ping 8.8.8.8»\n", .{});
    std.debug.print("========================================================================\n\n", .{});
}

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        _ = win_c.SetConsoleOutputCP(65001);
        _ = win_c.SetConsoleCP(65001);
    }

    const allocator = std.heap.c_allocator;

    // Load configuration (from config.json if present)
    const app_cfg = config_mod.AppConfig.loadFromFile(allocator, "config.json");

    std.debug.print("==============================================================\n", .{});
    std.debug.print("  JARVIS AI ASSISTANT (Monolithic Unified Engine - Zig 0.16) \n", .{});
    std.debug.print("  [Profile]: {s}\n", .{app_cfg.resource_profile});
    std.debug.print("  [LLM]: {s} @ {s}:{d}\n", .{ app_cfg.llm_model, app_cfg.llm_host, app_cfg.llm_port });
    std.debug.print("  [STT]: Whisper Base/Small (16kHz VAD Mic Capture)          \n", .{});
    std.debug.print("  [TTS]: Piper Neural Voice (ru_RU-dmitri) + Windows SAPI     \n", .{});
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

    // 2. Initialize STT Engine (Whisper + VAD)
    var stt_engine = stt_mod.SttEngine.init(allocator);
    defer stt_engine.deinit();
    stt_engine.setCallback(onVoiceCommandRecognized, null);
    global_app.stt_engine = &stt_engine;

    // 3. Initialize LLM Client
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

    // 4. Initialize TTS Engine
    const tts_engine = tts_mod.TtsEngine.init(allocator);
    global_app.tts_engine = &tts_engine;

    // 5. Initialize Tray Icon
    std.debug.print("[Tray] Initializing system tray notification icon...\n", .{});
    const tray_thread: ?std.Thread = tray_mod.startTrayThread() catch |err| blk: {
        std.debug.print("[Tray] Warning: Tray thread init failed ({any})\n", .{err});
        break :blk null;
    };
    defer if (tray_thread) |t| t.detach();

    // 6. Initialize Router
    var router = router_mod.Router.init(allocator, llm_client);
    defer router.deinit();
    global_app.router = &router;

    // Check if launched with --tray or --hide to start minimized in tray
    if (checkStartMinimized()) {
        tray_mod.showConsole(false);
    }

    // Auto-index installed apps database if missing
    if (builtin.os.tag == .windows) {
        const fp_apps = fopen("cache_apps.json", "rb");
        if (fp_apps) |f| {
            _ = fclose(f);
        } else {
            _ = win32.rescanApps(allocator) catch {};
        }
    }

    std.debug.print("[Jarvis] Ready. Speak into microphone or type in console.\n", .{});
    std.debug.print("[Jarvis] (Type 'help' for full command list, 'exit'/'quit' to stop)\n\n", .{});

    // 7. Interactive REPL loop
    var line_buf: [4096]u8 = undefined;
    var prompt_shown: bool = false;
    while (!tray_mod.should_exit.load(.acquire)) {
        if (!prompt_shown) {
            std.debug.print("[User]: ", .{});
            prompt_shown = true;
        }
        const line = readStdinLine(&line_buf);
        if (line == null) {
            // Keep assistant alive in background/tray mode even if stdin stream is inactive
            sleepMs(250);
            continue;
        }
        prompt_shown = false;

        if (tray_mod.should_exit.load(.acquire)) break;

        const trimmed = std.mem.trim(u8, line.?, " \r\n\t");
        if (trimmed.len == 0) continue;

        if (std.mem.eql(u8, trimmed, "exit") or std.mem.eql(u8, trimmed, "quit")) {
            std.debug.print("\n[Jarvis] Выключение. До свидания!\n", .{});
            tts_engine.speakAsync("Выключение. До свидания!");
            tray_mod.should_exit.store(true, .release);
            break;
        }

        if (std.mem.eql(u8, trimmed, "help") or std.mem.eql(u8, trimmed, "/help") or std.mem.eql(u8, trimmed, "?") or std.mem.eql(u8, trimmed, "команды")) {
            printHelp();
            tts_engine.speakAsync("Вот полный список доступных команд и возможностей.");
            continue;
        }

        global_app.busy_lock.lock();
        const reply = router.processUserText(trimmed) catch |err| {
            global_app.busy_lock.unlock();
            std.debug.print("[Jarvis Error]: Failed to get response: {any}\n", .{err});
            continue;
        };
        global_app.busy_lock.unlock();

        std.debug.print("[Jarvis]: {s}\n\n", .{reply});
        tts_engine.speakAsync(reply);
    }
}

