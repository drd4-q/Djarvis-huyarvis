const std = @import("std");
const builtin = @import("builtin");

pub var should_exit: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

const win_c = if (builtin.os.tag == .windows) @cImport({
    @cInclude("windows.h");
    @cInclude("shellapi.h");
}) else struct {};

const WM_TRAYICON: u32 = if (builtin.os.tag == .windows) (win_c.WM_USER + 100) else 0x464;

const ID_TRAY_SHOW: usize = 1001;
const ID_TRAY_HIDE: usize = 1002;
const ID_TRAY_STATUS: usize = 1003;
const ID_TRAY_EXIT: usize = 1004;

var g_hwnd: ?*anyopaque = null;
var g_nid: if (builtin.os.tag == .windows) win_c.NOTIFYICONDATAW else [64]u8 = undefined;
var g_tray_inited: bool = false;

pub fn showConsole(show: bool) void {
    if (builtin.os.tag != .windows) {
        std.debug.print("[Tray Mock] Console visibility: {any}\n", .{show});
        return;
    }

    const console_hwnd = win_c.GetConsoleWindow();
    if (console_hwnd != null) {
        _ = win_c.ShowWindow(console_hwnd, if (show) win_c.SW_SHOW else win_c.SW_HIDE);
        if (show) {
            _ = win_c.SetForegroundWindow(console_hwnd);
        }
    }
}

pub fn toggleConsole() void {
    if (builtin.os.tag != .windows) return;
    const console_hwnd = win_c.GetConsoleWindow();
    if (console_hwnd != null) {
        const is_visible = win_c.IsWindowVisible(console_hwnd) != 0;
        showConsole(!is_visible);
    }
}

fn removeTrayIcon() void {
    if (builtin.os.tag == .windows and g_tray_inited) {
        _ = win_c.Shell_NotifyIconW(win_c.NIM_DELETE, &g_nid);
        g_tray_inited = false;
    }
}

