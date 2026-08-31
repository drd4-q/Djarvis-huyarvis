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

pub fn rescanApps(allocator: std.mem.Allocator) ![]const u8 {
    _ = executeCommand(allocator, "powershell -ExecutionPolicy Bypass -File .\\scripts\\index_apps.ps1") catch "";
    return "База данных установленных программ успешно обновлена.";
}

pub var g_vad_threshold: std.atomic.Value(i32) = std.atomic.Value(i32).init(300);

pub fn setVadSensitivity(sensitivity: i32) ![]const u8 {
    const clamped = std.math.clamp(sensitivity, 50, 2000);
    g_vad_threshold.store(clamped, .release);
    var buf: [128]u8 = undefined;
    return std.fmt.bufPrint(&buf, "Чувствительность микрофона установлена на {d}.", .{clamped}) catch "Чувствительность изменена.";
}

pub fn getVadSensitivity() i32 {
    return g_vad_threshold.load(.acquire);
}

fn containsFuzzy(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

pub fn openAppByName(allocator: std.mem.Allocator, app_name: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, app_name, " \r\n\t'\"");
    if (trimmed.len == 0) return "Не указано имя программы.";

    // 1. Built-in Windows tools
    if (std.mem.indexOf(u8, trimmed, "калькулятор") != null or std.ascii.eqlIgnoreCase(trimmed, "calc") or std.ascii.eqlIgnoreCase(trimmed, "calculator")) {
        try openApp(allocator, "calc.exe", null);
        return "Открываю Калькулятор.";
    } else if (std.mem.indexOf(u8, trimmed, "блокнот") != null or std.ascii.eqlIgnoreCase(trimmed, "notepad")) {
        try openApp(allocator, "notepad.exe", null);
        return "Открываю Блокнот.";
    } else if (std.mem.indexOf(u8, trimmed, "диспетчер задач") != null or std.ascii.eqlIgnoreCase(trimmed, "taskmgr") or std.ascii.eqlIgnoreCase(trimmed, "task manager")) {
        try openApp(allocator, "taskmgr.exe", null);
        return "Открываю Диспетчер задач.";
    } else if (std.mem.indexOf(u8, trimmed, "командная строка") != null or std.ascii.eqlIgnoreCase(trimmed, "cmd")) {
        try openApp(allocator, "cmd.exe", null);
        return "Открываю Командную строку.";
    } else if (std.mem.indexOf(u8, trimmed, "проводник") != null or std.ascii.eqlIgnoreCase(trimmed, "explorer")) {
        try openApp(allocator, "explorer.exe", null);
        return "Открываю Проводник.";
    } else if (std.mem.indexOf(u8, trimmed, "паинт") != null or std.mem.indexOf(u8, trimmed, "пейнт") != null or std.ascii.eqlIgnoreCase(trimmed, "paint") or std.ascii.eqlIgnoreCase(trimmed, "mspaint")) {
        try openApp(allocator, "mspaint.exe", null);
        return "Открываю Paint.";
    } else if (std.mem.indexOf(u8, trimmed, "настройки") != null or std.mem.indexOf(u8, trimmed, "параметры") != null or std.ascii.eqlIgnoreCase(trimmed, "settings")) {
        try openApp(allocator, "ms-settings:", null);
        return "Открываю Параметры Windows.";
    }

    // Direct launch for top desktop applications
    if (std.mem.indexOf(u8, trimmed, "стим") != null or std.ascii.eqlIgnoreCase(trimmed, "steam")) {
        openUrl(allocator, "steam://open/main") catch {};
        openApp(allocator, "C:\\Program Files (x86)\\Steam\\steam.exe", null) catch {};
        openApp(allocator, "C:\\Program Files\\Steam\\steam.exe", null) catch {};
        return "Открываю Steam.";
    } else if (std.mem.indexOf(u8, trimmed, "дискорд") != null or std.ascii.eqlIgnoreCase(trimmed, "discord")) {
        openUrl(allocator, "discord://") catch {};
        openApp(allocator, "Discord.exe", null) catch {};
        return "Открываю Discord.";
    } else if (std.mem.indexOf(u8, trimmed, "телеграм") != null or std.mem.indexOf(u8, trimmed, "телег") != null or std.ascii.eqlIgnoreCase(trimmed, "telegram")) {
        openUrl(allocator, "tg://") catch {};
        openApp(allocator, "Telegram.exe", null) catch {};
        return "Открываю Telegram.";
    } else if (std.mem.indexOf(u8, trimmed, "хром") != null or std.mem.indexOf(u8, trimmed, "гугл") != null or std.mem.indexOf(u8, trimmed, "браузер") != null or std.ascii.eqlIgnoreCase(trimmed, "chrome")) {
        openApp(allocator, "chrome.exe", null) catch {};
        openApp(allocator, "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", null) catch {};
        openApp(allocator, "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe", null) catch {};
        return "Открываю Google Chrome.";
    } else if (std.mem.indexOf(u8, trimmed, "музык") != null or std.mem.indexOf(u8, trimmed, "яндекс") != null) {
        openUrl(allocator, "yandexmusic://") catch {};
        openUrl(allocator, "https://music.yandex.ru") catch {};
        return "Открываю Яндекс Музыку.";
    } else if (std.mem.indexOf(u8, trimmed, "код") != null or std.mem.indexOf(u8, trimmed, "вскод") != null or std.mem.indexOf(u8, trimmed, "вс код") != null or std.ascii.eqlIgnoreCase(trimmed, "code")) {
        openApp(allocator, "code.cmd", null) catch {};
        openApp(allocator, "Code.exe", null) catch {};
        return "Открываю Visual Studio Code.";
    }

    var query: []const u8 = trimmed;
    if (std.mem.indexOf(u8, trimmed, "обс") != null or std.ascii.eqlIgnoreCase(trimmed, "obs")) {
        query = "obs";
    } else if (std.mem.indexOf(u8, trimmed, "аида") != null or std.ascii.eqlIgnoreCase(trimmed, "aida")) {
        query = "aida64";
    } else if (std.mem.indexOf(u8, trimmed, "автобернер") != null or std.mem.indexOf(u8, trimmed, "афтербернер") != null or std.ascii.eqlIgnoreCase(trimmed, "afterburner")) {
        query = "msi afterburner";
    } else if (std.mem.indexOf(u8, trimmed, "риватюнер") != null or std.mem.indexOf(u8, trimmed, "рива") != null or std.ascii.eqlIgnoreCase(trimmed, "rivatuner")) {
        query = "rivatuner";
    } else if (std.mem.indexOf(u8, trimmed, "торрент") != null or std.mem.indexOf(u8, trimmed, "кьюбит") != null or std.ascii.eqlIgnoreCase(trimmed, "torrent")) {
        query = "qbittorrent";
    } else if (std.mem.indexOf(u8, trimmed, "визтри") != null or std.ascii.eqlIgnoreCase(trimmed, "wiztree")) {
        query = "wiztree";
    } else if (std.mem.indexOf(u8, trimmed, "рипер") != null or std.ascii.eqlIgnoreCase(trimmed, "reaper")) {
        query = "reaper";
    } else if (std.mem.indexOf(u8, trimmed, "принтер") != null or std.mem.indexOf(u8, trimmed, "крилити") != null or std.ascii.eqlIgnoreCase(trimmed, "creality")) {
        query = "creality";
    } else if (std.mem.indexOf(u8, trimmed, "эврисинг") != null or std.ascii.eqlIgnoreCase(trimmed, "everything")) {
        query = "everything";
    } else if (std.mem.indexOf(u8, trimmed, "радмин") != null or std.ascii.eqlIgnoreCase(trimmed, "radmin")) {
        query = "radmin";
    }

    // 2. Search in indexed applications database (cache_apps.json)
    const json_path = "cache_apps.json";
    var fp = fopen(json_path, "rb");
    if (fp == null) {
        _ = rescanApps(allocator) catch "";
        fp = fopen(json_path, "rb");
    }

    var best_match_path: ?[]const u8 = null;
    var best_match_title: ?[]const u8 = null;
    var best_score: usize = 0;

    if (fp) |f| {
        defer _ = fclose(f);
        _ = fseek(f, 0, 2);
        const fsize_c = ftell(f);
        _ = fseek(f, 0, 0);

        if (fsize_c > 0 and fsize_c < 10 * 1024 * 1024) {
            const fsize: usize = @intCast(fsize_c);
            const buf = try allocator.alloc(u8, fsize);
            defer allocator.free(buf);
            const n_read = fread(buf.ptr, 1, fsize, f);
            if (n_read > 0) {
                if (std.json.parseFromSlice(std.json.Value, allocator, buf[0..n_read], .{})) |parsed| {
                    defer parsed.deinit();
                    if (parsed.value == .array) {
                        for (parsed.value.array.items) |item| {
                            if (item == .object) {
                                const name_val = item.object.get("name");
                                const path_val = item.object.get("path");
                                const title_val = item.object.get("title");

                                if (name_val != null and path_val != null and name_val.? == .string and path_val.? == .string) {
                                    const app_key = name_val.?.string;
                                    const app_target = path_val.?.string;
                                    const display_title = if (title_val != null and title_val.? == .string) title_val.?.string else query;

                                    var score: usize = 0;
                                    if (std.ascii.eqlIgnoreCase(app_key, query) or std.ascii.eqlIgnoreCase(display_title, query)) {
                                        score = 100;
                                    } else if (containsFuzzy(app_key, query) or containsFuzzy(display_title, query)) {
                                        score = 80;
                                    } else if (containsFuzzy(query, app_key)) {
                                        score = 50;
                                    }

                                    // Filter out uninstaller shortcuts
                                    if (containsFuzzy(app_key, "uninstall") or containsFuzzy(app_key, "деинсталл")) {
                                        score = 0;
                                    }

                                    if (score > best_score) {
                                        best_score = score;
                                        if (best_match_path) |bmp| allocator.free(bmp);
                                        if (best_match_title) |bmt| allocator.free(bmt);
                                        best_match_path = try allocator.dupe(u8, app_target);
                                        best_match_title = try allocator.dupe(u8, display_title);
                                    }
                                }
                            }
                        }
                    }
                } else |_| {}
            }
        }
    }

    if (best_match_path) |bmp| {
        defer allocator.free(bmp);
        openApp(allocator, bmp, null) catch {};
        const title_to_show = if (best_match_title) |bmt| bmt else query;
        return try std.fmt.allocPrint(allocator, "Открываю {s}.", .{title_to_show});
    }

    // 3. Fallback: Deep filesystem executable discovery
    const deep_cmd = try std.fmt.allocPrint(allocator, "powershell -NoProfile -Command \"$f = Get-ChildItem -Path @('C:\\Program Files', 'C:\\Program Files (x86)', \\\"$env:LOCALAPPDATA\\Programs\\\") -Filter '*{s}*.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1; if ($f) {{{{ $f.FullName }}}}\"", .{query});
    defer allocator.free(deep_cmd);

    const found_exe_raw = executeCommand(allocator, deep_cmd) catch "";
    const found_exe = std.mem.trim(u8, found_exe_raw, " \r\n\t");
    if (found_exe.len > 3 and std.mem.endsWith(u8, found_exe, ".exe")) {
        openApp(allocator, found_exe, null) catch {};
        return try std.fmt.allocPrint(allocator, "Найдено и запущено: {s}.", .{query});
    }

    // 4. Fallback to direct Windows launch
    openApp(allocator, trimmed, null) catch {
        return try std.fmt.allocPrint(allocator, "Не удалось найти программу '{s}' на компьютере.", .{trimmed});
    };
    return try std.fmt.allocPrint(allocator, "Открываю {s}.", .{trimmed});
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

pub var g_screen_lock: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
pub var g_live_screen_description: [2048]u8 = std.mem.zeroes([2048]u8);
pub var g_live_screen_len: usize = 0;
pub var g_live_window_title: [512]u8 = std.mem.zeroes([512]u8);
pub var g_live_window_len: usize = 0;

const WindowEnumState = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(u8),
};

