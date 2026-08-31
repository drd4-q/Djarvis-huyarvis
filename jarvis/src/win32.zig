const std = @import("std");
const builtin = @import("builtin");

pub const MediaKey = enum {
    play_pause,
    next,
    prev,
    vol_up,
    vol_down,
    mute,
};

pub const Win32Error = error{
    ComInitFailed,
    DeviceEnumeratorFailed,
    DefaultDeviceFailed,
    ActivateVolumeFailed,
    SetVolumeFailed,
    GetVolumeFailed,
    WindowNotFound,
    ShellExecuteFailed,
    UnsupportedPlatform,
    InvalidUtf8,
    LockWorkStationFailed,
    PopenFailed,
};

// C win32 imports on Windows target
const win_c = if (builtin.os.tag == .windows) @cImport({
    @cInclude("windows.h");
    @cInclude("shellapi.h");
    @cInclude("mmdeviceapi.h");
    @cInclude("endpointvolume.h");
}) else struct {};

const CLSID_MMDeviceEnumerator_GUID = std.os.windows.GUID{
    .Data1 = 0xBCDE0395,
    .Data2 = 0xE52F,
    .Data3 = 0x467C,
    .Data4 = .{ 0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E },
};

const IID_IMMDeviceEnumerator_GUID = std.os.windows.GUID{
    .Data1 = 0xA95664D2,
    .Data2 = 0x9614,
    .Data3 = 0x4F35,
    .Data4 = .{ 0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6 },
};

const IID_IAudioEndpointVolume_GUID = std.os.windows.GUID{
    .Data1 = 0x5BC69F0A,
    .Data2 = 0x907E,
    .Data3 = 0x47F1,
    .Data4 = .{ 0x80, 0x9E, 0x9D, 0x41, 0x7B, 0xC8, 0xDE, 0x1A },
};

pub fn setVolume(scalar: f32, mute: ?bool) !void {
    if (builtin.os.tag != .windows) {
        std.debug.print("[Win32 Mock] Set volume: {d:.2}, mute: {any}\n", .{ scalar, mute });
        return;
    }

    const hr = win_c.CoInitializeEx(null, win_c.COINIT_APARTMENTTHREADED);
    defer if (hr == win_c.S_OK or hr == win_c.S_FALSE) win_c.CoUninitialize();

    var pEnumerator: ?*win_c.IMMDeviceEnumerator = null;
    const clsid = @as(*const win_c.GUID, @ptrCast(&CLSID_MMDeviceEnumerator_GUID));
    const iid_enum = @as(*const win_c.GUID, @ptrCast(&IID_IMMDeviceEnumerator_GUID));

    if (win_c.CoCreateInstance(clsid, null, win_c.CLSCTX_INPROC_SERVER, iid_enum, @as(*?*anyopaque, @ptrCast(&pEnumerator))) != win_c.S_OK) {
        return Win32Error.DeviceEnumeratorFailed;
    }
    defer _ = pEnumerator.?.lpVtbl.*.Release.?(pEnumerator.?);

    var pDevice: ?*win_c.IMMDevice = null;
    if (pEnumerator.?.lpVtbl.*.GetDefaultAudioEndpoint.?(pEnumerator.?, win_c.eRender, win_c.eMultimedia, &pDevice) != win_c.S_OK) {
        return Win32Error.DefaultDeviceFailed;
    }
    defer _ = pDevice.?.lpVtbl.*.Release.?(pDevice.?);

    var pVolume: ?*win_c.IAudioEndpointVolume = null;
    const iid_vol = @as(*const win_c.GUID, @ptrCast(&IID_IAudioEndpointVolume_GUID));
    if (pDevice.?.lpVtbl.*.Activate.?(pDevice.?, iid_vol, win_c.CLSCTX_INPROC_SERVER, null, @as(*?*anyopaque, @ptrCast(&pVolume))) != win_c.S_OK) {
        return Win32Error.ActivateVolumeFailed;
    }
    defer _ = pVolume.?.lpVtbl.*.Release.?(pVolume.?);

    var scalar_norm = scalar;
    if (scalar_norm > 1.0) {
        scalar_norm = scalar_norm / 100.0;
    }
    const clamped = std.math.clamp(scalar_norm, 0.0, 1.0);
    if (pVolume.?.lpVtbl.*.SetMasterVolumeLevelScalar.?(pVolume.?, clamped, null) != win_c.S_OK) {
        return Win32Error.SetVolumeFailed;
    }

    if (mute) |is_muted| {
        const mute_val: win_c.BOOL = if (is_muted) 1 else 0;
        _ = pVolume.?.lpVtbl.*.SetMute.?(pVolume.?, mute_val, null);
    }
}