fn wndProc(hwnd: win_c.HWND, msg: win_c.UINT, wparam: win_c.WPARAM, lparam: win_c.LPARAM) callconv(.c) win_c.LRESULT {
    if (builtin.os.tag != .windows) return 0;

    switch (msg) {
        WM_TRAYICON => {
            const ev: win_c.UINT = @intCast(lparam);
            switch (ev) {
                win_c.WM_RBUTTONUP, win_c.WM_CONTEXTMENU => {
                    var pt: win_c.POINT = undefined;
                    _ = win_c.GetCursorPos(&pt);

                    const hMenu = win_c.CreatePopupMenu();
                    _ = win_c.AppendMenuW(hMenu, win_c.MF_STRING | win_c.MF_GRAYED, ID_TRAY_STATUS, std.unicode.utf8ToUtf16LeStringLiteral("⚡ Jarvis AI: Активен"));
                    _ = win_c.AppendMenuW(hMenu, win_c.MF_SEPARATOR, 0, null);
                    _ = win_c.AppendMenuW(hMenu, win_c.MF_STRING, ID_TRAY_SHOW, std.unicode.utf8ToUtf16LeStringLiteral("Показать консоль"));
                    _ = win_c.AppendMenuW(hMenu, win_c.MF_STRING, ID_TRAY_HIDE, std.unicode.utf8ToUtf16LeStringLiteral("Скрыть в трей"));
                    _ = win_c.AppendMenuW(hMenu, win_c.MF_SEPARATOR, 0, null);
                    _ = win_c.AppendMenuW(hMenu, win_c.MF_STRING, ID_TRAY_EXIT, std.unicode.utf8ToUtf16LeStringLiteral("Выход"));

                    _ = win_c.SetForegroundWindow(hwnd);
                    _ = win_c.TrackPopupMenu(hMenu, win_c.TPM_BOTTOMALIGN | win_c.TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, null);
                    _ = win_c.DestroyMenu(hMenu);
                },
                win_c.WM_LBUTTONDBLCLK => {
                    toggleConsole();
                },
                else => {},
            }
            return 0;
        },
        win_c.WM_COMMAND => {
            const cmd: usize = @intCast(wparam & 0xFFFF);
            switch (cmd) {
                ID_TRAY_SHOW => {
                    showConsole(true);
                },
                ID_TRAY_HIDE => {
                    showConsole(false);
                },
                ID_TRAY_EXIT => {
                    should_exit.store(true, .release);
                    removeTrayIcon();
                    _ = win_c.PostQuitMessage(0);
                },
                else => {},
            }
            return 0;
        },
        win_c.WM_DESTROY => {
            removeTrayIcon();
            _ = win_c.PostQuitMessage(0);
            return 0;
        },
        else => return win_c.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

pub fn runTrayLoop() void {
    if (builtin.os.tag != .windows) {
        std.debug.print("[Tray Mock] Tray loop running\n", .{});
        return;
    }

    const hr = win_c.CoInitializeEx(null, win_c.COINIT_APARTMENTTHREADED);
    defer if (hr == win_c.S_OK or hr == win_c.S_FALSE) win_c.CoUninitialize();

    const hInstance = win_c.GetModuleHandleW(null);
    const className = std.unicode.utf8ToUtf16LeStringLiteral("JarvisTrayWindowClass");

    var wc: win_c.WNDCLASSEXW = std.mem.zeroes(win_c.WNDCLASSEXW);
    wc.cbSize = @sizeOf(win_c.WNDCLASSEXW);
    wc.lpfnWndProc = wndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = className;

    const class_atom = win_c.RegisterClassExW(&wc);
    std.debug.print("[Tray] RegisterClassExW atom: {d}\n", .{class_atom});

    const hwnd = win_c.CreateWindowExW(
        0,
        className,
        std.unicode.utf8ToUtf16LeStringLiteral("JarvisTrayWindow"),
        0,
        0,
        0,
        0,
        0,
        null,
        null,
        hInstance,
        null,
    );

    if (hwnd == null) {
        std.debug.print("[Tray Error] CreateWindowExW failed (err: {d})\n", .{win_c.GetLastError()});
        return;
    }
    g_hwnd = hwnd;
    std.debug.print("[Tray] Window created: {*} \n", .{hwnd});

    // Initialize Notification Icon
    g_nid = std.mem.zeroes(win_c.NOTIFYICONDATAW);
    g_nid.cbSize = @sizeOf(win_c.NOTIFYICONDATAW);
    g_nid.hWnd = hwnd;
    g_nid.uID = 1;
    g_nid.uFlags = win_c.NIF_MESSAGE | win_c.NIF_TIP;
    g_nid.uCallbackMessage = WM_TRAYICON;

    var hIcon: ?win_c.HICON = win_c.LoadIconW(null, @as([*c]const u16, @ptrFromInt(32512))); // IDI_APPLICATION
    if (hIcon == null) {
        hIcon = win_c.LoadIconW(null, @as([*c]const u16, @ptrFromInt(32516))); // IDI_INFORMATION
    }
    if (hIcon) |hi| {
        g_nid.hIcon = hi;
        g_nid.uFlags |= win_c.NIF_ICON;
    }

    const tip_text = std.unicode.utf8ToUtf16LeStringLiteral("Jarvis AI Assistant");
    @memcpy(g_nid.szTip[0..tip_text.len], tip_text);

    const res = win_c.Shell_NotifyIconW(win_c.NIM_ADD, &g_nid);
    std.debug.print("[Tray] Shell_NotifyIconW NIM_ADD result: {d}\n", .{res});
    if (res != 0) {
        g_tray_inited = true;
        std.debug.print("[Tray] Tray icon successfully added to notification area!\n", .{});
    } else {
        std.debug.print("[Tray Warning] Shell_NotifyIconW failed (err: {d})\n", .{win_c.GetLastError()});
    }

    var msg: win_c.MSG = std.mem.zeroes(win_c.MSG);
    while (win_c.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = win_c.TranslateMessage(&msg);
        _ = win_c.DispatchMessageW(&msg);
    }

    removeTrayIcon();
    std.debug.print("[Tray] Tray message loop ended\n", .{});
}

pub fn startTrayThread() !std.Thread {
    return try std.Thread.spawn(.{}, runTrayLoop, .{});
}
