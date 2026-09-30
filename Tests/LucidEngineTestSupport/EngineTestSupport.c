// Compile the real engine under private test names; no test hooks enter the shipped API.
#include "LucidEngineTestSupport.h"
void test_engine_stop_worker(LucidEngine *engine);
#define lucid_engine_latency_frames test_engine_latency_frames
#define lucid_engine_set_bypass test_engine_set_bypass
#define lucid_engine_underruns test_engine_underruns
#define lucid_engine_create test_engine_create
#define lucid_engine_destroy test_engine_destroy
#define lucid_engine_process test_engine_process
#define lucid_engine_ioproc test_engine_ioproc
#define lucid_engine_start_worker test_engine_start_worker
#define lucid_engine_start_live test_engine_start_live
#define lucid_engine_stop_worker test_engine_stop_worker
#include "../../Sources/LucidEngine/LucidEngine.c"

void lucid_test_worker_cycle(LucidEngine *engine) { run_model(engine); }

void lucid_test_fill_input(LucidEngine *engine) {
    const float silence[kRingSize] = {0};
    ring_push(&engine->in, silence, kRingSize);
}

void lucid_test_fill_output(LucidEngine *engine) {
    const float silence[kRingSize] = {0};
    ring_push(&engine->out, silence, kRingSize);
}