pub fn getVolume() !f32 {
    if (builtin.os.tag != .windows) return 0.5;

    const hr = win_c.CoInitializeEx(null, win_c.COINIT_APARTMENTTHREADED);
    defer if (hr == win_c.S_OK or hr == win_c.S_FALSE) win_c.CoUninitialize();

    var pEnumerator: ?*win_c.IMMDeviceEnumerator = null;
    const clsid = @as(*const win_c.GUID, @ptrCast(&CLSID_MMDeviceEnumerator_GUID));
    const iid_enum = @as(*const win_c.GUID, @ptrCast(&IID_IMMDeviceEnumerator_GUID));

    if (win_c.CoCreateInstance(clsid, null, win_c.CLSCTX_INPROC_SERVER, iid_enum, @as(*?*anyopaque, @ptrCast(&pEnumerator))) != win_c.S_OK) {
        return Win32Error.DeviceEnumeratorFailed;
    }
    defer _ = pEnumerator.?.lpVtbl.*.Release.?(pEnumerator.?);

    var pDevice: ?*win_c.IMMDevice = null;
    if (pEnumerator.?.lpVtbl.*.GetDefaultAudioEndpoint.?(pEnumerator.?, win_c.eRender, win_c.eMultimedia, &pDevice) != win_c.S_OK) {
        return Win32Error.DefaultDeviceFailed;
    }
    defer _ = pDevice.?.lpVtbl.*.Release.?(pDevice.?);

    var pVolume: ?*win_c.IAudioEndpointVolume = null;
    const iid_vol = @as(*const win_c.GUID, @ptrCast(&IID_IAudioEndpointVolume_GUID));
    if (pDevice.?.lpVtbl.*.Activate.?(pDevice.?, iid_vol, win_c.CLSCTX_INPROC_SERVER, null, @as(*?*anyopaque, @ptrCast(&pVolume))) != win_c.S_OK) {
        return Win32Error.ActivateVolumeFailed;
    }
    defer _ = pVolume.?.lpVtbl.*.Release.?(pVolume.?);

    var level: f32 = 0.0;
    if (pVolume.?.lpVtbl.*.GetMasterVolumeLevelScalar.?(pVolume.?, &level) != win_c.S_OK) {
        return Win32Error.GetVolumeFailed;
    }
    return level;
}

pub fn lockWorkstation() !void {
    if (builtin.os.tag != .windows) return;
    if (win_c.LockWorkStation() == 0) return error.LockWorkStationFailed;
}

pub fn shutdownPC(delay_sec: u32, restart: bool) !void {
    if (builtin.os.tag != .windows) return;
    var cmd_buf: [128]u8 = undefined;
    const flag = if (restart) "/r" else "/s";
    const cmd = try std.fmt.bufPrint(&cmd_buf, "shutdown {s} /t {d}", .{ flag, delay_sec });
    _ = executeCommandRaw(cmd);
}

pub fn cancelShutdown() !void {
    if (builtin.os.tag != .windows) return;
    _ = executeCommandRaw("shutdown /a");
}

pub fn sleepPC() !void {
    if (builtin.os.tag != .windows) return;
    _ = executeCommandRaw("rundll32.exe powrprof.dll,SetSuspendState 0,1,0");
}

