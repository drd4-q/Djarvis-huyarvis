const std = @import("std");
const llm = @import("llm.zig");
const win32 = @import("win32.zig");

pub const Router = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    history: std.ArrayList(llm.Message),
    client: llm.Client,
    max_turns: usize = 10,

    pub fn init(allocator: std.mem.Allocator, client: llm.Client) Router {
        var r = Router{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .history = .empty,
            .client = client,
            .max_turns = 10,
        };
        r.resetHistory();
        return r;
    }

    pub fn deinit(self: *Router) void {
        self.history.deinit(self.allocator);
        self.arena.deinit();
    }

    pub fn resetHistory(self: *Router) void {
        _ = self.arena.reset(.retain_capacity);
        self.history.clearRetainingCapacity();
        self.history.append(self.allocator, .{
            .role = "system",
            .content = llm.SystemPrompt,
        }) catch unreachable;
    }

    fn executeTool(self: *Router, name: []const u8, args_json: []const u8) []const u8 {
        const arena_alloc = self.arena.allocator();
        std.debug.print("[Router] Executing native action: {s} (args: {s})\n", .{ name, args_json });

        var parsed_args_opt: ?std.json.Parsed(std.json.Value) = null;
        if (args_json.len > 0) {
            parsed_args_opt = std.json.parseFromSlice(std.json.Value, arena_alloc, args_json, .{}) catch null;
        }

        var exec_err: ?[]const u8 = null;

        if (std.mem.eql(u8, name, "set_volume")) {
            var level: f32 = 0.5;
            var mute: ?bool = null;
            if (parsed_args_opt) |p| {
                if (p.value == .object) {
                    if (p.value.object.get("level")) |lvl| {
                        if (lvl == .float) level = @floatCast(lvl.float);
                        if (lvl == .integer) level = @floatFromInt(lvl.integer);
                    }
                    if (p.value.object.get("mute")) |m| {
                        if (m == .bool) mute = m.bool;
                    }
                }
            }
            win32.setVolume(level, mute) catch {
                exec_err = "failed to set volume";
            };
        } else if (std.mem.eql(u8, name, "media_key")) {
            var key: win32.MediaKey = .play_pause;
            if (parsed_args_opt) |p| {
                if (p.value == .object) {
                    if (p.value.object.get("key")) |k| {
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
        } else if (std.mem.eql(u8, name, "open_app")) {
            var path: []const u8 = "";
            var args: ?[]const u8 = null;
            if (parsed_args_opt) |p| {
                if (p.value == .object) {
                    if (p.value.object.get("path")) |pt| {
                        if (pt == .string) path = pt.string;
                    }
                    if (p.value.object.get("args")) |ag| {
                        if (ag == .string) args = ag.string;
                    }
                }
            }
            if (args != null and args.?.len > 0) {
                win32.openApp(arena_alloc, path, args) catch {
                    exec_err = "failed to launch app";
                };
            } else {
                return win32.openAppByName(arena_alloc, path) catch "не удалось запустить программу";
            }
        } else if (std.mem.eql(u8, name, "rescan_apps")) {
            return win32.rescanApps(arena_alloc) catch "не удалось обновить базу программ";
        } else if (std.mem.eql(u8, name, "open_url")) {
            var url: []const u8 = "";
            if (parsed_args_opt) |p| {
                if (p.value == .object) {
                    if (p.value.object.get("url")) |u| {
                        if (u == .string) url = u.string;
                    }
                }
            }
            win32.openUrl(arena_alloc, url) catch {
                exec_err = "failed to open url";
            };
        } else if (std.mem.eql(u8, name, "search_web")) {
            var query: []const u8 = "";
            if (parsed_args_opt) |p| {
                if (p.value == .object) {
                    if (p.value.object.get("query")) |q| {
                        if (q == .string) query = q.string;
                    }
                }
            }
            win32.searchWeb(arena_alloc, query) catch {
                exec_err = "failed to search web";
            };
        } else if (std.mem.eql(u8, name, "fetch_web_info")) {
            var query: []const u8 = "";
            if (parsed_args_opt) |p| {
                if (p.value == .object) {
                    if (p.value.object.get("query")) |q| {
                        if (q == .string) query = q.string;
                    }
                }
            }
            return win32.fetchWebSummary(arena_alloc, query) catch "не удалось получить информацию из интернета";
        } else if (std.mem.eql(u8, name, "read_webpage_content")) {
            var url: []const u8 = "";
            if (parsed_args_opt) |p| {
                if (p.value == .object) {
                    if (p.value.object.get("url")) |u| {
                        if (u == .string) url = u.string;
                    }
                }
            }
            return win32.readWebpageContent(arena_alloc, url) catch "не удалось прочитать содержимое страницы";
        } else if (std.mem.eql(u8, name, "look_at_screen")) {
            return win32.lookAtScreen(arena_alloc) catch "не удалось проанализировать экран";
        } else if (std.mem.eql(u8, name, "minimize_all")) {
            win32.minimizeAll() catch {
                exec_err = "failed to minimize all";
            };
        } else if (std.mem.eql(u8, name, "close_active_window")) {
            win32.closeActiveWindow() catch {
                exec_err = "failed to close active window";
            };
        } else if (std.mem.eql(u8, name, "focus_window")) {
            var title: []const u8 = "";
            if (parsed_args_opt) |p| {
                if (p.value == .object) {
                    if (p.value.object.get("title_contains")) |t| {
                        if (t == .string) title = t.string;
                    }
                }
            }
            win32.focusWindow(arena_alloc, title) catch {
                exec_err = "window not found";
            };
        } else if (std.mem.eql(u8, name, "lock_workstation")) {
            win32.lockWorkstation() catch {
                exec_err = "failed to lock workstation";
            };
        } else if (std.mem.eql(u8, name, "shutdown_pc")) {
            var restart = false;
            var delay: u32 = 10;
            if (parsed_args_opt) |p| {
                if (p.value == .object) {
                    if (p.value.object.get("restart")) |r| {
                        if (r == .bool) restart = r.bool;
                    }
                    if (p.value.object.get("delay_sec")) |d| {
                        if (d == .integer) delay = @intCast(@max(0, d.integer));
                    }
                }
            }
            win32.shutdownPC(delay, restart) catch {
                exec_err = "failed to shutdown pc";
            };
        } else if (std.mem.eql(u8, name, "cancel_shutdown")) {
            win32.cancelShutdown() catch {
                exec_err = "failed to cancel shutdown";
            };
        } else if (std.mem.eql(u8, name, "sleep_pc")) {
            win32.sleepPC() catch {
                exec_err = "failed to sleep pc";
            };
        } else if (std.mem.eql(u8, name, "empty_recycle_bin")) {
            win32.emptyRecycleBin() catch {
                exec_err = "failed to empty recycle bin";
            };
        } else if (std.mem.eql(u8, name, "take_screenshot")) {
            return win32.takeScreenshot(arena_alloc) catch "failed to take screenshot";
        } else if (std.mem.eql(u8, name, "get_battery_status")) {
            return win32.getBatteryStatus(arena_alloc) catch "failed to get battery status";
        } else if (std.mem.eql(u8, name, "get_system_info")) {
            return win32.getSystemInfo(arena_alloc) catch "failed to retrieve system info";
        } else if (std.mem.eql(u8, name, "press_key")) {
            var key: []const u8 = "";
            if (parsed_args_opt) |p| {
                if (p.value == .object) {
                    if (p.value.object.get("key")) |k| {
                        if (k == .string) key = k.string;
                    }
                }
            }
            win32.pressKeyCombination(key) catch {
                exec_err = "failed to press key";
            };
        } else if (std.mem.eql(u8, name, "run_command")) {
            var cmd: []const u8 = "";
            if (parsed_args_opt) |p| {
                if (p.value == .object) {
                    if (p.value.object.get("command")) |c| {
                        if (c == .string) cmd = c.string;
                    }
                }
            }
            if (cmd.len == 0) {
                exec_err = "empty command";
            } else {
                const out = win32.executeCommand(arena_alloc, cmd) catch {
                    return "error executing command";
                };
                return if (out.len > 0) out else "command executed with no output";
            }
        } else {
            exec_err = "unknown action";
        }

        if (exec_err) |em| {
            return std.fmt.allocPrint(arena_alloc, "error: {s}", .{em}) catch "error";
        }
        return "ok";
    }

    pub fn processUserText(self: *Router, text: []const u8) ![]const u8 {
        const arena_alloc = self.arena.allocator();
        const user_text_dupe = try arena_alloc.dupe(u8, text);

        try self.history.append(self.allocator, .{
            .role = "user",
            .content = user_text_dupe,
        });

        // 1. Initial LLM completion
        var resp1 = try self.client.complete(arena_alloc, self.history.items);
        defer resp1.deinit();

        if (resp1.value.choices.len == 0) {
            return error.NoChoicesReturned;
        }

        const msg1 = resp1.value.choices[0].message;

        // Duplicate response fields into arena so they outlive resp1 deinit
        var persistent_tool_calls: ?[]llm.ToolCall = null;
        if (msg1.tool_calls) |tcs| {
            const tc_slice = try arena_alloc.alloc(llm.ToolCall, tcs.len);
            for (tcs, 0..) |tc, i| {
                tc_slice[i] = .{
                    .id = try arena_alloc.dupe(u8, tc.id),
                    .type = "function",
                    .function = .{
                        .name = try arena_alloc.dupe(u8, tc.function.name),
                        .arguments = try arena_alloc.dupe(u8, tc.function.arguments),
                    },
                };
            }
            persistent_tool_calls = tc_slice;
        }

        const persistent_content = if (msg1.content) |c| try arena_alloc.dupe(u8, c) else null;

        try self.history.append(self.allocator, .{
            .role = "assistant",
            .content = persistent_content,
            .tool_calls = persistent_tool_calls,
        });

        // If tools were called, execute each directly in memory!
        if (persistent_tool_calls) |tcs| {
            for (tcs) |tc| {
                const action_result = self.executeTool(tc.function.name, tc.function.arguments);
                try self.history.append(self.allocator, .{
                    .role = "tool",
                    .content = action_result,
                    .tool_call_id = tc.id,
                });
            }

            // Follow-up LLM completion with tool output
            var resp2 = self.client.complete(arena_alloc, self.history.items) catch {
                self.pruneHistory();
                return persistent_content orelse "Команда выполнена.";
            };
            defer resp2.deinit();

            if (resp2.value.choices.len > 0 and resp2.value.choices[0].message.content != null) {
                const final_cnt = try arena_alloc.dupe(u8, resp2.value.choices[0].message.content.?);
                try self.history.append(self.allocator, .{
                    .role = "assistant",
                    .content = final_cnt,
                });
                self.pruneHistory();
                return sanitizeResponseText(arena_alloc, final_cnt);
            }
        }

        self.pruneHistory();
        if (persistent_content) |c| {
            return sanitizeResponseText(arena_alloc, c);
        }
        return "Слушаю вас.";
    }

    fn sanitizeResponseText(allocator: std.mem.Allocator, input: []const u8) []const u8 {
        const trimmed = std.mem.trim(u8, input, " \r\n\t");
        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "None") or std.mem.eql(u8, trimmed, "null")) {
            return "Слушаю вас.";
        }

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        var i: usize = 0;
        while (i < trimmed.len) {
            // Replace punycode youtube.xn--...
            if (i + 12 <= trimmed.len and (std.ascii.eqlIgnoreCase(trimmed[i .. i + 12], "youtube.xn--") or std.ascii.eqlIgnoreCase(trimmed[i .. i + 12], "youtu.be.xn-"))) {
                out.appendSlice(allocator, "YouTube") catch return trimmed;
                i += 12;
                while (i < trimmed.len and trimmed[i] != '/' and trimmed[i] != ' ' and trimmed[i] != '\n' and trimmed[i] != ')' and trimmed[i] != '.') {
                    i += 1;
                }
                continue;
            }

            // Generic .xn-- replacement
            if (i + 5 <= trimmed.len and std.mem.eql(u8, trimmed[i .. i + 5], ".xn--")) {
                out.appendSlice(allocator, ".com") catch return trimmed;
                i += 5;
                while (i < trimmed.len and trimmed[i] != '/' and trimmed[i] != ' ' and trimmed[i] != '\n' and trimmed[i] != ')' and trimmed[i] != '.') {
                    i += 1;
                }
                continue;
            }

            out.append(allocator, trimmed[i]) catch return trimmed;
            i += 1;
        }

        return out.toOwnedSlice(allocator) catch trimmed;
    }

    fn pruneHistory(self: *Router) void {
        const max_msgs = self.max_turns * 2 + 1;
        if (self.history.items.len > max_msgs) {
            const keep_from = self.history.items.len - (self.max_turns * 2);
            const sys = self.history.items[0];
            const recent = self.history.items[keep_from..];
            var new_hist: std.ArrayList(llm.Message) = .empty;
            new_hist.append(self.allocator, sys) catch unreachable;
            new_hist.appendSlice(self.allocator, recent) catch unreachable;
            self.history.deinit(self.allocator);
            self.history = new_hist;
        }
    }
};
