#ifndef AUDIO_BRIDGE_H
#define AUDIO_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*audio_capture_callback_t)(const int16_t* samples, uint32_t frame_count, void* user_data);
typedef void (*audio_playback_callback_t)(int16_t* samples, uint32_t frame_count, void* user_data);

int audio_bridge_init(
    audio_capture_callback_t on_capture,
    audio_playback_callback_t on_playback,
    void* user_data
);

int audio_bridge_start(void);
void audio_bridge_stop(void);
void audio_bridge_deinit(void);

int capture_screen_bmp(const char* filepath);

#ifdef __cplusplus
}
#endif

#endif