pub fn minimizeAll() !void {
    if (builtin.os.tag != .windows) return;
    var inputs: [4]win_c.INPUT = std.mem.zeroes([4]win_c.INPUT);
    inputs[0].type = win_c.INPUT_KEYBOARD;
    inputs[0].unnamed_0.ki.wVk = win_c.VK_LWIN;

    inputs[1].type = win_c.INPUT_KEYBOARD;
    inputs[1].unnamed_0.ki.wVk = 'D';

    inputs[2].type = win_c.INPUT_KEYBOARD;
    inputs[2].unnamed_0.ki.wVk = 'D';
    inputs[2].unnamed_0.ki.dwFlags = win_c.KEYEVENTF_KEYUP;

    inputs[3].type = win_c.INPUT_KEYBOARD;
    inputs[3].unnamed_0.ki.wVk = win_c.VK_LWIN;
    inputs[3].unnamed_0.ki.dwFlags = win_c.KEYEVENTF_KEYUP;

    _ = win_c.SendInput(4, &inputs[0], @sizeOf(win_c.INPUT));
}

pub fn closeActiveWindow() !void {
    if (builtin.os.tag != .windows) return;
    const hwnd = win_c.GetForegroundWindow();
    if (hwnd != null) {
        _ = win_c.PostMessageW(hwnd, win_c.WM_CLOSE, 0, 0);
    }
}

pub fn emptyRecycleBin() !void {
    if (builtin.os.tag != .windows) return;
    _ = executeCommandRaw("powershell -NoProfile -NonInteractive -Command \"Clear-RecycleBin -Force -ErrorAction SilentlyContinue\"");
}

pub fn sendMediaKey(key: MediaKey) !void {
    if (builtin.os.tag != .windows) return;

    const vk: win_c.WORD = switch (key) {
        .play_pause => 0xB3,
        .next => 0xB0,
        .prev => 0xB1,
        .vol_up => 0xAF,
        .vol_down => 0xAE,
        .mute => 0xAD,
    };

    var inputs: [2]win_c.INPUT = std.mem.zeroes([2]win_c.INPUT);
    inputs[0].type = win_c.INPUT_KEYBOARD;
    inputs[0].unnamed_0.ki.wVk = vk;

    inputs[1].type = win_c.INPUT_KEYBOARD;
    inputs[1].unnamed_0.ki.wVk = vk;
    inputs[1].unnamed_0.ki.dwFlags = win_c.KEYEVENTF_KEYUP;

    _ = win_c.SendInput(2, &inputs[0], @sizeOf(win_c.INPUT));
}

pub fn pressKeyCombination(combo: []const u8) !void {
    if (builtin.os.tag != .windows) return;

    if (std.mem.eql(u8, combo, "alt+tab")) {
        _ = executeCommandRaw("powershell -NoProfile -NonInteractive -Command \"$w = New-Object -ComObject WScript.Shell; $w.SendKeys('%{TAB}')\"");
    } else if (std.mem.eql(u8, combo, "ctrl+c")) {
        _ = executeCommandRaw("powershell -NoProfile -NonInteractive -Command \"$w = New-Object -ComObject WScript.Shell; $w.SendKeys('^c')\"");
    } else if (std.mem.eql(u8, combo, "ctrl+v")) {
        _ = executeCommandRaw("powershell -NoProfile -NonInteractive -Command \"$w = New-Object -ComObject WScript.Shell; $w.SendKeys('^v')\"");
    } else if (std.mem.eql(u8, combo, "enter")) {
        _ = executeCommandRaw("powershell -NoProfile -NonInteractive -Command \"$w = New-Object -ComObject WScript.Shell; $w.SendKeys('{ENTER}')\"");
    } else if (std.mem.eql(u8, combo, "space")) {
        _ = executeCommandRaw("powershell -NoProfile -NonInteractive -Command \"$w = New-Object -ComObject WScript.Shell; $w.SendKeys(' ')\"");
    }
}

pub fn takeScreenshot(allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    if (builtin.os.tag != .windows) return "Скриншот сохранен";
    const script =
        \\powershell -NoProfile -NonInteractive -Command "Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $path = Join-Path ([Environment]::GetFolderPath('MyPictures')) ('Screenshot_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.png'); $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose(); Write-Output ('Сохранено в: ' + $path)"
    ;
    return executeCommandRaw(script);
}

