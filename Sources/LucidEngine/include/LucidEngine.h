// Realtime denoise engine: physical mic -> DPDFNet (via sherpa-onnx) -> LucidMic Feed.
//
// The audio thread only moves samples through lock-free rings; a real-time worker thread
// runs the model, because ONNX Runtime allocates and must never run on the IO thread.
#pragma once

#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct LucidEngine LucidEngine;

/// Where the IOProc finds the mic (input) and the feed (output) in the aggregate's buffer lists.
typedef struct LucidRouting {
    uint32_t inputBuffer;       // mic stream index in the input list (channel 0 is used)
    uint32_t outputFirstBuffer; // first feed stream index in the output list
    uint32_t outputBufferCount; // number of feed streams
} LucidRouting;

/// Loads the DPDFNet 48 kHz model. Returns NULL if the model cannot be loaded.
LucidEngine *lucid_engine_create(LucidRouting routing, const char *modelPath);
void lucid_engine_destroy(LucidEngine *engine);

/// Output lags input by this many samples at 48 kHz (model 40 ms + 20 ms hand-off buffer).
uint32_t lucid_engine_latency_frames(void);

/// Noise removal on (false) or off (true). Safe from any thread while audio runs; the switch
/// crossfades over 10 ms and keeps the same latency, so it is click-free mid-recording.
void lucid_engine_set_bypass(LucidEngine *engine, bool bypass);

/// Offline/synchronous processing on the caller's thread (tests, file tool). Mono 48 kHz, any block size.
/// Do not call while the live worker runs.
void lucid_engine_process(LucidEngine *engine, const float *in, float *out, uint32_t frames);

/// Live mode: starts the worker thread and registers lucid_engine_ioproc on an aggregate device.
OSStatus lucid_engine_start_live(LucidEngine *engine, AudioObjectID device, AudioDeviceIOProcID *outProc);
/// Starts only the model's worker thread (lucid_engine_start_live does this for you).
bool lucid_engine_start_worker(LucidEngine *engine);
/// Stops the worker thread (call after AudioDeviceStop; lucid_engine_destroy also does it).
void lucid_engine_stop_worker(LucidEngine *engine);

/// The realtime IOProc. Public so tests can drive live mode without audio hardware.
OSStatus lucid_engine_ioproc(AudioObjectID device, const AudioTimeStamp *now, const AudioBufferList *input,
                             const AudioTimeStamp *inputTime, AudioBufferList *output,
                             const AudioTimeStamp *outputTime, void *clientData);

/// Samples the audio thread had to fill with silence because the worker was late (health counter).
uint64_t lucid_engine_underruns(const LucidEngine *engine);
