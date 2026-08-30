const std = @import("std");
const builtin = @import("builtin");
const ipc = @import("ipc_protocol.zig");
const win32 = @import("win32.zig");
const audio = @import("audio.zig");
const c = @import("c.zig").c;

const PIPE_NAME = "\\\\.\\pipe\\jarvis_ipc";
const UNIX_SOCKET_PATH = "/tmp/jarvis_ipc.sock";

fn sleepMs(ms: u32) void {
    if (builtin.os.tag == .windows) {
        c.Sleep(ms);
    } else {
        _ = c.usleep(ms * 1000);
    }
}

const ActionRequest = struct {
    id: []const u8,
    action: []const u8,
    params: ?std.json.Value = null,
};

// Global context for audio capture streaming over IPC
const AppState = struct {
    pipe_handle: ?ipc.HandleType = null,
    write_lock: audio.SpinLock = .{},
    audio_engine: audio.AudioEngine = .{},
    is_connected: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

var global_app: AppState = .{};

fn onMicCapture(chunk: []const u8, user_data: ?*anyopaque) void {
    _ = user_data;
    if (!global_app.is_connected.load(.acquire)) return;

    global_app.write_lock.lock();
    defer global_app.write_lock.unlock();

    if (global_app.pipe_handle) |h| {
        ipc.writePacket(h, .audio_in_chunk, chunk) catch {
            // Write failed, pipe might be closing
        };
    }
}

fn sendResult(handle: ipc.HandleType, id: []const u8, status: []const u8, err_msg: ?[]const u8) !void {
    var out_buf: [1024]u8 = undefined;
    const json_str = if (err_msg) |em|
        try std.fmt.bufPrint(&out_buf, "{{\"id\":\"{s}\",\"status\":\"{s}\",\"error\":\"{s}\"}}", .{ id, status, em })
    else
        try std.fmt.bufPrint(&out_buf, "{{\"id\":\"{s}\",\"status\":\"{s}\"}}", .{ id, status });

    global_app.write_lock.lock();
    defer global_app.write_lock.unlock();
    try ipc.writePacket(handle, .action_result, json_str);
}

fn executeAction(handle: ipc.HandleType, allocator: std.mem.Allocator, payload: []const u8) !void {
    const parsed = std.json.parseFromSlice(ActionRequest, allocator, payload, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        std.debug.print("[Core] JSON parse error: {any}\n", .{err});
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;
    std.debug.print("[Core] Executing action: {s} (id: {s})\n", .{ req.action, req.id });

    var exec_err: ?[]const u8 = null;

    if (std.mem.eql(u8, req.action, "set_volume")) {
        var level: f32 = 0.5;
        var mute: ?bool = null;

        if (req.params) |p| {
            if (p == .object) {
                if (p.object.get("level")) |lvl| {
                    if (lvl == .float) level = @floatCast(lvl.float);
                    if (lvl == .integer) level = @floatFromInt(lvl.integer);
                }
                if (p.object.get("mute")) |m| {
                    if (m == .bool) mute = m.bool;
                }
            }
        }
        win32.setVolume(level, mute) catch {
            exec_err = "failed to set volume";
        };
    } else if (std.mem.eql(u8, req.action, "lock_workstation")) {
        win32.lockWorkstation() catch {
            exec_err = "failed to lock workstation";
        };
    } else if (std.mem.eql(u8, req.action, "media_key")) {
        var key: win32.MediaKey = .play_pause;
        if (req.params) |p| {
            if (p == .object) {
                if (p.object.get("key")) |k| {
                    if (k == .string) {
                        if (std.mem.eql(u8, k.string, "play_pause")) key = .play_pause
                        else if (std.mem.eql(u8, k.string, "next")) key = .next
                        else if (std.mem.eql(u8, k.string, "prev")) key = .prev
                        else if (std.mem.eql(u8, k.string, "vol_up")) key = .vol_up
                        else if (std.mem.eql(u8, k.string, "vol_down")) key = .vol_down
                        else if (std.mem.eql(u8, k.string, "mute")) key = .mute;
                    }
                }
            }
        }
        win32.sendMediaKey(key) catch {
            exec_err = "failed to send media key";
        };
    } else if (std.mem.eql(u8, req.action, "focus_window")) {
        var title: []const u8 = "";
        if (req.params) |p| {
            if (p == .object) {
                if (p.object.get("title_contains")) |t| {
                    if (t == .string) title = t.string;
                }
            }
        }
        win32.focusWindow(allocator, title) catch {
            exec_err = "window not found or focus failed";
        };
    } else if (std.mem.eql(u8, req.action, "open_app")) {
        var path: []const u8 = "";
        var args: ?[]const u8 = null;
        if (req.params) |p| {
            if (p == .object) {
                if (p.object.get("path")) |pt| {
                    if (pt == .string) path = pt.string;
                }
                if (p.object.get("args")) |ag| {
                    if (ag == .string) args = ag.string;
                }
            }
        }
        win32.openApp(allocator, path, args) catch {
            exec_err = "failed to launch app";
        };
    } else {
        exec_err = "unknown action";
    }

    if (exec_err) |em| {
        try sendResult(handle, req.id, "error", em);
    } else {
        try sendResult(handle, req.id, "ok", null);
    }
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    std.debug.print("==================================================\n", .{});
    std.debug.print(" Jarvis Core (Native Engine: Zig 0.16.0 + Miniaudio)\n", .{});
    std.debug.print("==================================================\n", .{});

    // Initialize Miniaudio subsystem (Capture 16kHz & Playback 24kHz)
    std.debug.print("[Audio] Initializing audio devices...\n", .{});
    global_app.audio_engine.init(onMicCapture, null) catch |err| {
        std.debug.print("[Audio] Warning: Audio init failed ({any}), running in action-only mode\n", .{err});
    };
    defer global_app.audio_engine.deinit();

    global_app.audio_engine.start() catch |err| {
        std.debug.print("[Audio] Warning: Audio start failed ({any})\n", .{err});
    };

    // Outer reconnect loop for IPC Named Pipe
    while (true) {
        std.debug.print("[Core] Connecting to Hub IPC...\n", .{});

        var handle_opt: ?ipc.HandleType = null;

        if (builtin.os.tag == .windows) {
            const pipe_w = std.unicode.utf8ToUtf16LeStringLiteral(PIPE_NAME);
            const handle = c.CreateFileW(
                pipe_w,
                c.GENERIC_READ | c.GENERIC_WRITE,
                0,
                null,
                c.OPEN_EXISTING,
                0,
                null,
            );

            if (handle != c.INVALID_HANDLE_VALUE) {
                handle_opt = handle;
            }
        } else {
            const sock_fd = c.socket(c.AF_UNIX, c.SOCK_STREAM, 0);
            if (sock_fd >= 0) {
                var addr: c.struct_sockaddr_un = std.mem.zeroes(c.struct_sockaddr_un);
                addr.sun_family = c.AF_UNIX;
                @memcpy(addr.sun_path[0..UNIX_SOCKET_PATH.len], UNIX_SOCKET_PATH);
                addr.sun_path[UNIX_SOCKET_PATH.len] = 0;

                const ret = c.connect(sock_fd, @as(*const c.struct_sockaddr, @ptrCast(&addr)), @sizeOf(c.struct_sockaddr_un));
                if (ret == 0) {
                    handle_opt = sock_fd;
                } else {
                    _ = c.close(sock_fd);
                }
            }
        }

        if (handle_opt == null) {
            sleepMs(1000);
            continue;
        }

        const handle = handle_opt.?;
        defer {
            if (builtin.os.tag == .windows) {
                _ = c.CloseHandle(handle);
            } else {
                _ = c.close(handle);
            }
        }

        global_app.write_lock.lock();
        global_app.pipe_handle = handle;
        global_app.is_connected.store(true, .release);
        global_app.write_lock.unlock();

        std.debug.print("[Core] Connected to Hub IPC successfully.\n", .{});

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        // Inner frame processing loop
        while (true) {
            _ = arena.reset(.retain_capacity);
            const frame_allocator = arena.allocator();

            var packet = ipc.readPacket(handle, frame_allocator) catch |err| {
                std.debug.print("[Core] IPC disconnected ({any}), will reconnect...\n", .{err});
                break;
            };
            defer packet.deinit(frame_allocator);

            switch (packet.msg_type) {
                .ping => {
                    global_app.write_lock.lock();
                    ipc.writePacket(handle, .pong, "") catch {
                        global_app.write_lock.unlock();
                        break;
                    };
                    global_app.write_lock.unlock();
                },
                .pong => {},
                .exec_action => {
                    executeAction(handle, frame_allocator, packet.payload) catch |err| {
                        std.debug.print("[Core] Action execution error: {any}\n", .{err});
                    };
                },
                .audio_out_chunk => {
                    // Push synthesized audio chunk into real-time ring buffer
                    global_app.audio_engine.pushPlaybackChunk(packet.payload);
                },
                .audio_out_stop => {
                    // Immediate barge-in interrupt: clear playback ring buffer
                    global_app.audio_engine.stopPlaybackImmediate();
                },
                else => {
                    std.debug.print("[Core] Unhandled message type: {any}\n", .{packet.msg_type});
                },
            }
        }

        global_app.write_lock.lock();
        global_app.is_connected.store(false, .release);
        global_app.pipe_handle = null;
        global_app.write_lock.unlock();

        sleepMs(1000);
    }
}