pub fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    const hex_chars = "0123456789ABCDEF";
    for (input) |c| {
        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_' or c == '.' or c == '~') {
            try out.append(allocator, c);
        } else if (c == ' ') {
            try out.append(allocator, '+');
        } else {
            try out.append(allocator, '%');
            try out.append(allocator, hex_chars[(c >> 4) & 0x0F]);
            try out.append(allocator, hex_chars[c & 0x0F]);
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn sanitizeUrl(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, input, " \r\n\t'\"<>");

    // Fix punycode hallucinations (e.g. youtube.xn--com-ls0a349bjl7h3xi54br7g -> youtube.com)
    if (std.mem.indexOf(u8, trimmed, "youtube") != null or std.mem.indexOf(u8, trimmed, "youtu.be") != null or std.mem.indexOf(u8, trimmed, "ютуб") != null or std.mem.indexOf(u8, trimmed, "ютюб") != null) {
        if (std.mem.indexOf(u8, trimmed, "watch?v=") != null) {
            const v_idx = std.mem.indexOf(u8, trimmed, "watch?v=").?;
            return try std.fmt.allocPrint(allocator, "https://www.youtube.com/{s}", .{trimmed[v_idx..]});
        }
        return try allocator.dupe(u8, "https://www.youtube.com");
    }

    if (std.mem.indexOf(u8, trimmed, "vk.com") != null or std.mem.indexOf(u8, trimmed, "vkontakte") != null or std.mem.indexOf(u8, trimmed, "вк") != null) {
        return try allocator.dupe(u8, "https://vk.com");
    }

    if (std.mem.indexOf(u8, trimmed, "yandex") != null or std.mem.indexOf(u8, trimmed, "ya.ru") != null or std.mem.indexOf(u8, trimmed, "яндекс") != null) {
        return try allocator.dupe(u8, "https://ya.ru");
    }

    if (std.mem.indexOf(u8, trimmed, "google") != null or std.mem.indexOf(u8, trimmed, "гугл") != null) {
        return try allocator.dupe(u8, "https://www.google.com");
    }

    if (std.mem.indexOf(u8, trimmed, "github") != null or std.mem.indexOf(u8, trimmed, "гитхаб") != null) {
        return try allocator.dupe(u8, "https://github.com");
    }

    if (std.mem.indexOf(u8, trimmed, "telegram") != null or std.mem.indexOf(u8, trimmed, "t.me") != null or std.mem.indexOf(u8, trimmed, "телеграм") != null) {
        return try allocator.dupe(u8, "https://web.telegram.org");
    }

    if (std.mem.indexOf(u8, trimmed, "wikipedia") != null or std.mem.indexOf(u8, trimmed, "википедия") != null) {
        return try allocator.dupe(u8, "https://ru.wikipedia.org");
    }

    if (std.mem.indexOf(u8, trimmed, "mail.ru") != null or std.mem.indexOf(u8, trimmed, "почта") != null) {
        return try allocator.dupe(u8, "https://mail.ru");
    }

    if (std.mem.indexOf(u8, trimmed, "kinopoisk") != null or std.mem.indexOf(u8, trimmed, "кинопоиск") != null) {
        return try allocator.dupe(u8, "https://kinopoisk.ru");
    }

    if (std.mem.indexOf(u8, trimmed, "gosuslugi") != null or std.mem.indexOf(u8, trimmed, "госуслуги") != null) {
        return try allocator.dupe(u8, "https://gosuslugi.ru");
    }

    if (std.mem.indexOf(u8, trimmed, "ozon") != null or std.mem.indexOf(u8, trimmed, "озон") != null) {
        return try allocator.dupe(u8, "https://ozon.ru");
    }

    if (std.mem.indexOf(u8, trimmed, "wildberries") != null or std.mem.indexOf(u8, trimmed, "вайлдберриз") != null or std.mem.indexOf(u8, trimmed, "вб") != null) {
        return try allocator.dupe(u8, "https://wildberries.ru");
    }

    if (std.mem.indexOf(u8, trimmed, "steam") != null or std.mem.indexOf(u8, trimmed, "стим") != null) {
        return try allocator.dupe(u8, "https://store.steampowered.com");
    }

    // Strip punycode domains
    if (std.mem.indexOf(u8, trimmed, ".xn--") != null) {
        const xn_idx = std.mem.indexOf(u8, trimmed, ".xn--").?;
        const domain_prefix = trimmed[0..xn_idx];
        if (std.mem.startsWith(u8, domain_prefix, "http://") or std.mem.startsWith(u8, domain_prefix, "https://")) {
            return try std.fmt.allocPrint(allocator, "{s}.com", .{domain_prefix});
        }
        return try std.fmt.allocPrint(allocator, "https://{s}.com", .{domain_prefix});
    }

    if (std.mem.startsWith(u8, trimmed, "http://") or std.mem.startsWith(u8, trimmed, "https://")) {
        return try allocator.dupe(u8, trimmed);
    }

    if (std.mem.indexOf(u8, trimmed, ".") != null and std.mem.indexOf(u8, trimmed, " ") == null) {
        return try std.fmt.allocPrint(allocator, "https://{s}", .{trimmed});
    }

    const encoded = try urlEncode(allocator, trimmed);
    defer allocator.free(encoded);
    return try std.fmt.allocPrint(allocator, "https://www.google.com/search?q={s}", .{encoded});
}

