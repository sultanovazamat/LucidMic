#include "LucidEngine.h"

#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_policy.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "sherpa-onnx/c-api/c-api.h"

enum {
    kRate = 48000,
    kChunk = 480,        // DPDFNet hop: 10 ms
    kModelDelay = 1920,  // measured: denoised sample j is input sample j - 1920 (40 ms)
    kHandoff = 1536,     // 32 ms covers the first empty model chunk and every supported IO/hop alignment
    kRingSize = 16384,   // power of two
    kHistory = 8192,     // power of two, > kModelDelay + a few chunks
    kMaxLiveBlock = 512,
};

// Single-producer single-consumer ring of samples.
typedef struct {
    float data[kRingSize];
    _Atomic uint64_t written;
    _Atomic uint64_t read;
} Ring;

static uint32_t ring_push(Ring *r, const float *x, uint32_t n) {
    const uint64_t w = atomic_load_explicit(&r->written, memory_order_relaxed);
    const uint64_t rd = atomic_load_explicit(&r->read, memory_order_acquire);
    const uint32_t space = kRingSize - (uint32_t)(w - rd);
    if (n > space) n = space;
    for (uint32_t i = 0; i < n; ++i) r->data[(w + i) & (kRingSize - 1)] = x[i];
    atomic_store_explicit(&r->written, w + n, memory_order_release);
    return n;
}

static uint32_t ring_pop(Ring *r, float *x, uint32_t n) {
    const uint64_t rd = atomic_load_explicit(&r->read, memory_order_relaxed);
    const uint64_t w = atomic_load_explicit(&r->written, memory_order_acquire);
    const uint32_t available = (uint32_t)(w - rd);
    if (n > available) n = available;
    for (uint32_t i = 0; i < n; ++i) x[i] = r->data[(rd + i) & (kRingSize - 1)];
    atomic_store_explicit(&r->read, rd + n, memory_order_release);
    return n;
}

static uint32_t ring_count(Ring *r) {
    return (uint32_t)(atomic_load_explicit(&r->written, memory_order_acquire) -
                      atomic_load_explicit(&r->read, memory_order_acquire));
}

// Only the ring's consumer may discard samples. Counters stay monotonic across resets.
static void ring_discard(Ring *r) {
    const uint64_t w = atomic_load_explicit(&r->written, memory_order_acquire);
    atomic_store_explicit(&r->read, w, memory_order_release);
}

enum RecoveryState {
    kRunning,
    kWorkerNeedsReset,  // worker found a full output ring; callback must first stop using the rings
    kResetRequested,   // callback is quiescent; worker can discard its input and reset the model
    kResetReady,       // worker is quiescent; callback can discard its output and restart priming
};

struct LucidEngine {
    LucidRouting routing;
    const SherpaOnnxOnlineSpeechDenoiser *model;
    Ring in;   // audio thread -> worker
    Ring out;  // worker -> audio thread
    // Worker-only state.
    float history[kHistory];  // recent input by absolute sample number, for the bypass (original) path
    uint64_t inputCount;
    uint64_t outputCount;
    float wet;  // 1 = denoised, 0 = original; ramps on switch
    _Atomic bool bypass;
    _Atomic uint64_t underruns;
    _Atomic int recovery;
    // Live mode.
    pthread_t worker;
    bool workerRunning;
    _Atomic bool stop;
    dispatch_semaphore_t wake;
    // Callback-only state (the synchronous offline path has the same ownership).
    uint32_t priming;
    float scratchIn[kMaxLiveBlock];
    float scratchOut[kMaxLiveBlock];
};

uint32_t lucid_engine_latency_frames(void) { return kHandoff + kModelDelay; }

void lucid_engine_set_bypass(LucidEngine *e, bool bypass) {
    atomic_store_explicit(&e->bypass, bypass, memory_order_relaxed);
}

uint64_t lucid_engine_underruns(const LucidEngine *e) {
    return atomic_load_explicit(&((LucidEngine *)e)->underruns, memory_order_relaxed);
}

LucidEngine *lucid_engine_create(LucidRouting routing, const char *modelPath) {
    LucidEngine *e = calloc(1, sizeof(LucidEngine));
    if (!e) return NULL;
    SherpaOnnxOnlineSpeechDenoiserConfig config;
    memset(&config, 0, sizeof config);
    config.model.dpdfnet.model = modelPath;
    config.model.num_threads = 1;
    config.model.provider = "cpu";
    e->model = SherpaOnnxCreateOnlineSpeechDenoiser(&config);
    if (!e->model) {
        free(e);
        return NULL;
    }
    e->routing = routing;
    e->wet = 1.0f;
    e->wake = dispatch_semaphore_create(0);
    e->priming = kHandoff;
    return e;
}

