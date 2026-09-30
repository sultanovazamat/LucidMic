// Realtime denoise engine: physical mic -> RNNoise -> virtual mic (BlackHole).
#pragma once

#include <CoreAudio/CoreAudio.h>
#include <stdint.h>

typedef struct LucidEngine LucidEngine;

/// Where the IOProc finds the mic (input) and the virtual mic (output) in the aggregate's buffer lists.
typedef struct LucidRouting {
    uint32_t inputBuffer;       // mic stream index in the input list (channel 0 is used)
    uint32_t outputFirstBuffer; // first virtual-mic stream index in the output list
    uint32_t outputBufferCount; // number of virtual-mic streams
} LucidRouting;

LucidEngine *lucid_engine_create(LucidRouting routing);
void lucid_engine_destroy(LucidEngine *engine);

/// Mono 48 kHz in -> denoised mono out, any block size. Output lags input by lucid_engine_latency_frames().
void lucid_engine_process(LucidEngine *engine, const float *in, float *out, uint32_t frames);
uint32_t lucid_engine_latency_frames(void);

/// Registers the engine's IOProc on an aggregate device.
OSStatus lucid_engine_create_ioproc(AudioObjectID device, LucidEngine *engine, AudioDeviceIOProcID *outProc);
