const builtin = @import("builtin");

pub const c = @cImport({
    if (builtin.os.tag == .windows) {
        @cInclude("windows.h");
        @cInclude("shellapi.h");
        @cInclude("mmdeviceapi.h");
        @cInclude("endpointvolume.h");
    } else {
        @cInclude("sys/socket.h");
        @cInclude("sys/un.h");
        @cInclude("unistd.h");
    }
    @cInclude("miniaudio.h");
});