fn enumWindowsCallback(hwnd: win_c.HWND, lparam: win_c.LPARAM) callconv(.c) win_c.BOOL {
    if (hwnd == null) return 1;
    if (win_c.IsWindowVisible(hwnd) == 0) return 1;

    var title_w: [512]u16 = undefined;
    const len = win_c.GetWindowTextW(hwnd, @as([*c]u16, @ptrCast(&title_w)), 512);
    if (len <= 0) return 1;

    var title_u8: [512]u8 = undefined;
    const u8_len = std.unicode.utf16LeToUtf8(&title_u8, title_w[0..@intCast(len)]) catch return 1;
    const trimmed = std.mem.trim(u8, title_u8[0..u8_len], " \r\n\t");
    if (trimmed.len < 2) return 1;

    if (std.mem.eql(u8, trimmed, "Program Manager") or std.mem.eql(u8, trimmed, "Settings") or std.mem.eql(u8, trimmed, "Windows Input Experience")) {
        return 1;
    }

    const state: *WindowEnumState = @ptrFromInt(@as(usize, @bitCast(lparam)));
    if (state.list.items.len > 0) {
        state.list.appendSlice(state.allocator, ", ") catch return 1;
    }
    state.list.appendSlice(state.allocator, "[") catch return 1;
    state.list.appendSlice(state.allocator, trimmed) catch return 1;
    state.list.appendSlice(state.allocator, "]") catch return 1;

    return 1;
}

