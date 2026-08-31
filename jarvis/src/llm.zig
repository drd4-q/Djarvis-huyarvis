const std = @import("std");
const builtin = @import("builtin");

pub const SystemPrompt =
    \\Ты — Джарвис, умный голосовой ИИ-ассистент для Windows со зрением экрана и прямым управлением ПК.
    \\Твоя задача — мгновенно выполнять команды пользователя или отвечать на вопросы кратко, вежливо и естественно.
    \\Твои ответы озвучиваются голосом вслух:
    \\1. Говори простым разговорным языком (1-2 емких предложения), без markdown-разметки (*, #, списки).
    \\2. Не зачитывай вслух сырые веб-ссылки и URL (вместо длинных ссылок говори 'Открываю YouTube', 'Открываю ВКонтакте', 'Ищу в Google').
    \\3. Категорически запрещено выдумывать punycode-домены вроде 'xn--...'. Всегда используй стандартные названия сервисов и чистые домены (youtube.com, google.com).
    \\4. При системных действиях (запуск программ, поиск в интернете, управление звуком, зрение экрана) всегда вызывай соответствующий инструмент (tool_call).
;

const win_sock = if (builtin.os.tag == .windows) @cImport({
    @cInclude("winsock2.h");
    @cInclude("ws2tcpip.h");
}) else struct {};

pub const FunctionCall = struct {
    name: []const u8 = "",
    arguments: []const u8 = "{}",
};

pub const ToolCall = struct {
    id: []const u8 = "",
    type: []const u8 = "function",
    function: FunctionCall = .{},
};

pub const Message = struct {
    role: []const u8 = "assistant",
    content: ?[]const u8 = null,
    tool_calls: ?[]ToolCall = null,
    tool_call_id: ?[]const u8 = null,
};

pub const Choice = struct {
    message: Message = .{},
    finish_reason: ?[]const u8 = null,
    index: ?usize = null,
};

pub const ChatResponse = struct {
    choices: []Choice = &.{},
    id: ?[]const u8 = null,
    object: ?[]const u8 = null,
    created: ?i64 = null,
    model: ?[]const u8 = null,
};

pub const Config = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    path: []const u8 = "/v1/chat/completions",
    model_name: []const u8 = "qwen2.5-3b-instruct",
    temperature: f32 = 0.1,
};

pub const TOOLS_SCHEMA_JSON =
    \\[
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "set_volume",
    \\      "description": "Set master system volume (0.0 to 1.0) or mute.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "level": { "type": "number", "description": "Volume scalar 0.0 to 1.0" },
    \\          "mute": { "type": "boolean", "description": "Optional mute state" }
    \\        },
    \\        "required": ["level"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "media_key",
    \\      "description": "Control playback: play_pause, next, prev, vol_up, vol_down, mute.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "key": { "type": "string", "enum": ["play_pause", "next", "prev", "vol_up", "vol_down", "mute"] }
    \\        },
    \\        "required": ["key"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "open_app",
    \\      "description": "Open any installed application or program by name from the app database (e.g. 'discord', 'telegram', 'chrome', 'steam', 'obs', 'vscode', 'яндекс музыка', 'notepad', 'calc', 'taskmgr', 'paint', 'settings').",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "path": { "type": "string", "description": "App name or keyword (e.g. 'discord', 'telegram', 'steam', 'chrome')" },
    \\          "args": { "type": "string", "description": "Optional arguments" }
    \\        },
    \\        "required": ["path"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "rescan_apps",
    \\      "description": "Scan and refresh the local database of all installed programs on the computer.",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "set_vad_sensitivity",
    \\      "description": "Adjust microphone / Whisper VAD speech detection threshold (sensitivity level from 100 to 1000). Lower is more sensitive.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "sensitivity": { "type": "integer", "description": "VAD sensitivity value (e.g. 200 for sensitive/quiet voice, 400 for standard, 700 for noisy background)" }
    \\        },
    \\        "required": ["sensitivity"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "open_url",
    \\      "description": "Open website URL in default browser (e.g. 'https://youtube.com', 'https://github.com').",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "url": { "type": "string", "description": "Full URL" }
    \\        },
    \\        "required": ["url"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "search_web",
    \\      "description": "Search the internet via browser (Google).",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "query": { "type": "string", "description": "Search query" }
    \\        },
    \\        "required": ["query"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "fetch_web_info",
    \\      "description": "Fetch live online knowledge, encyclopedic facts, and web summaries for a query without opening the browser.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "query": { "type": "string", "description": "Topic or search query" }
    \\        },
    \\        "required": ["query"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "read_webpage_content",
    \\      "description": "Read and extract clean text content from any website or URL.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "url": { "type": "string", "description": "Website URL to read" }
    \\        },
    \\        "required": ["url"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "look_at_screen",
    \\      "description": "Capture the user's computer screen and analyze what is visible using SmolVLM vision model.",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "minimize_all",
    \\      "description": "Minimize all open windows and show the Desktop (Win+D).",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "close_active_window",
    \\      "description": "Close currently active window (Alt+F4).",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "focus_window",
    \\      "description": "Bring an open window to the front by title name.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "title_contains": { "type": "string", "description": "Window title" }
    \\        },
    \\        "required": ["title_contains"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "lock_workstation",
    \\      "description": "Lock Windows screen immediately.",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "shutdown_pc",
    \\      "description": "Turn off or restart computer.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "restart": { "type": "boolean", "description": "True for restart, false for shutdown" },
    \\          "delay_sec": { "type": "integer", "description": "Delay in seconds" }
    \\        }
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "cancel_shutdown",
    \\      "description": "Cancel scheduled shutdown or restart.",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "sleep_pc",
    \\      "description": "Put PC into sleep mode.",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "empty_recycle_bin",
    \\      "description": "Clean / empty Windows Recycle Bin.",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "take_screenshot",
    \\      "description": "Take full screen screenshot and save to Pictures.",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "get_battery_status",
    \\      "description": "Check battery percentage and charging status.",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "get_system_info",
    \\      "description": "Get current time, RAM usage, and OS status.",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "press_key",
    \\      "description": "Press keyboard hotkey (e.g. 'alt+tab', 'ctrl+c', 'ctrl+v', 'enter', 'space').",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "key": { "type": "string", "description": "Key name or combination" }
    \\        },
    \\        "required": ["key"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "run_command",
    \\      "description": "Execute a shell command in Windows.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "command": { "type": "string", "description": "Command to run" }
    \\        },
    \\        "required": ["command"]
    \\      }
    \\    }
    \\  }
    \\]
