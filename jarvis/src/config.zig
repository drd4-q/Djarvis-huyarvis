const std = @import("std");

extern fn fopen(filename: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern fn fclose(stream: ?*anyopaque) c_int;
extern fn fseek(stream: ?*anyopaque, offset: c_long, whence: c_int) c_int;
extern fn ftell(stream: ?*anyopaque) c_long;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, stream: ?*anyopaque) usize;

pub const AppConfig = struct {
    llm_host: []const u8 = "127.0.0.1",
    llm_port: u16 = 8080,
    llm_model: []const u8 = "qwen2.5-3b-instruct",
    llm_endpoint: []const u8 = "http://127.0.0.1:8080/v1",
    llm_temperature: f32 = 0.1,
    resource_profile: []const u8 = "hybrid_low_memory",
    stt_engine: []const u8 = "whisper.cpp",
    tts_engine: []const u8 = "piper-tts",
    vad_engine: []const u8 = "silero_vad",

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) AppConfig {
        var cfg = AppConfig{};

        var path_z: [512:0]u8 = undefined;
        if (path.len >= 512) return cfg;
        @memcpy(path_z[0..path.len], path);
        path_z[path.len] = 0;

        const file = fopen(&path_z, "rb") orelse return cfg;
        defer _ = fclose(file);

        _ = fseek(file, 0, 2); // SEEK_END
        const file_size_long = ftell(file);
        if (file_size_long <= 0 or file_size_long > 1024 * 1024) return cfg;
        const file_size: usize = @intCast(file_size_long);
        _ = fseek(file, 0, 0); // SEEK_SET

        const file_content = allocator.alloc(u8, file_size) catch return cfg;
        defer allocator.free(file_content);

        const bytes_read = fread(file_content.ptr, 1, file_size, file);
        if (bytes_read == 0) return cfg;

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, file_content[0..bytes_read], .{}) catch return cfg;
        defer parsed.deinit();

        if (parsed.value != .object) return cfg;

        if (parsed.value.object.get("resource_profile")) |rp| {
            if (rp == .string) cfg.resource_profile = allocator.dupe(u8, rp.string) catch cfg.resource_profile;
        }

        if (parsed.value.object.get("devices")) |devices| {
            if (devices == .object) {
                if (devices.object.get("llm")) |llm_obj| {
                    if (llm_obj == .object) {
                        if (llm_obj.object.get("model")) |m| {
                            if (m == .string) cfg.llm_model = allocator.dupe(u8, m.string) catch cfg.llm_model;
                        }
                        if (llm_obj.object.get("endpoint")) |ep| {
                            if (ep == .string) {
                                const duped_ep = allocator.dupe(u8, ep.string) catch null;
                                if (duped_ep) |dep| {
                                    cfg.llm_endpoint = dep;
                                    var temp_host: []const u8 = "";
                                    parseEndpoint(dep, &temp_host, &cfg.llm_port);
                                    if (temp_host.len > 0) {
                                        cfg.llm_host = allocator.dupe(u8, temp_host) catch cfg.llm_host;
                                    }
                                }
                            }
                        }
                    }
                }
                if (devices.object.get("stt")) |stt_obj| {
                    if (stt_obj == .object) {
                        if (stt_obj.object.get("engine")) |eng| {
                            if (eng == .string) cfg.stt_engine = allocator.dupe(u8, eng.string) catch cfg.stt_engine;
                        }
                    }
                }
                if (devices.object.get("tts")) |tts_obj| {
                    if (tts_obj == .object) {
                        if (tts_obj.object.get("engine")) |eng| {
                            if (eng == .string) cfg.tts_engine = allocator.dupe(u8, eng.string) catch cfg.tts_engine;
                        }
                    }
                }
                if (devices.object.get("vad")) |vad_obj| {
                    if (vad_obj == .object) {
                        if (vad_obj.object.get("engine")) |eng| {
                            if (eng == .string) cfg.vad_engine = allocator.dupe(u8, eng.string) catch cfg.vad_engine;
                        }
                    }
                }
            }
        }

        return cfg;
    }

    fn parseEndpoint(endpoint: []const u8, host_out: *[]const u8, port_out: *u16) void {
        var url = endpoint;
        if (std.mem.startsWith(u8, url, "http://")) {
            url = url["http://".len..];
        } else if (std.mem.startsWith(u8, url, "https://")) {
            url = url["https://".len..];
        }

        // strip path if any (e.g. /v1)
        if (std.mem.indexOf(u8, url, "/")) |idx| {
            url = url[0..idx];
        }

        if (std.mem.indexOf(u8, url, ":")) |colon_idx| {
            host_out.* = url[0..colon_idx];
            const port_str = url[colon_idx + 1 ..];
            if (std.fmt.parseInt(u16, port_str, 10)) |p| {
                port_out.* = p;
            } else |_| {}
        } else {
            host_out.* = url;
        }
    }
};