pub fn getOpenWindowsSummary(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag != .windows) return try allocator.dupe(u8, "Рабочий стол");

    var state = WindowEnumState{
        .allocator = allocator,
        .list = std.ArrayList(u8).empty,
    };
    errdefer state.list.deinit(allocator);

    _ = win_c.EnumWindows(enumWindowsCallback, @as(win_c.LPARAM, @bitCast(@intFromPtr(&state))));

    if (state.list.items.len == 0) {
        return try allocator.dupe(u8, "Рабочий стол Windows");
    }

    return state.list.toOwnedSlice(allocator);
}

pub fn getLiveScreenContext(allocator: std.mem.Allocator) ![]const u8 {
    while (g_screen_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
        std.atomic.spinLoopHint();
    }
    defer g_screen_lock.store(false, .release);

    if (g_live_screen_len > 0) {
        return try allocator.dupe(u8, g_live_screen_description[0..g_live_screen_len]);
    }
    if (g_live_window_len > 0) {
        return try std.fmt.allocPrint(allocator, "Открыто окно «{s}».", .{g_live_window_title[0..g_live_window_len]});
    }
    return try allocator.dupe(u8, "Рабочий стол Windows.");
}

pub fn getLiveActiveWindowTitle(allocator: std.mem.Allocator) ![]const u8 {
    while (g_screen_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
        std.atomic.spinLoopHint();
    }
    defer g_screen_lock.store(false, .release);

    if (g_live_window_len > 0) {
        return try allocator.dupe(u8, g_live_window_title[0..g_live_window_len]);
    }
    return try allocator.dupe(u8, "Рабочий стол");
}