pub fn resolveSiteUrl(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    return sanitizeUrl(allocator, input);
}

pub fn openUrl(allocator: std.mem.Allocator, raw_url: []const u8) !void {
    const resolved = try resolveSiteUrl(allocator, raw_url);
    defer allocator.free(resolved);
    try openApp(allocator, resolved, null);
}

pub fn searchWeb(allocator: std.mem.Allocator, query: []const u8) !void {
    const encoded = try urlEncode(allocator, query);
    defer allocator.free(encoded);
    const search_url = try std.fmt.allocPrint(allocator, "https://www.google.com/search?q={s}", .{encoded});
    defer allocator.free(search_url);
    try openApp(allocator, search_url, null);
}

pub fn fetchWebSummary(allocator: std.mem.Allocator, query: []const u8) ![]const u8 {
    const encoded = try urlEncode(allocator, query);
    defer allocator.free(encoded);

    // 1. Wikipedia Russian Summary API
    const cmd_wiki = try std.fmt.allocPrint(allocator, "curl.exe -s --max-time 4 \"https://ru.wikipedia.org/api/rest_v1/page/summary/{s}\"", .{encoded});
    defer allocator.free(cmd_wiki);

    const wiki_json = executeCommand(allocator, cmd_wiki) catch "";
    if (wiki_json.len > 20) {
        if (std.json.parseFromSlice(std.json.Value, allocator, wiki_json, .{})) |parsed| {
            defer parsed.deinit();
            if (parsed.value == .object) {
                if (parsed.value.object.get("extract")) |ext| {
                    if (ext == .string and ext.string.len > 0) {
                        return try allocator.dupe(u8, ext.string);
                    }
                }
            }
        } else |_| {}
    }

    // 2. DuckDuckGo Instant Answer API
    const cmd_ddg = try std.fmt.allocPrint(allocator, "curl.exe -s --max-time 4 \"https://api.duckduckgo.com/?q={s}&format=json&no_html=1&skip_disambig=1\"", .{encoded});
    defer allocator.free(cmd_ddg);

    const ddg_json = executeCommand(allocator, cmd_ddg) catch "";
    if (ddg_json.len > 20) {
        if (std.json.parseFromSlice(std.json.Value, allocator, ddg_json, .{})) |parsed| {
            defer parsed.deinit();
            if (parsed.value == .object) {
                if (parsed.value.object.get("AbstractText")) |abt| {
                    if (abt == .string and abt.string.len > 0) {
                        return try allocator.dupe(u8, abt.string);
                    }
                }
            }
        } else |_| {}
    }

    return "Информация по данному запросу не найдена. Попробуйте уточнить ключевые слова или открыть поиск в браузере.";
}

const WindowSearchContext = struct {
    needle_utf16: [256]u16,
    needle_len: usize,
    found_hwnd: ?*anyopaque = null,
};

