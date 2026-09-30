#pragma once
#include "LucidEngine.h"

// Drive the production worker synchronously so scheduling failures are reproducible.
void lucid_test_worker_cycle(LucidEngine *engine);
// Force queue capacity faults without depending on thread timing or audio hardware.
void lucid_test_fill_input(LucidEngine *engine);
void lucid_test_fill_output(LucidEngine *engine);