pub fn startContinuousVisionWatcher(allocator: std.mem.Allocator) void {
    const VisionWorker = struct {
        fn loop(alloc: std.mem.Allocator) void {
            var last_title_buf: [512]u8 = std.mem.zeroes([512]u8);
            var last_title_len: usize = 0;
            var iterations: u32 = 0;

            while (true) {
                if (builtin.os.tag == .windows) {
                    win_c.Sleep(2000);
                } else {
                    std.time.sleep(2000 * std.time.ns_per_ms);
                }
                iterations += 1;

                // 1. Get current active foreground window
                var current_title_buf: [512]u8 = std.mem.zeroes([512]u8);
                var current_title_len: usize = 0;

                if (builtin.os.tag == .windows) {
                    const hwnd = win_c.GetForegroundWindow();
                    if (hwnd != null) {
                        var w_title: [512]u16 = undefined;
                        const w_len = win_c.GetWindowTextW(hwnd, @as([*c]u16, @ptrCast(&w_title)), 512);
                        if (w_len > 0) {
                            if (std.unicode.utf16LeToUtf8(&current_title_buf, w_title[0..@intCast(w_len)])) |u8_l| {
                                current_title_len = u8_l;
                            } else |_| {}
                        }
                    }
                }

                const window_changed = (current_title_len != last_title_len or
                    !std.mem.eql(u8, current_title_buf[0..current_title_len], last_title_buf[0..last_title_len]));

                if (window_changed) {
                    if (current_title_len > 0) {
                        @memcpy(last_title_buf[0..current_title_len], current_title_buf[0..current_title_len]);
                    }
                    last_title_len = current_title_len;
                }

                if (window_changed or (iterations % 3 == 0)) {
                    var arena = std.heap.ArenaAllocator.init(alloc);
                    defer arena.deinit();
                    const a = arena.allocator();

                    const desc = lookAtScreen(a) catch "";

                    while (g_screen_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
                        std.atomic.spinLoopHint();
                    }
                    if (desc.len > 0) {
                        const copy_len = @min(desc.len, 2040);
                        @memcpy(g_live_screen_description[0..copy_len], desc[0..copy_len]);
                        g_live_screen_len = copy_len;
                    }
                    if (current_title_len > 0) {
                        const copy_w_len = @min(current_title_len, 500);
                        @memcpy(g_live_window_title[0..copy_w_len], current_title_buf[0..copy_w_len]);
                        g_live_window_len = copy_w_len;
                    }
                    g_screen_lock.store(false, .release);
                }
            }
        }
    };

    const t = std.Thread.spawn(.{}, VisionWorker.loop, .{allocator}) catch return;
    t.detach();
}

