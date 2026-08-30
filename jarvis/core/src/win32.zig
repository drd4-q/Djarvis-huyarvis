const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig").c;

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
    WindowNotFound,
    ShellExecuteFailed,
    UnsupportedPlatform,
};

// GUID constants for Windows Core Audio COM API
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

    const hr = c.CoInitializeEx(null, c.COINIT_APARTMENTTHREADED);
    defer if (hr == c.S_OK or hr == c.S_FALSE) c.CoUninitialize();

    var pEnumerator: ?*c.IMMDeviceEnumerator = null;
    const clsid = @as(*const c.GUID, @ptrCast(&CLSID_MMDeviceEnumerator_GUID));
    const iid_enum = @as(*const c.GUID, @ptrCast(&IID_IMMDeviceEnumerator_GUID));

    if (c.CoCreateInstance(clsid, null, c.CLSCTX_INPROC_SERVER, iid_enum, @as(*?*anyopaque, @ptrCast(&pEnumerator))) != c.S_OK) {
        return Win32Error.DeviceEnumeratorFailed;
    }
    defer _ = pEnumerator.?.lpVtbl.*.Release.?(@as(*c.IUnknown, @ptrCast(pEnumerator.?)));

    var pDevice: ?*c.IMMDevice = null;
    if (pEnumerator.?.lpVtbl.*.GetDefaultAudioEndpoint.?(pEnumerator.?, c.eRender, c.eMultimedia, &pDevice) != c.S_OK) {
        return Win32Error.DefaultDeviceFailed;
    }
    defer _ = pDevice.?.lpVtbl.*.Release.?(@as(*c.IUnknown, @ptrCast(pDevice.?)));

    var pVolume: ?*c.IAudioEndpointVolume = null;
    const iid_vol = @as(*const c.GUID, @ptrCast(&IID_IAudioEndpointVolume_GUID));
    if (pDevice.?.lpVtbl.*.Activate.?(pDevice.?, iid_vol, c.CLSCTX_INPROC_SERVER, null, @as(*?*anyopaque, @ptrCast(&pVolume))) != c.S_OK) {
        return Win32Error.ActivateVolumeFailed;
    }
    defer _ = pVolume.?.lpVtbl.*.Release.?(@as(*c.IUnknown, @ptrCast(pVolume.?)));

    const clamped = std.math.clamp(scalar, 0.0, 1.0);
    if (pVolume.?.lpVtbl.*.SetMasterVolumeLevelScalar.?(pVolume.?, clamped, null) != c.S_OK) {
        return Win32Error.SetVolumeFailed;
    }

    if (mute) |is_muted| {
        const mute_val: c.BOOL = if (is_muted) 1 else 0;
        _ = pVolume.?.lpVtbl.*.SetMute.?(pVolume.?, mute_val, null);
    }
}

pub fn lockWorkstation() !void {
    if (builtin.os.tag != .windows) {
        std.debug.print("[Win32 Mock] Lock workstation called\n", .{});
        return;
    }

    if (c.LockWorkStation() == 0) {
        return error.LockWorkStationFailed;
    }
}

pub fn sendMediaKey(key: MediaKey) !void {
    if (builtin.os.tag != .windows) {
        std.debug.print("[Win32 Mock] Media key pressed: {s}\n", .{@tagName(key)});
        return;
    }

    const vk: c.WORD = switch (key) {
        .play_pause => 0xB3, // VK_MEDIA_PLAY_PAUSE
        .next => 0xB0,       // VK_MEDIA_NEXT_TRACK
        .prev => 0xB1,       // VK_MEDIA_PREV_TRACK
        .vol_up => 0xAF,     // VK_VOLUME_UP
        .vol_down => 0xAE,   // VK_VOLUME_DOWN
        .mute => 0xAD,       // VK_VOLUME_MUTE
    };

    var inputs: [2]c.INPUT = std.mem.zeroes([2]c.INPUT);
    inputs[0].type = c.INPUT_KEYBOARD;
    inputs[0].unnamed_0.ki.wVk = vk;

    inputs[1].type = c.INPUT_KEYBOARD;
    inputs[1].unnamed_0.ki.wVk = vk;
    inputs[1].unnamed_0.ki.dwFlags = c.KEYEVENTF_KEYUP;

    _ = c.SendInput(2, &inputs[0], @sizeOf(c.INPUT));
}

const WindowSearchContext = struct {
    needle_utf16: [256]u16,
    needle_len: usize,
    found_hwnd: ?c.HWND = null,
};

pub fn focusWindow(allocator: std.mem.Allocator, title_contains: []const u8) !void {
    _ = allocator;
    if (builtin.os.tag != .windows) {
        std.debug.print("[Win32 Mock] Focus window: {s}\n", .{title_contains});
        return;
    }

    var ctx: WindowSearchContext = .{
        .needle_utf16 = undefined,
        .needle_len = 0,
        .found_hwnd = null,
    };

    const utf16_len = std.unicode.utf8ToUtf16Le(&ctx.needle_utf16, title_contains) catch return error.InvalidUtf8;
    ctx.needle_len = utf16_len;

    const callback = struct {
        fn enumProc(hwnd: ?c.HWND, lparam: c.LPARAM) callconv(.c) c.BOOL {
            const search_ctx: *WindowSearchContext = @ptrFromInt(@as(usize, @bitCast(lparam)));
            var title_buf: [512]u16 = undefined;
            const len = c.GetWindowTextW(hwnd, @as([*c]u16, @ptrCast(&title_buf)), 512);
            if (len <= 0) return 1;

            const title_slice = title_buf[0..@as(usize, @intCast(len))];
            const needle = search_ctx.needle_utf16[0..search_ctx.needle_len];

            // Case-insensitive substring search
            if (std.mem.indexOf(u16, title_slice, needle) != null) {
                search_ctx.found_hwnd = hwnd;
                return 0; // Stop enumeration
            }
            return 1;
        }
    }.enumProc;

    _ = c.EnumWindows(callback, @as(c.LPARAM, @bitCast(@intFromPtr(&ctx))));

    if (ctx.found_hwnd) |hwnd| {
        _ = c.ShowWindow(hwnd, c.SW_RESTORE);
        _ = c.SetForegroundWindow(hwnd);
    } else {
        return Win32Error.WindowNotFound;
    }
}

pub fn openApp(allocator: std.mem.Allocator, path: []const u8, args: ?[]const u8) !void {
    _ = allocator;
    if (builtin.os.tag != .windows) {
        std.debug.print("[Win32 Mock] Open app: {s} args: {any}\n", .{ path, args });
        return;
    }

    var path_w: [512]u16 = undefined;
    _ = std.unicode.utf8ToUtf16Le(&path_w, path) catch return error.InvalidUtf8;

    var args_w: [512]u16 = undefined;
    var args_ptr: ?[*:0]const u16 = null;
    if (args) |a| {
        _ = std.unicode.utf8ToUtf16Le(&args_w, a) catch return error.InvalidUtf8;
        args_ptr = @as([*:0]const u16, @ptrCast(&args_w));
    }

    const res = c.ShellExecuteW(
        null,
        std.unicode.utf8ToUtf16LeStringLiteral("open"),
        @as([*:0]const u16, @ptrCast(&path_w)),
        args_ptr,
        null,
        c.SW_SHOWNORMAL,
    );

    if (@intFromPtr(res) <= 32) {
        return Win32Error.ShellExecuteFailed;
    }
}
