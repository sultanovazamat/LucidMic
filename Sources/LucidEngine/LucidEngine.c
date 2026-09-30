#include "LucidEngine.h"

#include <rnnoise.h>
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
};

uint32_t lucid_engine_latency_frames(void) { return kFrame; }

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
            rnnoise_process_frame(e->rnnoise, denoised, e->inFrame);
            for (uint32_t k = 0; k < kFrame; ++k) {
                e->out[(e->outRead + e->outCount) % kOutCapacity] = denoised[k] / 32768.0f;
                e->outCount++;
            }
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