pub fn lookAtScreen(allocator: std.mem.Allocator) ![]const u8 {
    // 1. Capture screen bmp
    _ = capture_screen_bmp("cache_screen.bmp");

    // 2. Active foreground window
    var active_title_buf: [512]u8 = undefined;
    var active_title_len: usize = 0;
    if (builtin.os.tag == .windows) {
        const hwnd = win_c.GetForegroundWindow();
        if (hwnd != null) {
            var fg_title: [512]u16 = undefined;
            const len = win_c.GetWindowTextW(hwnd, @as([*c]u16, @ptrCast(&fg_title)), 512);
            if (len > 0) {
                if (std.unicode.utf16LeToUtf8(&active_title_buf, fg_title[0..@intCast(len)])) |u8_len| {
                    active_title_len = u8_len;
                } else |_| {}
            }
        }
    }
    const active_name = if (active_title_len > 0) active_title_buf[0..active_title_len] else "Рабочий стол";

    // 3. Enumerate all visible open windows
    const open_windows = getOpenWindowsSummary(allocator) catch try allocator.dupe(u8, "Рабочий стол");
    defer allocator.free(open_windows);

    return try std.fmt.allocPrint(allocator,
        "На экране сейчас открыты следующие окна: {s}. Активное окно в фокусе пользователя: «{s}».",
        .{ open_windows, active_name },
    );
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