void lucid_engine_destroy(LucidEngine *e) {
    if (!e) return;
    lucid_engine_stop_worker(e);
    SherpaOnnxDestroyOnlineSpeechDenoiser(e->model);
    dispatch_release(e->wake);
    free(e);
}

// Mixes denoised samples with the time-aligned original (for the switch) and hands them to the audio thread.
static bool mix_and_push(LucidEngine *e, const float *denoised, int32_t n) {
    const float target = atomic_load_explicit(&e->bypass, memory_order_relaxed) ? 0.0f : 1.0f;
    float mixed[kChunk];
    for (int32_t start = 0; start < n; start += kChunk) {
        const int32_t len = n - start < kChunk ? n - start : kChunk;
        for (int32_t k = 0; k < len; ++k) {
            const uint64_t j = e->outputCount + (uint64_t)(start + k);
            const float original = j >= kModelDelay ? e->history[(j - kModelDelay) & (kHistory - 1)] : 0.0f;
            const float wet = e->wet + (target - e->wet) * (float)(k + 1) / (float)len;
            mixed[k] = wet * denoised[start + k] + (1.0f - wet) * original;
        }
        e->wet = target;
        if (ring_push(&e->out, mixed, (uint32_t)len) != (uint32_t)len) {
            int expected = kRunning;
            atomic_compare_exchange_strong_explicit(&e->recovery, &expected, kWorkerNeedsReset,
                                                     memory_order_release, memory_order_relaxed);
            return false;
        }
    }
    e->outputCount += (uint64_t)n;
    return true;
}

// Runs the model on every complete 10 ms chunk waiting in the input ring.
static void run_model(LucidEngine *e) {
    float chunk[kChunk];
    for (;;) {
        const int recovery = atomic_load_explicit(&e->recovery, memory_order_acquire);
        if (recovery == kResetRequested) {
            // The callback has stopped pushing input. It will not resume until it observes Ready.
            ring_discard(&e->in);
            SherpaOnnxOnlineSpeechDenoiserReset(e->model);
            memset(e->history, 0, sizeof e->history);
            e->inputCount = e->outputCount = 0;
            e->wet = atomic_load_explicit(&e->bypass, memory_order_relaxed) ? 0.0f : 1.0f;
            atomic_store_explicit(&e->recovery, kResetReady, memory_order_release);
            return;
        }
        if (recovery != kRunning || ring_count(&e->in) < kChunk) return;
        if (ring_pop(&e->in, chunk, kChunk) != kChunk) return;
        for (uint32_t k = 0; k < kChunk; ++k) e->history[(e->inputCount + k) & (kHistory - 1)] = chunk[k];
        e->inputCount += kChunk;
        const SherpaOnnxDenoisedAudio *audio = SherpaOnnxOnlineSpeechDenoiserRun(e->model, chunk, kChunk, kRate);
        if (!audio) continue;  // the model returns nothing for its very first chunk
        const bool pushed = mix_and_push(e, audio->samples, audio->n);
        SherpaOnnxDestroyDenoisedAudio(audio);
        if (!pushed) return;
    }
}

static uint32_t take_output(LucidEngine *e, float *out, uint32_t frames) {
    const uint32_t silence = e->priming < frames ? e->priming : frames;
    memset(out, 0, silence * sizeof(float));
    e->priming -= silence;
    return silence + ring_pop(&e->out, out + silence, frames - silence);
}

void lucid_engine_process(LucidEngine *e, const float *in, float *out, uint32_t frames) {
    while (frames > 0) {
        const uint32_t n = frames < 4096 ? frames : 4096;
        ring_push(&e->in, in, n);
        run_model(e);
        const uint32_t got = take_output(e, out, n);
        if (got < n) memset(out + got, 0, (n - got) * sizeof(float));
        in += n;
        out += n;
        frames -= n;
    }
}

// Audio-thread only. A reset never changes the producer's ring counter from the consumer thread.
static void request_recovery(LucidEngine *e) {
    const int recovery = atomic_load_explicit(&e->recovery, memory_order_acquire);
    if (recovery == kRunning || recovery == kWorkerNeedsReset) {
        atomic_store_explicit(&e->recovery, kResetRequested, memory_order_release);
    }
    dispatch_semaphore_signal(e->wake);
}

