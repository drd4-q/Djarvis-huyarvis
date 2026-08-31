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
    WindowNotFound,
    ShellExecuteFailed,
    UnsupportedPlatform,
    InvalidUtf8,
    LockWorkStationFailed,
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
    defer _ = pEnumerator.?.lpVtbl.*.Release.?(@as(*win_c.IUnknown, @ptrCast(pEnumerator.?)));

    var pDevice: ?*win_c.IMMDevice = null;
    if (pEnumerator.?.lpVtbl.*.GetDefaultAudioEndpoint.?(pEnumerator.?, win_c.eRender, win_c.eMultimedia, &pDevice) != win_c.S_OK) {
        return Win32Error.DefaultDeviceFailed;
    }
    defer _ = pDevice.?.lpVtbl.*.Release.?(@as(*win_c.IUnknown, @ptrCast(pDevice.?)));

    var pVolume: ?*win_c.IAudioEndpointVolume = null;
    const iid_vol = @as(*const win_c.GUID, @ptrCast(&IID_IAudioEndpointVolume_GUID));
    if (pDevice.?.lpVtbl.*.Activate.?(pDevice.?, iid_vol, win_c.CLSCTX_INPROC_SERVER, null, @as(*?*anyopaque, @ptrCast(&pVolume))) != win_c.S_OK) {
        return Win32Error.ActivateVolumeFailed;
    }
    defer _ = pVolume.?.lpVtbl.*.Release.?(@as(*win_c.IUnknown, @ptrCast(pVolume.?)));

    const clamped = std.math.clamp(scalar, 0.0, 1.0);
    if (pVolume.?.lpVtbl.*.SetMasterVolumeLevelScalar.?(pVolume.?, clamped, null) != win_c.S_OK) {
        return Win32Error.SetVolumeFailed;
    }

    if (mute) |is_muted| {
        const mute_val: win_c.BOOL = if (is_muted) 1 else 0;
        _ = pVolume.?.lpVtbl.*.SetMute.?(pVolume.?, mute_val, null);
    }
}

pub fn lockWorkstation() !void {
    if (builtin.os.tag != .windows) {
        std.debug.print("[Win32 Mock] Lock workstation called\n", .{});
        return;
    }

    if (win_c.LockWorkStation() == 0) {
        return error.LockWorkStationFailed;
    }
}

pub fn sendMediaKey(key: MediaKey) !void {
    if (builtin.os.tag != .windows) {
        std.debug.print("[Win32 Mock] Media key pressed: {s}\n", .{@tagName(key)});
        return;
    }

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

const WindowSearchContext = struct {
    needle_utf16: [256]u16,
    needle_len: usize,
    found_hwnd: ?*anyopaque = null,
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
        fn enumProc(hwnd: ?win_c.HWND, lparam: win_c.LPARAM) callconv(.c) win_c.BOOL {
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
        const hwnd: win_c.HWND = @ptrCast(hwnd_ptr);
        _ = win_c.ShowWindow(hwnd, win_c.SW_RESTORE);
        _ = win_c.SetForegroundWindow(hwnd);
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

extern fn popen(command: [*:0]const u8, modes: [*:0]const u8) ?*anyopaque;
extern fn pclose(stream: ?*anyopaque) c_int;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, stream: ?*anyopaque) usize;
extern fn time(timer: ?*i64) i64;
extern fn ctime(timer: *const i64) ?[*:0]const u8;

pub fn executeCommand(allocator: std.mem.Allocator, command: []const u8) ![]const u8 {
    var cmd_z = try allocator.allocSentinel(u8, command.len, 0);
    defer allocator.free(cmd_z);
    @memcpy(cmd_z[0..command.len], command);

    const stream = popen(cmd_z.ptr, "r") orelse return error.PopenFailed;
    defer _ = pclose(stream);

    var output = try allocator.alloc(u8, 4096);
    const n = fread(output.ptr, 1, 4095, stream);
    return output[0..n];
}

pub fn getSystemInfo(allocator: std.mem.Allocator) ![]const u8 {
    var t: i64 = 0;
    _ = time(&t);
    const time_str = if (ctime(&t)) |s| std.mem.span(s) else "unknown";
    const trimmed_time = std.mem.trim(u8, time_str, "\r\n");

    return try std.fmt.allocPrint(allocator,
        "OS: {s}, Arch: {s}, Local Time: {s}",
        .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch), trimmed_time }
    );
}

