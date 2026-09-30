#include "LucidEngine.h"

#include <rnnoise.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

enum {
    kFrame = 480,        // RNNoise frame: 10 ms at 48 kHz
    kMaxBlock = 8192,    // largest IO buffer we handle
    kOutCapacity = 16384 // >= kFrame + kMaxBlock
};

struct LucidEngine {
    LucidRouting routing;
    DenoiseState *rnnoise;
    float inFrame[kFrame];
    uint32_t inCount;
    float out[kOutCapacity]; // FIFO of denoised samples
    uint32_t outRead, outCount;
    float scratchIn[kMaxBlock], scratchOut[kMaxBlock];
    _Atomic bool bypass;
    float wet;                // 1 = denoised, 0 = original; ramps on switch
    float dry[2][kFrame];     // last two input frames: RNNoise itself delays audio by two frames
    uint32_t dryIndex;
};

// One frame of FIFO priming plus RNNoise's own two-frame delay (measured: 1440 samples = 30 ms).
uint32_t lucid_engine_latency_frames(void) { return 3 * kFrame; }

void lucid_engine_set_bypass(LucidEngine *e, bool bypass) {
    atomic_store_explicit(&e->bypass, bypass, memory_order_relaxed);
}

LucidEngine *lucid_engine_create(LucidRouting routing) {
    LucidEngine *e = calloc(1, sizeof(LucidEngine));
    if (!e) return NULL;
    e->routing = routing;
    e->rnnoise = rnnoise_create(NULL);
    if (!e->rnnoise) {
        free(e);
        return NULL;
    }
    e->outCount = kFrame; // prime with one frame of silence so output never underruns
    e->wet = 1.0f;
    atomic_init(&e->bypass, false);
    return e;
}

void lucid_engine_destroy(LucidEngine *e) {
    if (!e) return;
    rnnoise_destroy(e->rnnoise);
    free(e);
}

static void process_block(LucidEngine *e, const float *in, float *out, uint32_t frames) {
    float denoised[kFrame];
    for (uint32_t i = 0; i < frames; ++i) {
        e->inFrame[e->inCount++] = in[i] * 32768.0f; // RNNoise works in 16-bit sample scale
        if (e->inCount == kFrame) {
            rnnoise_process_frame(e->rnnoise, denoised, e->inFrame);  // always run: keeps the model warm
            const float *original = e->dry[e->dryIndex];  // input from two frames ago, aligned with `denoised`
            const float target = atomic_load_explicit(&e->bypass, memory_order_relaxed) ? 0.0f : 1.0f;
            for (uint32_t k = 0; k < kFrame; ++k) {
                const float wet = e->wet + (target - e->wet) * (float)(k + 1) / kFrame;
                const float sample = wet * denoised[k] + (1.0f - wet) * original[k];
                e->out[(e->outRead + e->outCount) % kOutCapacity] = sample / 32768.0f;
                e->outCount++;
            }
            e->wet = target;
            memcpy(e->dry[e->dryIndex], e->inFrame, sizeof(e->inFrame));
            e->dryIndex ^= 1;
            e->inCount = 0;
        }
    }
    for (uint32_t i = 0; i < frames; ++i) {
        if (e->outCount == 0) { // cannot happen given priming; stay safe
            out[i] = 0.0f;
            continue;
        }
        out[i] = e->out[e->outRead];
        e->outRead = (e->outRead + 1) % kOutCapacity;
        e->outCount--;
    }
}

void lucid_engine_process(LucidEngine *e, const float *in, float *out, uint32_t frames) {
    // Chunk so the output FIFO (kOutCapacity) can never overflow, whatever the caller's block size.
    while (frames > 0) {
        const uint32_t n = frames < kMaxBlock ? frames : kMaxBlock;
        process_block(e, in, out, n);
        in += n;
        out += n;
        frames -= n;
    }
}

static OSStatus ioproc(AudioObjectID device, const AudioTimeStamp *now, const AudioBufferList *input,
                       const AudioTimeStamp *inputTime, AudioBufferList *output, const AudioTimeStamp *outputTime,
                       void *clientData) {
    (void)device; (void)now; (void)inputTime; (void)outputTime;
    LucidEngine *e = clientData;
    const LucidRouting r = e->routing;

    for (UInt32 b = 0; b < output->mNumberBuffers; ++b) {
        if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    }
    if (!input || r.inputBuffer >= input->mNumberBuffers) return noErr;

    const AudioBuffer *in = &input->mBuffers[r.inputBuffer];
    const UInt32 inCh = in->mNumberChannels ? in->mNumberChannels : 1;
    UInt32 frames = in->mDataByteSize / (sizeof(float) * inCh);
    if (frames > kMaxBlock) frames = kMaxBlock;
    const float *src = in->mData;
    for (UInt32 i = 0; i < frames; ++i) e->scratchIn[i] = src[i * inCh];

    lucid_engine_process(e, e->scratchIn, e->scratchOut, frames);

    for (UInt32 m = 0; m < r.outputBufferCount; ++m) {
        const UInt32 b = r.outputFirstBuffer + m;
        if (b >= output->mNumberBuffers) break;
        AudioBuffer *dst = &output->mBuffers[b];
        const UInt32 ch = dst->mNumberChannels ? dst->mNumberChannels : 1;
        UInt32 n = dst->mDataByteSize / (sizeof(float) * ch);
        if (n > frames) n = frames;
        float *o = dst->mData;
        for (UInt32 i = 0; i < n; ++i) {
            for (UInt32 c = 0; c < ch; ++c) o[i * ch + c] = e->scratchOut[i];
        }
    }
    return noErr;
}

OSStatus lucid_engine_create_ioproc(AudioObjectID device, LucidEngine *engine, AudioDeviceIOProcID *outProc) {
    return AudioDeviceCreateIOProcID(device, ioproc, engine, outProc);
}