pub fn focusWindow(allocator: std.mem.Allocator, title_contains: []const u8) !void {
    _ = allocator;
    if (builtin.os.tag != .windows) return;

    var ctx: WindowSearchContext = .{
        .needle_utf16 = std.mem.zeroes([256]u16),
        .needle_len = 0,
        .found_hwnd = null,
    };

    const utf16_len = std.unicode.utf8ToUtf16Le(&ctx.needle_utf16, title_contains) catch return error.InvalidUtf8;
    ctx.needle_utf16[utf16_len] = 0;
    ctx.needle_len = utf16_len;

    const callback = struct {
        fn enumProc(hwnd: win_c.HWND, lparam: win_c.LPARAM) callconv(.c) win_c.BOOL {
            const search_ctx: *WindowSearchContext = @ptrFromInt(@as(usize, @bitCast(lparam)));
            var title_buf: [512]u16 = undefined;
            const len = win_c.GetWindowTextW(hwnd, @as([*c]u16, @ptrCast(&title_buf)), 512);
            if (len <= 0) return 1;

            const title_slice = title_buf[0..@as(usize, @intCast(len))];
            const needle = search_ctx.needle_utf16[0..search_ctx.needle_len];

            if (std.mem.indexOf(u16, title_slice, needle) != null) {
                search_ctx.found_hwnd = hwnd;
                return 0;
            }
            return 1;
        }
    }.enumProc;

    _ = win_c.EnumWindows(callback, @as(win_c.LPARAM, @bitCast(@intFromPtr(&ctx))));

    if (ctx.found_hwnd) |hwnd_ptr| {
        const hwnd: win_c.HWND = @ptrCast(@alignCast(hwnd_ptr));
        _ = win_c.ShowWindow(hwnd, win_c.SW_RESTORE);
        _ = win_c.SetForegroundWindow(hwnd);
    } else {
        return Win32Error.WindowNotFound;
    }
}

pub fn openApp(allocator: std.mem.Allocator, path: []const u8, args: ?[]const u8) !void {
    _ = allocator;
    if (builtin.os.tag != .windows) return;

    var path_w: [1024:0]u16 = std.mem.zeroes([1024:0]u16);
    const p_len = std.unicode.utf8ToUtf16Le(&path_w, path) catch return error.InvalidUtf8;
    path_w[p_len] = 0;

    var args_w: [1024:0]u16 = std.mem.zeroes([1024:0]u16);
    var args_ptr: ?[*:0]const u16 = null;
    if (args) |a| {
        const a_len = std.unicode.utf8ToUtf16Le(&args_w, a) catch return error.InvalidUtf8;
        args_w[a_len] = 0;
        args_ptr = @as([*:0]const u16, @ptrCast(&args_w));
    }

    const res = win_c.ShellExecuteW(
        null,
        std.unicode.utf8ToUtf16LeStringLiteral("open"),
        @as([*:0]const u16, @ptrCast(&path_w)),
        args_ptr,
        null,
        win_c.SW_SHOWNORMAL,
    );

    if (@intFromPtr(res) <= 32) {
        return Win32Error.ShellExecuteFailed;
    }
}

