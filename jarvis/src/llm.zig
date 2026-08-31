const std = @import("std");

pub const SystemPrompt =
    \\Ты — Джарвис, высокоэффективный голосовой ИИ-ассистент для Windows.
    \\Твоя задача — мгновенно выполнять команды пользователя или отвечать на вопросы кратко, вежливо и по делу.
    \\Когда пользователь просит выполнить системное действие (изменить звук, переключить трек, заблокировать ПК, переключить окно, запустить программу), ты ОБЯЗАН использовать соответствующий вызов инструмента (tool_call).
    \\Отвечай на русском языке кратко (1-2 предложения), без лишней воды.
;

const c_net = struct {
    extern fn socket(domain: c_int, typ: c_int, protocol: c_int) c_int;
    extern fn connect(sockfd: c_int, addr: ?*const anyopaque, addrlen: u32) c_int;
    extern fn send(sockfd: c_int, buf: [*]const u8, len: usize, flags: c_int) isize;
    extern fn recv(sockfd: c_int, buf: [*]u8, len: usize, flags: c_int) isize;
    extern fn close(fd: c_int) c_int;
    extern fn inet_addr(cp: [*:0]const u8) u32;
    extern fn htons(hostshort: u16) u16;
};

const SockAddrIn = extern struct {
    sin_family: u16 = 2, // AF_INET
    sin_port: u16,
    sin_addr: u32,
    sin_zero: [8]u8 = [_]u8{0} ** 8,
};

pub const FunctionCall = struct {
    name: []const u8,
    arguments: []const u8,
};

pub const ToolCall = struct {
    id: []const u8,
    type: []const u8 = "function",
    function: FunctionCall,
};

pub const Message = struct {
    role: []const u8,
    content: ?[]const u8 = null,
    tool_calls: ?[]ToolCall = null,
    tool_call_id: ?[]const u8 = null,
};

pub const Choice = struct {
    message: Message,
    finish_reason: ?[]const u8 = null,
};