;

pub const Client = struct {
    config: Config,

    pub fn init(cfg: Config) Client {
        return .{ .config = cfg };
    }

    fn appendJsonEscaped(out: *std.ArrayList(u8), allocator: std.mem.Allocator, s: []const u8) !void {
        try out.append(allocator, '"');
        var i: usize = 0;
        while (i < s.len) {
            const byte_len = std.unicode.utf8ByteSequenceLength(s[i]) catch {
                i += 1;
                continue;
            };
            if (i + byte_len > s.len) break;

            if (byte_len == 1) {
                const c = s[i];
                switch (c) {
                    '"' => try out.appendSlice(allocator, "\\\""),
                    '\\' => try out.appendSlice(allocator, "\\\\"),
                    '\n' => try out.appendSlice(allocator, "\\n"),
                    '\r' => try out.appendSlice(allocator, "\\r"),
                    '\t' => try out.appendSlice(allocator, "\\t"),
                    else => {
                        if (c < 0x20) {
                            var hex_buf: [8]u8 = undefined;
                            const hex = try std.fmt.bufPrint(&hex_buf, "\\u{x:0>4}", .{c});
                            try out.appendSlice(allocator, hex);
                        } else {
                            try out.append(allocator, c);
                        }
                    },
                }
                i += 1;
            } else {
                const slice = s[i .. i + byte_len];
                if (std.unicode.utf8ValidateSlice(slice)) {
                    try out.appendSlice(allocator, slice);
                }
                i += byte_len;
            }
        }
        try out.append(allocator, '"');
    }

    pub fn complete(self: *const Client, allocator: std.mem.Allocator, history: []const Message) !std.json.Parsed(ChatResponse) {
        // Build JSON request body
        var msg_buf: std.ArrayList(u8) = .empty;
        defer msg_buf.deinit(allocator);

        for (history, 0..) |msg, i| {
            if (i > 0) try msg_buf.appendSlice(allocator, ",");

            if (msg.tool_calls) |tcs| {
                try msg_buf.appendSlice(allocator, "{\"role\":");
                try appendJsonEscaped(&msg_buf, allocator, msg.role);
                try msg_buf.appendSlice(allocator, ",\"content\":null,\"tool_calls\":[");
                for (tcs, 0..) |tc, ti| {
                    if (ti > 0) try msg_buf.appendSlice(allocator, ",");
                    try msg_buf.appendSlice(allocator, "{\"id\":");
                    try appendJsonEscaped(&msg_buf, allocator, tc.id);
                    try msg_buf.appendSlice(allocator, ",\"type\":\"function\",\"function\":{\"name\":");
                    try appendJsonEscaped(&msg_buf, allocator, tc.function.name);
                    try msg_buf.appendSlice(allocator, ",\"arguments\":");
                    try appendJsonEscaped(&msg_buf, allocator, tc.function.arguments);
                    try msg_buf.appendSlice(allocator, "}}");
                }
                try msg_buf.appendSlice(allocator, "]}");
            } else if (msg.tool_call_id) |tid| {
                try msg_buf.appendSlice(allocator, "{\"role\":");
                try appendJsonEscaped(&msg_buf, allocator, msg.role);
                try msg_buf.appendSlice(allocator, ",\"tool_call_id\":");
                try appendJsonEscaped(&msg_buf, allocator, tid);
                try msg_buf.appendSlice(allocator, ",\"content\":");
                try appendJsonEscaped(&msg_buf, allocator, msg.content orelse "ok");
                try msg_buf.appendSlice(allocator, "}");
            } else {
                try msg_buf.appendSlice(allocator, "{\"role\":");
                try appendJsonEscaped(&msg_buf, allocator, msg.role);
                try msg_buf.appendSlice(allocator, ",\"content\":");
                try appendJsonEscaped(&msg_buf, allocator, msg.content orelse "");
                try msg_buf.appendSlice(allocator, "}");
            }
        }

        const json_payload = try std.fmt.allocPrint(allocator,
            "{{\"model\":\"{s}\",\"temperature\":{d:.2},\"stream\":false,\"tool_choice\":\"auto\",\"tools\":{s},\"messages\":[{s}]}}",
            .{ self.config.model_name, self.config.temperature, TOOLS_SCHEMA_JSON, msg_buf.items },
        );
        defer allocator.free(json_payload);

        // Perform TCP HTTP Request via Windows Sockets / POSIX
        if (builtin.os.tag == .windows) {
            var wd: win_sock.WSADATA = undefined;
            _ = win_sock.WSAStartup(0x0202, &wd);
        }

        const sockfd = if (builtin.os.tag == .windows)
            win_sock.socket(win_sock.AF_INET, win_sock.SOCK_STREAM, win_sock.IPPROTO_TCP)
        else
            std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch -1;

        if (builtin.os.tag == .windows) {
            if (sockfd == win_sock.INVALID_SOCKET) return error.SocketCreateFailed;
        } else {
            if (sockfd < 0) return error.SocketCreateFailed;
        }

        defer {
            if (builtin.os.tag == .windows) {
                _ = win_sock.closesocket(sockfd);
            } else {
                std.posix.close(sockfd);
            }
        }

        if (builtin.os.tag == .windows) {
            var sa: win_sock.sockaddr_in = std.mem.zeroes(win_sock.sockaddr_in);
            sa.sin_family = win_sock.AF_INET;
            sa.sin_port = win_sock.htons(self.config.port);

            var host_z: [256:0]u8 = undefined;
            @memcpy(host_z[0..self.config.host.len], self.config.host);
            host_z[self.config.host.len] = 0;

            _ = win_sock.InetPtonA(win_sock.AF_INET, &host_z, &sa.sin_addr);

            if (win_sock.connect(sockfd, @ptrCast(&sa), @sizeOf(win_sock.sockaddr_in)) != 0) {
                std.debug.print("[LLM Error] Connect failed to {s}:{d} (WSA error: {d})\n", .{ self.config.host, self.config.port, win_sock.WSAGetLastError() });
                return error.ConnectionRefused;
            }
        }

        var header_buf: [512]u8 = undefined;
        const header = try std.fmt.bufPrint(&header_buf,
            "POST {s} HTTP/1.1\r\nHost: {s}:{d}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ self.config.path, self.config.host, self.config.port, json_payload.len },
        );

        if (builtin.os.tag == .windows) {
            _ = win_sock.send(sockfd, header.ptr, @as(c_int, @intCast(header.len)), 0);
            _ = win_sock.send(sockfd, json_payload.ptr, @as(c_int, @intCast(json_payload.len)), 0);
        }

        var response_list: std.ArrayList(u8) = .empty;
        defer response_list.deinit(allocator);

        var read_buf: [4096]u8 = undefined;
        while (true) {
            const n = if (builtin.os.tag == .windows)
                win_sock.recv(sockfd, &read_buf, @as(c_int, @intCast(read_buf.len)), 0)
            else
                std.posix.read(sockfd, &read_buf) catch 0;

            if (n <= 0) break;
            try response_list.appendSlice(allocator, read_buf[0..@as(usize, @intCast(n))]);
        }

        const full_resp = response_list.items;
        const body = if (std.mem.indexOf(u8, full_resp, "\r\n\r\n")) |idx|
            full_resp[idx + 4 ..]
        else
            full_resp;

        const parsed = try std.json.parseFromSlice(ChatResponse, allocator, body, .{
            .ignore_unknown_fields = true,
        });

        if (parsed.value.choices.len == 0) {
            std.debug.print("[LLM Error] Server response has no choices: {s}\n", .{body});
            parsed.deinit();
            return error.NoChoicesReturned;
        }

        return parsed;
    }
};