pub extern fn capture_screen_bmp(filepath: [*:0]const u8) c_int;
extern fn fopen(filename: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern fn fclose(stream: ?*anyopaque) c_int;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, stream: ?*anyopaque) usize;
extern fn fwrite(ptr: [*]const u8, size: usize, nmemb: usize, stream: ?*anyopaque) usize;
extern fn fseek(stream: ?*anyopaque, offset: c_long, origin: c_int) c_int;
extern fn ftell(stream: ?*anyopaque) c_long;
extern fn popen(command: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern fn pclose(stream: ?*anyopaque) c_int;
extern fn time(timer: ?*i64) i64;
extern fn ctime(timer: *const i64) ?[*:0]const u8;

pub fn lookAtScreen(allocator: std.mem.Allocator) ![]const u8 {
    const bmp_path = "cache_screen.bmp";
    const res = capture_screen_bmp(bmp_path);
    if (res == 0) {
        return "Не удалось сделать снимок экрана.";
    }

    const fp = fopen(bmp_path, "rb");
    if (fp == null) {
        return "Ошибка чтения снимка экрана.";
    }
    defer _ = fclose(fp);

    _ = fseek(fp, 0, 2); // SEEK_END
    const file_size_c = ftell(fp);
    _ = fseek(fp, 0, 0); // SEEK_SET

    if (file_size_c <= 0 or file_size_c > 20 * 1024 * 1024) {
        return "Некорректный размер снимка экрана.";
    }
    const file_size: usize = @intCast(file_size_c);
    const img_buf = try allocator.alloc(u8, file_size);
    defer allocator.free(img_buf);
    const n_read = fread(img_buf.ptr, 1, file_size, fp);
    if (n_read == 0) return "Не удалось прочитать данные экрана.";

    const encoder = std.base64.standard.Encoder;
    const b64_len = encoder.calcSize(img_buf.len);
    const b64_buf = try allocator.alloc(u8, b64_len);
    defer allocator.free(b64_buf);
    _ = encoder.encode(b64_buf, img_buf);

    // Call SmolVLM Vision server on port 8081 via JSON request file
    const json_file = "cache_vlm_req.json";
    const req_fp = fopen(json_file, "wb");
    if (req_fp != null) {
        const prefix = "{\"model\":\"smolvlm\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"Describe in detail in Russian what is visible on this computer screen. Mention open windows, text, apps, browser tabs.\"},{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/bmp;base64,";
        const suffix = "\"}}]}],\"max_tokens\":256,\"temperature\":0.2}";
        _ = fwrite(prefix.ptr, 1, prefix.len, req_fp);
        _ = fwrite(b64_buf.ptr, 1, b64_buf.len, req_fp);
        _ = fwrite(suffix.ptr, 1, suffix.len, req_fp);
        _ = fclose(req_fp);

        const vlm_out = executeCommand(allocator, "curl.exe -s -X POST http://127.0.0.1:8081/v1/chat/completions -H \"Content-Type: application/json\" -d @cache_vlm_req.json --max-time 10") catch "";
        if (vlm_out.len > 20) {
            if (std.json.parseFromSlice(std.json.Value, allocator, vlm_out, .{})) |parsed| {
                defer parsed.deinit();
                if (parsed.value == .object) {
                    if (parsed.value.object.get("choices")) |choices| {
                        if (choices == .array and choices.array.items.len > 0) {
                            const choice0 = choices.array.items[0];
                            if (choice0 == .object) {
                                if (choice0.object.get("message")) |msg| {
                                    if (msg == .object) {
                                        if (msg.object.get("content")) |cnt| {
                                            if (cnt == .string and cnt.string.len > 0) {
                                                return try allocator.dupe(u8, cnt.string);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else |_| {}
        }
    }

    // Fallback: active window title
    var fg_title: [512]u16 = undefined;
    const hwnd = win_c.GetForegroundWindow();
    if (hwnd != null) {
        const len = win_c.GetWindowTextW(hwnd, @as([*c]u16, @ptrCast(&fg_title)), 512);
        if (len > 0) {
            var title_u8: [512]u8 = undefined;
            const u8_len = std.unicode.utf16LeToUtf8(&title_u8, fg_title[0..@intCast(len)]) catch 0;
            if (u8_len > 0) {
                return try std.fmt.allocPrint(allocator, "Снимок экрана сделан. Активное окно: «{s}».", .{title_u8[0..u8_len]});
            }
        }
    }

    return "Снимок экрана сохранен в cache_screen.bmp.";
}

pub fn readWebpageContent(allocator: std.mem.Allocator, raw_url: []const u8) ![]const u8 {
    const resolved = try resolveSiteUrl(allocator, raw_url);
    defer allocator.free(resolved);

    const cmd = try std.fmt.allocPrint(allocator, "curl.exe -s -L --max-time 5 -A \"Mozilla/5.0\" \"{s}\"", .{resolved});
    defer allocator.free(cmd);

    const html = executeCommand(allocator, cmd) catch {
        return "Не удалось загрузить веб-страницу.";
    };

    if (html.len == 0) return "Веб-страница пуста или не отвечает.";

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var in_tag = false;
    var in_script = false;
    var last_space = false;
    var i: usize = 0;

    while (i < html.len and out.items.len < 1200) {
        const c = html[i];
        if (c == '<') {
            in_tag = true;
            if (i + 7 <= html.len and std.ascii.eqlIgnoreCase(html[i .. i + 7], "<script")) {
                in_script = true;
            } else if (i + 6 <= html.len and std.ascii.eqlIgnoreCase(html[i .. i + 6], "<style")) {
                in_script = true;
            } else if (i + 9 <= html.len and std.ascii.eqlIgnoreCase(html[i .. i + 9], "</script>")) {
                in_script = false;
                i += 9;
                in_tag = false;
                continue;
            } else if (i + 8 <= html.len and std.ascii.eqlIgnoreCase(html[i .. i + 8], "</style>")) {
                in_script = false;
                i += 8;
                in_tag = false;
                continue;
            }
            i += 1;
            continue;
        }
        if (c == '>') {
            in_tag = false;
            i += 1;
            continue;
        }

        if (!in_tag and !in_script) {
            if (c == '\r' or c == '\n' or c == '\t' or c == ' ') {
                if (!last_space and out.items.len > 0) {
                    try out.append(allocator, ' ');
                    last_space = true;
                }
            } else if (c >= 32) {
                try out.append(allocator, c);
                last_space = false;
            }
        }
        i += 1;
    }

    if (out.items.len == 0) {
        return "Содержимое страницы не содержит читаемого текста.";
    }

    return out.toOwnedSlice(allocator);
}

fn executeCommandRaw(command: []const u8) []const u8 {
    var cmd_z: [4096:0]u8 = undefined;
    if (command.len >= 4096) return "";
    @memcpy(cmd_z[0..command.len], command);
    cmd_z[command.len] = 0;

    const stream = popen(&cmd_z, "r") orelse return "";
    defer _ = pclose(stream);

    var output: [2048]u8 = undefined;
    const n = fread(&output, 1, 2047, stream);
    return std.mem.trim(u8, output[0..n], " \r\n\t");
}

pub fn executeCommand(allocator: std.mem.Allocator, command: []const u8) ![]const u8 {
    var cmd_z = try allocator.allocSentinel(u8, command.len, 0);
    defer allocator.free(cmd_z);
    @memcpy(cmd_z[0..command.len], command);

    const stream = popen(cmd_z.ptr, "r") orelse return error.PopenFailed;
    defer _ = pclose(stream);

    var output = try allocator.alloc(u8, 8192);
    const n = fread(output.ptr, 1, 8191, stream);
    return output[0..n];
}

pub fn getBatteryStatus(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag != .windows) return "Питание от сети";

    var sps: win_c.SYSTEM_POWER_STATUS = undefined;
    if (win_c.GetSystemPowerStatus(&sps) == 0) return "Не удалось получить статус батареи";

    const percent: u8 = sps.BatteryLifePercent;
    const is_charging = (sps.ACLineStatus == 1);

    if (percent > 100) {
        return "Питание от сети (компьютер подключен к розетке)";
    }

    return try std.fmt.allocPrint(allocator,
        "Заряд аккумулятора: {d} процентов, {s}",
        .{ percent, if (is_charging) "подключено к сети (заряжается)" else "работа от батареи" }
    );
}

pub fn getSystemInfo(allocator: std.mem.Allocator) ![]const u8 {
    var t: i64 = 0;
    _ = time(&t);
    const time_str = if (ctime(&t)) |s| std.mem.span(s) else "unknown";
    const trimmed_time = std.mem.trim(u8, time_str, "\r\n");

    var mem_str: []const u8 = "";
    if (builtin.os.tag == .windows) {
        var ms: win_c.MEMORYSTATUSEX = std.mem.zeroes(win_c.MEMORYSTATUSEX);
        ms.dwLength = @sizeOf(win_c.MEMORYSTATUSEX);
        if (win_c.GlobalMemoryStatusEx(&ms) != 0) {
            const total_gb = @as(f32, @floatFromInt(ms.ullTotalPhys)) / (1024.0 * 1024.0 * 1024.0);
            const avail_gb = @as(f32, @floatFromInt(ms.ullAvailPhys)) / (1024.0 * 1024.0 * 1024.0);
            mem_str = std.fmt.allocPrint(allocator, ", ОЗУ: {d:.1}/{d:.1} ГБ", .{ total_gb - avail_gb, total_gb }) catch "";
        }
    }

    return try std.fmt.allocPrint(allocator,
        "ОС: Windows x64, Системное время: {s}{s}",
        .{ trimmed_time, mem_str }
    );
}