pub const ChatResponse = struct {
    choices: []Choice,
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
    \\      "description": "Set system master audio volume or mute state on Windows.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "level": { "type": "number", "description": "Volume scalar from 0.0 to 1.0", "minimum": 0.0, "maximum": 1.0 },
    \\          "mute": { "type": "boolean", "description": "Optional mute flag" }
    \\        },
    \\        "required": ["level"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "lock_workstation",
    \\      "description": "Immediately lock the Windows workstation / user session.",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "media_key",
    \\      "description": "Send a multimedia hardware key event (play_pause, next, prev, vol_up, vol_down, mute).",
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
    \\      "name": "focus_window",
    \\      "description": "Bring an active application window to the foreground by title substring.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "title_contains": { "type": "string", "description": "Substring of window title" }
    \\        },
    \\        "required": ["title_contains"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "open_app",
    \\      "description": "Launch or open an application or executable.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "path": { "type": "string", "description": "Executable or shell URI (e.g. 'notepad', 'calc', 'msedge')" },
    \\          "args": { "type": "string", "description": "Optional command line arguments" }
    \\        },
    \\        "required": ["path"]
    \\      }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "get_system_info",
    \\      "description": "Get current operating system, hardware architecture, and current date/time.",
    \\      "parameters": { "type": "object", "properties": {} }
    \\    }
    \\  },
    \\  {
    \\    "type": "function",
    \\    "function": {
    \\      "name": "run_command",
    \\      "description": "Execute a shell / terminal command and return the output.",
    \\      "parameters": {
    \\        "type": "object",
    \\        "properties": {
    \\          "command": { "type": "string", "description": "Shell command line to execute" }
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

    pub fn complete(self: *const Client, allocator: std.mem.Allocator, history: []const Message) !std.json.Parsed(ChatResponse) {
        // Build JSON request body
        var msg_buf: std.ArrayList(u8) = .empty;
        defer msg_buf.deinit(allocator);

        for (history, 0..) |msg, i| {
            if (i > 0) try msg_buf.appendSlice(allocator, ",");

            if (msg.tool_calls) |tcs| {
                var tc_buf: std.ArrayList(u8) = .empty;
                defer tc_buf.deinit(allocator);
                for (tcs, 0..) |tc, ti| {
                    if (ti > 0) try tc_buf.appendSlice(allocator, ",");
                    const tc_str = try std.fmt.allocPrint(allocator,
                        "{{\"id\":\"{s}\",\"type\":\"function\",\"function\":{{\"name\":\"{s}\",\"arguments\":\"{s}\"}}}}",
                        .{ tc.id, tc.function.name, tc.function.arguments },
                    );
                    defer allocator.free(tc_str);
                    try tc_buf.appendSlice(allocator, tc_str);
                }
                const m_str = try std.fmt.allocPrint(allocator,
                    "{{\"role\":\"{s}\",\"content\":null,\"tool_calls\":[{s}]}}",
                    .{ msg.role, tc_buf.items },
                );
                defer allocator.free(m_str);
                try msg_buf.appendSlice(allocator, m_str);
            } else if (msg.tool_call_id) |tid| {
                const cnt = msg.content orelse "ok";
                const m_str = try std.fmt.allocPrint(allocator,
                    "{{\"role\":\"{s}\",\"content\":\"{s}\",\"tool_call_id\":\"{s}\"}}",
                    .{ msg.role, cnt, tid },
                );
                defer allocator.free(m_str);
                try msg_buf.appendSlice(allocator, m_str);
            } else {
                const cnt = msg.content orelse "";
                const m_str = try std.fmt.allocPrint(allocator,
                    "{{\"role\":\"{s}\",\"content\":\"{s}\"}}",
                    .{ msg.role, cnt },
                );
                defer allocator.free(m_str);
                try msg_buf.appendSlice(allocator, m_str);
            }
        }

        const json_payload = try std.fmt.allocPrint(allocator,
            "{{\"model\":\"{s}\",\"temperature\":{d:.2},\"stream\":false,\"tool_choice\":\"auto\",\"tools\":{s},\"messages\":[{s}]}}",
            .{ self.config.model_name, self.config.temperature, TOOLS_SCHEMA_JSON, msg_buf.items },
        );
        defer allocator.free(json_payload);

        // Perform TCP HTTP Request via standard socket
        const sockfd = c_net.socket(2, 1, 0); // AF_INET, SOCK_STREAM
        if (sockfd < 0) return error.SocketCreateFailed;
        defer _ = c_net.close(sockfd);

        var host_z: [256:0]u8 = undefined;
        @memcpy(host_z[0..self.config.host.len], self.config.host);
        host_z[self.config.host.len] = 0;

        const sa = SockAddrIn{
            .sin_port = c_net.htons(self.config.port),
            .sin_addr = c_net.inet_addr(&host_z),
        };

        if (c_net.connect(sockfd, @ptrCast(&sa), @sizeOf(SockAddrIn)) != 0) {
            return error.ConnectionRefused;
        }

        var header_buf: [512]u8 = undefined;
        const header = try std.fmt.bufPrint(&header_buf,
            "POST {s} HTTP/1.1\r\nHost: {s}:{d}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ self.config.path, self.config.host, self.config.port, json_payload.len },
        );

        _ = c_net.send(sockfd, header.ptr, header.len, 0);
        _ = c_net.send(sockfd, json_payload.ptr, json_payload.len, 0);

        var response_list: std.ArrayList(u8) = .empty;
        defer response_list.deinit(allocator);

        var read_buf: [4096]u8 = undefined;
        while (true) {
            const n = c_net.recv(sockfd, &read_buf, read_buf.len, 0);
            if (n <= 0) break;
            try response_list.appendSlice(allocator, read_buf[0..@as(usize, @intCast(n))]);
        }

        const full_resp = response_list.items;
        const body = if (std.mem.indexOf(u8, full_resp, "\r\n\r\n")) |idx|
            full_resp[idx + 4 ..]
        else
            full_resp;

        return std.json.parseFromSlice(ChatResponse, allocator, body, .{
            .ignore_unknown_fields = true,
        });
    }
};