// Real-time scheduling so the model reliably finishes each 10 ms chunk in time.
static void make_realtime(void) {
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    const double ticksPerMs = 1e6 * (double)tb.denom / (double)tb.numer;
    thread_time_constraint_policy_data_t policy = {
        .period = (uint32_t)(10 * ticksPerMs),
        .computation = (uint32_t)(4 * ticksPerMs),
        .constraint = (uint32_t)(9 * ticksPerMs),
        .preemptible = 1,
    };
    thread_policy_set(pthread_mach_thread_np(pthread_self()), THREAD_TIME_CONSTRAINT_POLICY,
                      (thread_policy_t)&policy, THREAD_TIME_CONSTRAINT_POLICY_COUNT);
}

static void *worker_main(void *arg) {
    LucidEngine *e = arg;
    make_realtime();
    while (!atomic_load_explicit(&e->stop, memory_order_acquire)) {
        dispatch_semaphore_wait(e->wake, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC));
        run_model(e);
    }
    return NULL;
}

// Audio thread: only copies samples in and out of the rings. No allocation, no locks, no model calls.
OSStatus lucid_engine_ioproc(AudioObjectID device, const AudioTimeStamp *now, const AudioBufferList *input,
                       const AudioTimeStamp *inputTime, AudioBufferList *output, const AudioTimeStamp *outputTime,
                       void *clientData) {
    (void)device; (void)now; (void)inputTime; (void)outputTime;
    LucidEngine *e = clientData;
    const LucidRouting r = e->routing;

    for (UInt32 b = 0; b < output->mNumberBuffers; ++b) {
        if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    }
    if (!input || r.inputBuffer >= input->mNumberBuffers) {
        request_recovery(e);
        return noErr;
    }

    const AudioBuffer *in = &input->mBuffers[r.inputBuffer];
    const UInt32 inCh = in->mNumberChannels;
    const UInt32 frames = inCh ? in->mDataByteSize / (sizeof(float) * inCh) : 0;
    if (!frames || frames > kMaxLiveBlock || r.inputChannel >= inCh) {
        request_recovery(e);
        return noErr;
    }

    const int recovery = atomic_load_explicit(&e->recovery, memory_order_acquire);
    if (recovery == kResetReady) {
        // The worker stopped publishing output before Ready. Discard all old audio before resuming.
        ring_discard(&e->out);
        e->priming = kHandoff;
        atomic_store_explicit(&e->recovery, kRunning, memory_order_release);
    } else if (recovery != kRunning) {
        request_recovery(e);
        return noErr;
    }

    const float *src = in->mData;
    for (UInt32 i = 0; i < frames; ++i) e->scratchIn[i] = src ? src[i * inCh + r.inputChannel] : 0.0f;

    if (ring_push(&e->in, e->scratchIn, frames) != frames) {
        request_recovery(e);
        return noErr;
    }
    const uint32_t got = take_output(e, e->scratchOut, frames);
    if (got < frames) {
        memset(e->scratchOut + got, 0, (frames - got) * sizeof(float));
        atomic_fetch_add_explicit(&e->underruns, frames - got, memory_order_relaxed);
        request_recovery(e);
    }
    dispatch_semaphore_signal(e->wake);

    for (UInt32 m = 0; m < r.outputBufferCount; ++m) {
        const UInt32 b = r.outputFirstBuffer + m;
        if (b >= output->mNumberBuffers) break;
        AudioBuffer *dst = &output->mBuffers[b];
        const UInt32 ch = dst->mNumberChannels;
        if (!dst->mData || !ch) continue;
        UInt32 n = dst->mDataByteSize / (sizeof(float) * ch);
        if (n > frames) n = frames;
        float *o = dst->mData;
        for (UInt32 i = 0; i < n; ++i) {
            for (UInt32 c = 0; c < ch; ++c) o[i * ch + c] = e->scratchOut[i];
        }
    }
    return noErr;
}

bool lucid_engine_start_worker(LucidEngine *e) {
    if (e->workerRunning) return true;
    atomic_store_explicit(&e->stop, false, memory_order_release);
    if (pthread_create(&e->worker, NULL, worker_main, e) != 0) return false;
    e->workerRunning = true;
    return true;
}

OSStatus lucid_engine_start_live(LucidEngine *e, AudioObjectID device, AudioDeviceIOProcID *outProc) {
    if (!lucid_engine_start_worker(e)) return kAudioHardwareUnspecifiedError;
    const OSStatus status = AudioDeviceCreateIOProcID(device, lucid_engine_ioproc, e, outProc);
    if (status != noErr) lucid_engine_stop_worker(e);
    return status;
}

void lucid_engine_stop_worker(LucidEngine *e) {
    if (!e->workerRunning) return;
    atomic_store_explicit(&e->stop, true, memory_order_release);
    dispatch_semaphore_signal(e->wake);
    pthread_join(e->worker, NULL);
    e->workerRunning = false;
}
