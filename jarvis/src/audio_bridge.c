#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include "audio_bridge.h"
#include <string.h>

static ma_device g_capture_device;
static ma_device g_playback_device;
static int g_capture_inited = 0;
static int g_playback_inited = 0;

static audio_capture_callback_t g_on_capture = NULL;
static audio_playback_callback_t g_on_playback = NULL;
static void* g_user_data = NULL;

static void capture_cb(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    (void)pOutput;
    (void)pDevice;
    if (g_on_capture && pInput && frameCount > 0) {
        g_on_capture((const int16_t*)pInput, frameCount, g_user_data);
    }
}

static void playback_cb(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    (void)pInput;
    (void)pDevice;
    if (pOutput && frameCount > 0) {
        if (g_on_playback) {
            g_on_playback((int16_t*)pOutput, frameCount, g_user_data);
        } else {
            memset(pOutput, 0, frameCount * sizeof(int16_t));
        }
    }
}

int audio_bridge_init(
    audio_capture_callback_t on_capture,
    audio_playback_callback_t on_playback,
    void* user_data
) {
    g_on_capture = on_capture;
    g_on_playback = on_playback;
    g_user_data = user_data;

    // Capture: 16000 Hz, 1 channel (mono), 16-bit PCM (Whisper standard)
    ma_device_config cap_cfg = ma_device_config_init(ma_device_type_capture);
    cap_cfg.capture.format = ma_format_s16;
    cap_cfg.capture.channels = 1;
    cap_cfg.sampleRate = 16000;
    cap_cfg.dataCallback = capture_cb;

    if (ma_device_init(NULL, &cap_cfg, &g_capture_device) == MA_SUCCESS) {
        g_capture_inited = 1;
    }

    // Playback: 24000 Hz, 1 channel (mono), 16-bit PCM (Piper TTS standard)
    ma_device_config play_cfg = ma_device_config_init(ma_device_type_playback);
    play_cfg.playback.format = ma_format_s16;
    play_cfg.playback.channels = 1;
    play_cfg.sampleRate = 24000;
    play_cfg.dataCallback = playback_cb;

    if (ma_device_init(NULL, &play_cfg, &g_playback_device) == MA_SUCCESS) {
        g_playback_inited = 1;
    }

    return (g_capture_inited || g_playback_inited) ? 0 : -1;
}

int audio_bridge_start(void) {
    if (g_capture_inited) {
        if (ma_device_start(&g_capture_device) != MA_SUCCESS) {
            return -1;
        }
    }
    if (g_playback_inited) {
        if (ma_device_start(&g_playback_device) != MA_SUCCESS) {
            return -1;
        }
    }
    return 0;
}

void audio_bridge_stop(void) {
    if (g_capture_inited) ma_device_stop(&g_capture_device);
    if (g_playback_inited) ma_device_stop(&g_playback_device);
}

void audio_bridge_deinit(void) {
    audio_bridge_stop();
    if (g_capture_inited) {
        ma_device_uninit(&g_capture_device);
        g_capture_inited = 0;
    }
    if (g_playback_inited) {
        ma_device_uninit(&g_playback_device);
        g_playback_inited = 0;
    }
}
