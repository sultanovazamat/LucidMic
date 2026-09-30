# LucidMic Phase 1 (Installable Skeleton) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** An installable `LucidMic.pkg` that adds a **LucidMic Microphone** device and a
menu-bar app that passes the physical mic through to it, with latency, level, and load meters.
There is no denoising yet. The model engines arrive in phase 2.

**Architecture:** A libASPL-based AudioServerPlugIn publishes two devices, a hidden output
**LucidMic Feed** and a visible input **LucidMic Microphone**, which share one
timestamp-indexed ring and one clock. The app builds a private aggregate device (physical mic
as clock master, plus the feed and an optional monitor, drift-compensated) and runs a
realtime-safe C IOProc that copies the mic into the feed. A `.pkg` installs the app and the
driver, then restarts `coreaudiod`.

**Tech Stack:** C++17 + libASPL v3.1.2 (driver), CMake/CTest, C11 (realtime code),
Swift 6 / SwiftPM / Swift Testing / SwiftUI `MenuBarExtra` (app), `pkgbuild`, ad-hoc codesign.

**Status of the code below:** every file in this plan was compiled and tested in a scratch
prototype on this machine on 2026-09-30 (macOS 26.5.2, Xcode 26.4.1, Swift 6.3.1).
`make pkg` and `make check` pass: 2/2 CTest suites and 18 Swift tests, with swift-format lint
clean. The hardware steps (install, loopback, latency, second Mac) have NOT been run yet. They
are the verification steps in Tasks 5, 11, 14 and 15.

**Known toolchain gotcha:** Swift 6.3.1 crashes (`SendNonSendable` region analysis) when Swift
code passes a C IOProc function pointer to `AudioDeviceCreateIOProcID`, or builds a
`[String: Any]` aggregate description inside a `@MainActor` method. For that reason IOProc
registration lives in C (`lucid_*_create_ioproc`) and aggregate creation lives in the
nonisolated `AggregateDevice` enum. Don't "simplify" either back into Swift.

**Rules for every task:** run commands from the repo root `/Users/azamatsultanov/Desktop/Exp`.
Never touch `.env`. Tasks that need `sudo` are marked **(USER RUNS)**. The agent can't type
passwords, so it asks the user to run those commands and paste the output.

---

### Task 1: Repository scaffolding

**Files:**
- Create: `VERSION`, `.swift-format`, `Makefile`, `README.md`
- Modify: `.gitignore`
- Create: `third_party/libASPL` (git submodule pinned to tag `v3.1.2`)

**Step 1: Add libASPL as a pinned submodule**

```bash
git submodule add https://github.com/gavv/libASPL.git third_party/libASPL
git -C third_party/libASPL fetch --tags
git -C third_party/libASPL checkout v3.1.2
```

Expected: `git -C third_party/libASPL describe --tags` prints `v3.1.2`. libASPL's CMake needs
the tag to detect its version.

**Step 2: Create the version and format files**

`VERSION`:

```
0.1.0
```

`.swift-format`:

```json
{
  "version": 1,
  "indentation": { "spaces": 4 },
  "lineLength": 120,
  "maximumBlankLines": 1,
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeEachArgument": false,
  "rules": {
    "AlwaysUseLowerCamelCase": false,
    "NeverForceUnwrap": false,
    "NeverUseForceTry": false,
    "UseLetInEveryBoundCaseVariable": false,
    "ValidateDocumentationComments": false
  }
}
```

**Step 3: Create the Makefile**

`Makefile`:

```make
# LucidMic build entry points. `make help` lists targets.
VERSION := $(shell cat VERSION)
BUILD   := build
DIST    := dist
PKG     := $(DIST)/LucidMic-$(VERSION).pkg
SWIFT_SOURCES := app/Sources app/Tests app/Package.swift
SHELL_SCRIPTS := scripts/bundle-app.sh Installer/build-pkg.sh Installer/uninstall.sh Installer/scripts/postinstall

.PHONY: help driver app pkg test test-driver test-app test-integration format lint check install-dev uninstall-dev latency clean

help:
	@echo "driver | app | pkg | test | test-integration | format | lint | check | install-dev | uninstall-dev | latency | clean"

driver:
	cmake -S Driver -B $(BUILD)/driver -DCMAKE_BUILD_TYPE=Release -DDRIVER_VERSION=$(VERSION)
	cmake --build $(BUILD)/driver -j

app:
	scripts/bundle-app.sh $(VERSION) $(BUILD)

pkg: driver app
	Installer/build-pkg.sh $(VERSION) $(BUILD)/LucidMic.app $(BUILD)/driver/LucidMic.driver $(PKG)

test-driver: driver
	ctest --test-dir $(BUILD)/driver --output-on-failure

test-app:
	swift test --package-path app

test: test-driver test-app

# Needs the driver installed (make install-dev).
test-integration:
	LUCIDMIC_INTEGRATION=1 swift test --package-path app --filter DriverLoopbackTests

format:
	xcrun swift-format format -i -r $(SWIFT_SOURCES)

lint:
	xcrun swift-format lint --strict -r $(SWIFT_SOURCES)
	@for f in $(SHELL_SCRIPTS); do [ -f "$$f" ] || continue; sh -n "$$f" || exit 1; done

check: lint test

install-dev: pkg
	sudo installer -pkg $(PKG) -target /

uninstall-dev:
	sudo Installer/uninstall.sh

latency:
	swift run --package-path app -c release lucidmic-latency

clean:
	rm -rf $(BUILD) $(DIST) app/.build
```

Note: recipe lines must start with a TAB.

**Step 4: Create README.md**

`README.md`:

````markdown
# LucidMic

Makes your voice clearer in any app. LucidMic runs speech enhancement on your microphone and
publishes the result as **LucidMic Microphone**, which you pick in Zoom, Meet, Teams, Slack,
Voice Memos, and other apps.

## Install (coworkers)

1. Download `LucidMic-<version>.pkg` from GitHub Releases.
2. Double-click it. macOS blocks it because it is not notarized. Open **System Settings ›
   Privacy & Security**, scroll down, and click **Open Anyway** next to the LucidMic message.
3. Follow the installer (one admin password prompt).
4. Launch **LucidMic** from Applications. A waveform icon appears in the menu bar. Turn it on
   and allow microphone access.
5. In your call app, choose **LucidMic Microphone** as the microphone.

To uninstall, use **Uninstall…** in the LucidMic menu, or run
`sudo /Applications/LucidMic.app/Contents/Resources/uninstall.sh`.

## Develop

Requirements: Apple silicon, macOS 14+, Xcode 26+, CMake.

```bash
git submodule update --init --recursive
make check          # lint + driver tests + app tests
make pkg            # dist/LucidMic-<version>.pkg
make install-dev    # installs the pkg locally (sudo)
make test-integration   # feed → microphone loopback, needs the driver installed
make latency        # measures the latency LucidMic adds on this Mac
```

Design: `docs/plans/2026-09-30-lucidmic-design.md`.
````

**Step 5: Extend .gitignore**

Make sure `.gitignore` contains:

```
build/
DerivedData/
.build/
.swiftpm/
dist/
*.pkg
bench/data/
bench/results/
.env
```

**Step 6: Verify and commit**

Run: `make help`
Expected: the target list is printed.

```bash
git add .gitmodules third_party/libASPL VERSION .swift-format Makefile README.md .gitignore
git commit -m "chore: scaffold LucidMic repo

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 2: LoopbackRing (driver ring buffer), TDD

**Files:**
- Create: `Driver/tests/check.hpp`, `Driver/tests/test_loopback_ring.cpp`, `Driver/CMakeLists.txt` (tests only for now)
- Create: `Driver/src/LoopbackRing.hpp`

**Why:** a timestamp-indexed ring (not a FIFO). Every client of LucidMic Microphone asks for
sample time T and gets exactly what the feed wrote for T, so any number of apps can read the
mic at once. Samples that were never written, were overwritten, or fall in a pause read as
silence.

**Step 1: Write the failing tests**

`Driver/tests/check.hpp`:

```cpp
// Minimal assertion helper for dependency-free C++ tests.
#pragma once
#include <cstdio>
#include <cstdlib>

#define CHECK(cond)                                                                     \
    do {                                                                                \
        if (!(cond)) {                                                                  \
            std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
            std::exit(1);                                                               \
        }                                                                               \
    } while (0)
```

`Driver/tests/test_loopback_ring.cpp`:

```cpp
#include "LoopbackRing.hpp"
#include "check.hpp"

#include <vector>

using lucid::LoopbackRing;

static std::vector<float> Ramp(float start, uint32_t n)
{
    std::vector<float> v(n);
    for (uint32_t i = 0; i < n; ++i) v[i] = start + static_cast<float>(i);
    return v;
}

static void ReadsSilenceBeforeAnyWrite()
{
    LoopbackRing ring(16);
    std::vector<float> out(8, 99.0f);
    ring.Read(0, out.data(), 8);
    for (float s : out) CHECK(s == 0.0f);
}

static void ReadsBackWhatWasWrittenAtSameTimestamp()
{
    LoopbackRing ring(16);
    auto in = Ramp(1.0f, 8);
    ring.Write(100, in.data(), 8);
    std::vector<float> out(8);
    ring.Read(100, out.data(), 8);
    for (int i = 0; i < 8; ++i) CHECK(out[i] == in[i]);
}

static void FutureSamplesReadAsSilence()
{
    LoopbackRing ring(16);
    auto in = Ramp(1.0f, 4);
    ring.Write(100, in.data(), 4);
    std::vector<float> out(8, 99.0f);
    ring.Read(102, out.data(), 8);  // 102,103 valid; 104.. not written yet
    CHECK(out[0] == 3.0f && out[1] == 4.0f);
    for (int i = 2; i < 8; ++i) CHECK(out[i] == 0.0f);
}

static void OverwrittenSamplesReadAsSilence()
{
    LoopbackRing ring(8);
    auto a = Ramp(1.0f, 8);
    auto b = Ramp(10.0f, 8);
    ring.Write(0, a.data(), 8);
    ring.Write(8, b.data(), 8);  // capacity 8: timestamps 0..7 are gone
    std::vector<float> out(8, 99.0f);
    ring.Read(0, out.data(), 8);
    for (float s : out) CHECK(s == 0.0f);
    ring.Read(8, out.data(), 8);
    for (int i = 0; i < 8; ++i) CHECK(out[i] == b[i]);
}

static void GapInvalidatesStaleData()
{
    LoopbackRing ring(16);
    auto a = Ramp(1.0f, 4);
    ring.Write(0, a.data(), 4);
    auto b = Ramp(50.0f, 4);
    ring.Write(8, b.data(), 4);  // writer paused for 4 samples
    std::vector<float> out(12, 99.0f);
    ring.Read(0, out.data(), 12);
    for (int i = 0; i < 8; ++i) CHECK(out[i] == 0.0f);  // old run + gap are silence
    for (int i = 0; i < 4; ++i) CHECK(out[8 + i] == b[i]);
}

static void ManyReadersSeeIdenticalData()
{
    LoopbackRing ring(16);
    auto in = Ramp(1.0f, 8);
    ring.Write(40, in.data(), 8);
    std::vector<float> r1(8), r2(8);
    ring.Read(40, r1.data(), 8);
    ring.Read(40, r2.data(), 8);
    CHECK(r1 == r2);
}

int main()
{
    ReadsSilenceBeforeAnyWrite();
    ReadsBackWhatWasWrittenAtSameTimestamp();
    FutureSamplesReadAsSilence();
    OverwrittenSamplesReadAsSilence();
    GapInvalidatesStaleData();
    ManyReadersSeeIdenticalData();
    return 0;
}
```

`Driver/CMakeLists.txt` (temporary, tests only; replaced in Task 4):

```cmake
cmake_minimum_required(VERSION 3.20)
project(LucidMicDriver CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

enable_testing()
foreach(t test_loopback_ring)
  add_executable(${t} tests/${t}.cpp)
  target_include_directories(${t} PRIVATE src)
  add_test(NAME ${t} COMMAND ${t})
endforeach()
```

**Step 2: Run the tests to verify they fail**

Run: `cmake -S Driver -B build/driver && cmake --build build/driver`
Expected: compile error `'LoopbackRing.hpp' file not found`.

**Step 3: Implement**

`Driver/src/LoopbackRing.hpp`:

```cpp
// LoopbackRing: timestamp-indexed mono ring shared by the hidden feed device
// (single writer) and the visible microphone device (any number of readers).
//
// Timestamps are absolute sample times on the shared clock, so every reader
// that asks for sample time T gets exactly the sample the writer wrote for T.
// Samples outside the valid window [runStart, writeEnd) read as silence.
#pragma once

#include <atomic>
#include <cstdint>
#include <cstring>
#include <vector>

namespace lucid {

class LoopbackRing {
public:
    // capacityFrames must be a power of two.
    explicit LoopbackRing(uint32_t capacityFrames)
        : buffer_(capacityFrames, 0.0f)
        , mask_(capacityFrames - 1)
    {
    }

    uint32_t Capacity() const { return static_cast<uint32_t>(buffer_.size()); }

    // Realtime-safe. Called only from the feed device's IO thread.
    void Write(int64_t timestamp, const float* frames, uint32_t count)
    {
        const int64_t end = writeEnd_.load(std::memory_order_relaxed);
        if (timestamp > end) {
            // First write, or a gap (the app paused): start a new valid run.
            runStart_.store(timestamp, std::memory_order_release);
        }
        for (uint32_t i = 0; i < count; ++i) {
            buffer_[static_cast<uint64_t>(timestamp + i) & mask_] = frames[i];
        }
        if (timestamp + count > end) {
            writeEnd_.store(timestamp + count, std::memory_order_release);
        }
    }

    // Realtime-safe. Called from the microphone device's IO thread(s).
    void Read(int64_t timestamp, float* out, uint32_t count) const
    {
        const int64_t end = writeEnd_.load(std::memory_order_acquire);
        if (end == kNever) {
            std::memset(out, 0, count * sizeof(float));
            return;
        }
        const int64_t runStart = runStart_.load(std::memory_order_acquire);
        const int64_t oldest = end - static_cast<int64_t>(buffer_.size());
        const int64_t validStart = runStart > oldest ? runStart : oldest;

        for (uint32_t i = 0; i < count; ++i) {
            const int64_t t = timestamp + i;
            out[i] = (t >= validStart && t < end) ? buffer_[static_cast<uint64_t>(t) & mask_]
                                                  : 0.0f;
        }
    }

private:
    static constexpr int64_t kNever = INT64_MIN;

    std::vector<float> buffer_;
    const uint64_t mask_;
    std::atomic<int64_t> runStart_{kNever};
    std::atomic<int64_t> writeEnd_{kNever};
};

} // namespace lucid
```

**Step 4: Run the tests to verify they pass**

Run: `cmake --build build/driver && ctest --test-dir build/driver --output-on-failure`
Expected: `100% tests passed, 0 tests failed out of 1`.

**Step 5: Commit**

```bash
git add Driver/
git commit -m "feat(driver): timestamp-indexed loopback ring

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 3: SharedClock, TDD

**Files:**
- Create: `Driver/tests/test_shared_clock.cpp`, `Driver/src/SharedClock.hpp`
- Modify: `Driver/CMakeLists.txt` (change `foreach(t test_loopback_ring)` to `foreach(t test_loopback_ring test_shared_clock)`)

**Why:** by default libASPL anchors each device's clock when its first client starts, so two
devices would have unrelated sample timelines. One shared, stateless anchor means feed time T
equals microphone time T.

**Step 1: Write the failing test**

`Driver/tests/test_shared_clock.cpp`:

```cpp
#include "SharedClock.hpp"
#include "check.hpp"

using lucid::SharedClock;

// 48 kHz, 24 MHz host clock (Apple silicon) => 500 ticks per frame.
static constexpr double kRate = 48000.0;
static constexpr double kTicksPerSecond = 24000000.0;

static void StartsAtZeroAtAnchor()
{
    SharedClock clock(kRate, 1024, 1000, kTicksPerSecond);
    double sampleTime = -1;
    uint64_t hostTime = 0;
    clock.ZeroTimeStamp(1000, &sampleTime, &hostTime);
    CHECK(sampleTime == 0.0);
    CHECK(hostTime == 1000);
}

static void AdvancesByWholePeriods()
{
    SharedClock clock(kRate, 1024, 0, kTicksPerSecond);
    const uint64_t ticksPerPeriod = 1024 * 500;
    double sampleTime = 0;
    uint64_t hostTime = 0;
    clock.ZeroTimeStamp(ticksPerPeriod - 1, &sampleTime, &hostTime);
    CHECK(sampleTime == 0.0);
    clock.ZeroTimeStamp(ticksPerPeriod * 3 + 7, &sampleTime, &hostTime);
    CHECK(sampleTime == 3072.0);
    CHECK(hostTime == ticksPerPeriod * 3);
}

static void TwoDevicesSharingAClockAgree()
{
    SharedClock clock(kRate, 16384, 12345, kTicksPerSecond);
    double a = 0, b = 0;
    uint64_t ha = 0, hb = 0;
    clock.ZeroTimeStamp(987654321, &a, &ha);
    clock.ZeroTimeStamp(987654321, &b, &hb);
    CHECK(a == b && ha == hb);
}

static void NowBeforeAnchorClampsToZero()
{
    SharedClock clock(kRate, 1024, 5000, kTicksPerSecond);
    double sampleTime = -1;
    uint64_t hostTime = 0;
    clock.ZeroTimeStamp(10, &sampleTime, &hostTime);
    CHECK(sampleTime == 0.0);
    CHECK(hostTime == 5000);
}

int main()
{
    StartsAtZeroAtAnchor();
    AdvancesByWholePeriods();
    TwoDevicesSharingAClockAgree();
    NowBeforeAnchorClampsToZero();
    return 0;
}
```

Update the `foreach` line in `Driver/CMakeLists.txt` as described above.

**Step 2: Run the tests to verify they fail**

Run: `cmake -S Driver -B build/driver && cmake --build build/driver`
Expected: `'SharedClock.hpp' file not found`.

**Step 3: Implement**

`Driver/src/SharedClock.hpp`:

```cpp
// SharedClock: one zero-timestamp timeline for every LucidMic device.
//
// Both devices report zero timestamps from the same anchor, rate and period,
// so a sample written to the feed at sample time T is read back from the
// microphone at the same sample time T: no drift, no offset.
#pragma once

#include <cstdint>

namespace lucid {

class SharedClock {
public:
    SharedClock(double sampleRate, uint32_t periodFrames, uint64_t anchorHostTime,
        double hostTicksPerSecond)
        : periodFrames_(periodFrames)
        , anchorHostTime_(anchorHostTime)
        , hostTicksPerPeriod_(hostTicksPerSecond / sampleRate * periodFrames)
    {
    }

    uint32_t PeriodFrames() const { return periodFrames_; }

    // Stateless: the latest period boundary at or before nowHostTime.
    void ZeroTimeStamp(uint64_t nowHostTime, double* outSampleTime, uint64_t* outHostTime) const
    {
        const uint64_t elapsed = nowHostTime > anchorHostTime_ ? nowHostTime - anchorHostTime_ : 0;
        const uint64_t periods = static_cast<uint64_t>(static_cast<double>(elapsed) / hostTicksPerPeriod_);
        *outSampleTime = static_cast<double>(periods) * periodFrames_;
        *outHostTime = anchorHostTime_ + static_cast<uint64_t>(static_cast<double>(periods) * hostTicksPerPeriod_);
    }

private:
    const uint32_t periodFrames_;
    const uint64_t anchorHostTime_;
    const double hostTicksPerPeriod_;
};

} // namespace lucid
```

**Step 4: Run the tests to verify they pass**

Run: `cmake --build build/driver && ctest --test-dir build/driver --output-on-failure`
Expected: `100% tests passed, 0 tests failed out of 2`.

**Step 5: Commit**

```bash
git add Driver/
git commit -m "feat(driver): shared zero-timestamp clock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 4: The LucidMic.driver bundle

**Files:**
- Create: `Driver/src/Driver.cpp`, `Driver/Info.plist.in`
- Modify: `Driver/CMakeLists.txt` (full version below)

**Step 1: Write the plug-in**

`Driver/src/Driver.cpp`:

```cpp
// LucidMic audio server plug-in.
//
// Publishes two devices that share one LoopbackRing and one SharedClock:
//   "LucidMic Feed"       hidden, output only: LucidMic.app writes enhanced audio here.
//   "LucidMic Microphone" visible, input only: call apps read it like any mic.
#include "LoopbackRing.hpp"
#include "SharedClock.hpp"

#include <aspl/Driver.hpp>

#include <CoreAudio/AudioServerPlugIn.h>
#include <mach/mach_time.h>

#include <cmath>
#include <memory>

namespace {

constexpr UInt32 kSampleRate = 48000;
constexpr UInt32 kChannels = 1;
constexpr UInt32 kRingFrames = 32768;   // ~680 ms at 48 kHz, power of two
constexpr UInt32 kPeriodFrames = 16384; // zero-timestamp period

constexpr const char* kMicUID = "com.sultanovazamat.lucidmic.microphone";
constexpr const char* kFeedUID = "com.sultanovazamat.lucidmic.feed";
constexpr const char* kModelUID = "com.sultanovazamat.lucidmic.model";

double HostTicksPerSecond()
{
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    return 1e9 * static_cast<double>(tb.denom) / static_cast<double>(tb.numer);
}

AudioStreamBasicDescription MonoFloatFormat()
{
    AudioStreamBasicDescription f = {};
    f.mSampleRate = kSampleRate;
    f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    f.mBitsPerChannel = 32;
    f.mChannelsPerFrame = kChannels;
    f.mBytesPerFrame = 4 * kChannels;
    f.mFramesPerPacket = 1;
    f.mBytesPerPacket = 4 * kChannels;
    return f;
}

// Device whose zero timestamps come from the shared clock.
class LucidDevice : public aspl::Device {
public:
    LucidDevice(std::shared_ptr<const aspl::Context> context, const aspl::DeviceParameters& params,
        std::shared_ptr<const lucid::SharedClock> clock)
        : aspl::Device(std::move(context), params)
        , clock_(std::move(clock))
    {
    }

protected:
    OSStatus GetZeroTimeStampImpl(UInt32 /*clientID*/, Float64* outSampleTime, UInt64* outHostTime,
        UInt64* outSeed) override
    {
        clock_->ZeroTimeStamp(mach_absolute_time(), outSampleTime, outHostTime);
        *outSeed = 1;
        return kAudioHardwareNoError;
    }

private:
    std::shared_ptr<const lucid::SharedClock> clock_;
};

class FeedHandler : public aspl::IORequestHandler {
public:
    explicit FeedHandler(std::shared_ptr<lucid::LoopbackRing> ring)
        : ring_(std::move(ring))
    {
    }

    void OnWriteMixedOutput(const std::shared_ptr<aspl::Stream>& /*stream*/, Float64 /*zeroTimestamp*/,
        Float64 timestamp, const void* bytes, UInt32 bytesCount) override
    {
        ring_->Write(std::llround(timestamp), static_cast<const float*>(bytes),
            bytesCount / sizeof(float));
    }

private:
    std::shared_ptr<lucid::LoopbackRing> ring_;
};

class MicHandler : public aspl::IORequestHandler {
public:
    explicit MicHandler(std::shared_ptr<lucid::LoopbackRing> ring)
        : ring_(std::move(ring))
    {
    }

    void OnReadClientInput(const std::shared_ptr<aspl::Client>& /*client*/,
        const std::shared_ptr<aspl::Stream>& /*stream*/, Float64 /*zeroTimestamp*/, Float64 timestamp,
        void* bytes, UInt32 bytesCount) override
    {
        ring_->Read(std::llround(timestamp), static_cast<float*>(bytes), bytesCount / sizeof(float));
    }

private:
    std::shared_ptr<lucid::LoopbackRing> ring_;
};

std::shared_ptr<LucidDevice> MakeDevice(const std::shared_ptr<aspl::Context>& context,
    const std::shared_ptr<const lucid::SharedClock>& clock, const char* name, const char* uid,
    aspl::Direction direction, bool canBeDefault)
{
    aspl::DeviceParameters params;
    params.Name = name;
    params.Manufacturer = "LucidMic";
    params.DeviceUID = uid;
    params.ModelUID = kModelUID;
    params.SampleRate = kSampleRate;
    params.ChannelCount = kChannels;
    params.ZeroTimeStampPeriod = clock->PeriodFrames();
    params.CanBeDefault = canBeDefault;
    params.CanBeDefaultForSystemSounds = false;

    auto device = std::make_shared<LucidDevice>(context, params, clock);

    aspl::StreamParameters streamParams;
    streamParams.Direction = direction;
    streamParams.Format = MonoFloatFormat();
    device->AddStreamAsync(streamParams);
    return device;
}

std::shared_ptr<aspl::Driver> CreateDriver()
{
    auto context = std::make_shared<aspl::Context>();
    auto ring = std::make_shared<lucid::LoopbackRing>(kRingFrames);
    auto clock = std::make_shared<const lucid::SharedClock>(
        kSampleRate, kPeriodFrames, mach_absolute_time(), HostTicksPerSecond());

    auto feed = MakeDevice(context, clock, "LucidMic Feed", kFeedUID, aspl::Direction::Output, false);
    feed->SetIsHidden(true);
    feed->SetIOHandler(std::make_shared<FeedHandler>(ring));

    auto mic = MakeDevice(
        context, clock, "LucidMic Microphone", kMicUID, aspl::Direction::Input, true);
    mic->SetIOHandler(std::make_shared<MicHandler>(ring));

    auto plugin = std::make_shared<aspl::Plugin>(context);
    plugin->AddDevice(mic);
    plugin->AddDevice(feed);

    return std::make_shared<aspl::Driver>(context, plugin);
}

} // namespace

extern "C" void* LucidMicEntryPoint(CFAllocatorRef /*allocator*/, CFUUIDRef typeUUID)
{
    if (!CFEqual(typeUUID, kAudioServerPlugInTypeUUID)) {
        return nullptr;
    }
    static std::shared_ptr<aspl::Driver> driver = CreateDriver();
    return driver->GetReference();
}
```

`Driver/Info.plist.in`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
	<key>AudioServerPlugIn_MachServices</key>
	<array>
	</array>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${MACOSX_BUNDLE_EXECUTABLE_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${MACOSX_BUNDLE_GUI_IDENTIFIER}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${MACOSX_BUNDLE_BUNDLE_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>BNDL</string>
	<key>CFBundleShortVersionString</key>
	<string>${MACOSX_BUNDLE_SHORT_VERSION_STRING}</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>CFBundleVersion</key>
	<string>${MACOSX_BUNDLE_SHORT_VERSION_STRING}</string>
	<key>CFPlugInFactories</key>
	<dict>
		<key>3AF6892F-B644-46A8-BAEF-44438E9D445A</key>
		<string>LucidMicEntryPoint</string>
	</dict>
	<key>CFPlugInTypes</key>
	<dict>
		<key>443ABAB8-E7B3-491A-B985-BEB9187030DB</key>
		<array>
			<string>3AF6892F-B644-46A8-BAEF-44438E9D445A</string>
		</array>
	</dict>
	<key>NSHumanReadableCopyright</key>
	<string>LucidMic</string>
	<key>NSPrincipalClass</key>
	<string></string>
	<key>sandboxSafe</key>
	<true/>
  </dict>
</plist>
```

`Driver/CMakeLists.txt`:

```cmake
cmake_minimum_required(VERSION 3.20)
project(LucidMicDriver CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0)

set(DRIVER_NAME "LucidMic")
set(DRIVER_VERSION "0.1.0" CACHE STRING "Driver version")
set(DRIVER_IDENTIFIER "com.sultanovazamat.lucidmic.driver")
set(DRIVER_UID "3AF6892F-B644-46A8-BAEF-44438E9D445A")
set(DRIVER_ENTRYPOINT "LucidMicEntryPoint")
set(LIBASPL_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../third_party/libASPL" CACHE PATH "libASPL source")

include(ExternalProject)
ExternalProject_Add(libASPL_ext
  SOURCE_DIR ${LIBASPL_SOURCE_DIR}
  BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/libASPL-build
  INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/libASPL-prefix
  CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR> -DCMAKE_BUILD_TYPE=Release
             -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
  BUILD_BYPRODUCTS ${CMAKE_CURRENT_BINARY_DIR}/libASPL-prefix/lib/libASPL.a
)

add_library(${DRIVER_NAME} MODULE src/Driver.cpp)
add_dependencies(${DRIVER_NAME} libASPL_ext)
target_include_directories(${DRIVER_NAME} PRIVATE
  ${CMAKE_CURRENT_BINARY_DIR}/libASPL-prefix/include src)
target_link_libraries(${DRIVER_NAME} PRIVATE
  ${CMAKE_CURRENT_BINARY_DIR}/libASPL-prefix/lib/libASPL.a
  "-framework CoreFoundation" "-framework CoreAudio")
set_target_properties(${DRIVER_NAME} PROPERTIES
  OUTPUT_NAME "${DRIVER_NAME}" BUNDLE TRUE BUNDLE_EXTENSION "driver" PREFIX "" SUFFIX ""
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
  MACOSX_BUNDLE_BUNDLE_NAME "${DRIVER_NAME}"
  MACOSX_BUNDLE_BUNDLE_VERSION "${DRIVER_VERSION}"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "${DRIVER_VERSION}"
  MACOSX_BUNDLE_GUI_IDENTIFIER "${DRIVER_IDENTIFIER}"
  MACOSX_BUNDLE_COPYRIGHT "LucidMic")
add_custom_command(TARGET ${DRIVER_NAME} POST_BUILD
  COMMAND codesign --force --sign - "$<TARGET_BUNDLE_DIR:${DRIVER_NAME}>"
  COMMENT "Ad-hoc signing LucidMic.driver" VERBATIM)

enable_testing()
foreach(t test_loopback_ring test_shared_clock)
  add_executable(${t} tests/${t}.cpp)
  target_include_directories(${t} PRIVATE src)
  add_test(NAME ${t} COMMAND ${t})
endforeach()
```

The factory UUID `3AF6892F-B644-46A8-BAEF-44438E9D445A` identifies the plug-in. Don't change
it after the first release.

**Step 2: Build and verify**

Run: `make test-driver`
Expected: `100% tests passed, 0 tests failed out of 2`.

Run: `codesign -dv build/driver/LucidMic.driver 2>&1 | grep -E "Identifier|Signature"`
Expected: `Identifier=com.sultanovazamat.lucidmic.driver` and `Signature=adhoc`.

Run: `nm -gU build/driver/LucidMic.driver/Contents/MacOS/LucidMic | grep EntryPoint`
Expected: `T _LucidMicEntryPoint`.

**Step 3: Commit**

```bash
git add Driver/
git commit -m "feat(driver): LucidMic Feed + LucidMic Microphone plug-in

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 5: Install the driver and confirm the devices appear (USER RUNS)

**Step 1: Install (user runs in Terminal)**

```bash
sudo cp -R build/driver/LucidMic.driver /Library/Audio/Plug-Ins/HAL/
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/LucidMic.driver
sudo killall -9 coreaudiod
```

**Step 2: Verify**

Run: `system_profiler SPAudioDataType | grep -A6 "LucidMic Microphone"`
Expected: a `LucidMic Microphone` entry with `Input Channels: 1` at 48000 Hz.
`LucidMic Feed` is hidden and should NOT appear in Sound settings or in Zoom's speaker list.

If the microphone does not appear, check the driver log:
`log show --last 2m --predicate 'process == "coreaudiod"' | grep -i -E "lucid|aspl|plug"`

**Step 3: Record the result.** Note it in the PR/commit message of Task 11. Nothing to commit here.

### Task 6: Swift package + realtime pass-through IOProc (C), TDD

**Files:**
- Create: `app/Package.swift` (initial), `app/Sources/LucidAudioC/include/LucidAudioC.h` (initial),
  `app/Sources/LucidAudioC/include/LucidPassthrough.h`, `app/Sources/LucidAudioC/LucidPassthrough.c`
- Test: `app/Tests/LucidAudioTests/TestBuffers.swift`, `app/Tests/LucidAudioTests/PassthroughIOProcTests.swift`

**Why C:** the IOProc runs on Core Audio's realtime thread. It must not allocate memory, take
locks, or touch the Swift/ObjC runtime. Meters are C11 atomics read through accessor functions,
because Swift can't import `_Atomic` fields.

**Step 1: Write the failing tests**

`app/Package.swift` (initial):

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LucidMic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LucidAudioC", linkerSettings: [.linkedFramework("CoreAudio")]),
        .testTarget(name: "LucidAudioTests", dependencies: ["LucidAudioC"]),
    ]
)
```

`app/Tests/LucidAudioTests/TestBuffers.swift`:

```swift
import CoreAudio

/// Owns a heap AudioBufferList with interleaved float streams, for driving IOProcs in tests.
final class TestBufferList {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []

    init(streams: [(channels: Int, frames: Int)]) {
        list = AudioBufferList.allocate(maximumBuffers: streams.count)
        for (i, stream) in streams.enumerated() {
            let count = stream.channels * stream.frames
            let data = UnsafeMutablePointer<Float>.allocate(capacity: count)
            data.initialize(repeating: 0, count: count)
            storage.append(data)
            list[i] = AudioBuffer(
                mNumberChannels: UInt32(stream.channels),
                mDataByteSize: UInt32(count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(data))
        }
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }

    func samples(_ buffer: Int) -> [Float] {
        let b = list[buffer]
        let n = Int(b.mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(start: storage[buffer], count: n))
    }

    func fill(_ buffer: Int, with values: [Float]) {
        for (i, v) in values.enumerated() { storage[buffer][i] = v }
    }
}
```

`app/Tests/LucidAudioTests/PassthroughIOProcTests.swift`:

```swift
import CoreAudio
import LucidAudioC
import Testing

@Suite struct PassthroughIOProcTests {
    private func run(
        routing: LucidRouting, input: TestBufferList, output: TestBufferList, monitor: Bool = false
    ) -> OpaquePointer {
        let state = lucid_passthrough_create(routing)!
        lucid_passthrough_set_monitor(state, monitor)
        var ts = AudioTimeStamp()
        _ = lucid_passthrough_ioproc(
            0, &ts, input.list.unsafePointer, &ts, output.list.unsafeMutablePointer, &ts, UnsafeMutableRawPointer(state)
        )
        return state
    }

    private func routing(feed: UInt32 = 0, monitorFirst: Int32 = -1, monitorCount: UInt32 = 0) -> LucidRouting {
        LucidRouting(
            inputBuffer: 0, inputChannel: 0, feedBuffer: feed, monitorFirstBuffer: monitorFirst,
            monitorBufferCount: monitorCount, sampleRate: 48_000)
    }

    @Test func copiesMicChannelZeroToFeed() {
        let input = TestBufferList(streams: [(channels: 2, frames: 4)])
        input.fill(0, with: [0.1, 9, 0.2, 9, 0.3, 9, 0.4, 9])  // L R L R… take L
        let output = TestBufferList(streams: [(channels: 1, frames: 4)])
        let state = run(routing: routing(), input: input, output: output)
        defer { lucid_passthrough_destroy(state) }
        #expect(output.samples(0) == [0.1, 0.2, 0.3, 0.4])
    }

    @Test func monitorIsSilentWhenDisabled() {
        let input = TestBufferList(streams: [(channels: 1, frames: 2)])
        input.fill(0, with: [0.5, -0.5])
        let output = TestBufferList(streams: [(channels: 1, frames: 2), (channels: 2, frames: 2)])
        output.fill(1, with: [7, 7, 7, 7])  // garbage must be cleared
        let state = run(routing: routing(monitorFirst: 1, monitorCount: 1), input: input, output: output)
        defer { lucid_passthrough_destroy(state) }
        #expect(output.samples(1) == [0, 0, 0, 0])
    }

    @Test func monitorGetsMicOnAllChannelsWhenEnabled() {
        let input = TestBufferList(streams: [(channels: 1, frames: 2)])
        input.fill(0, with: [0.5, -0.25])
        let output = TestBufferList(streams: [(channels: 1, frames: 2), (channels: 2, frames: 2)])
        let state = run(routing: routing(monitorFirst: 1, monitorCount: 1), input: input, output: output, monitor: true)
        defer { lucid_passthrough_destroy(state) }
        #expect(output.samples(1) == [0.5, 0.5, -0.25, -0.25])
    }

    @Test func tracksPeakAndResetsOnRead() {
        let input = TestBufferList(streams: [(channels: 1, frames: 3)])
        input.fill(0, with: [0.1, -0.8, 0.3])
        let output = TestBufferList(streams: [(channels: 1, frames: 3)])
        let state = run(routing: routing(), input: input, output: output)
        defer { lucid_passthrough_destroy(state) }
        #expect(lucid_passthrough_take_input_peak(state) == 0.8)
        #expect(lucid_passthrough_take_input_peak(state) == 0)
        #expect(lucid_passthrough_callback_count(state) == 1)
    }

    @Test func ignoresOutOfRangeRouting() {
        let input = TestBufferList(streams: [(channels: 1, frames: 2)])
        input.fill(0, with: [0.5, 0.5])
        let output = TestBufferList(streams: [(channels: 1, frames: 2)])
        let state = run(routing: routing(feed: 5), input: input, output: output)
        defer { lucid_passthrough_destroy(state) }
        #expect(output.samples(0) == [0, 0])
    }
}
```

**Step 2: Run the tests to verify they fail**

Run: `swift test --package-path app`
Expected: FAIL (the `LucidAudioC` target has no sources, or `cannot find 'lucid_passthrough_create' in scope`).

**Step 3: Implement**

`app/Sources/LucidAudioC/include/LucidAudioC.h` (initial):

```c
// Umbrella header for the LucidAudioC module.
#pragma once

#include "LucidPassthrough.h"
```

`app/Sources/LucidAudioC/include/LucidPassthrough.h`:

```c
// Realtime pass-through IOProc for the LucidMic aggregate device.
// Everything the IOProc touches is preallocated; meters are lock-free atomics.
#pragma once

#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct LucidPassthrough LucidPassthrough;

/// Where the IOProc finds the mic in the input list and the feed/monitor in the output list.
typedef struct LucidRouting {
    uint32_t inputBuffer;         ///< Index of the mic stream in the input AudioBufferList.
    uint32_t inputChannel;        ///< Channel to take from that interleaved stream.
    uint32_t feedBuffer;          ///< Index of the LucidMic Feed stream in the output list.
    int32_t monitorFirstBuffer;   ///< First monitor stream in the output list, or -1.
    uint32_t monitorBufferCount;  ///< Number of monitor streams.
    double sampleRate;            ///< Aggregate nominal sample rate.
} LucidRouting;

LucidPassthrough *lucid_passthrough_create(LucidRouting routing);
void lucid_passthrough_destroy(LucidPassthrough *state);

void lucid_passthrough_set_monitor(LucidPassthrough *state, bool enabled);

/// Peak |sample| since the previous call, then resets to 0.
float lucid_passthrough_take_input_peak(LucidPassthrough *state);
float lucid_passthrough_take_output_peak(LucidPassthrough *state);
/// Max callback duration / buffer duration since the previous call, then resets to 0.
double lucid_passthrough_take_max_load(LucidPassthrough *state);
uint64_t lucid_passthrough_callback_count(LucidPassthrough *state);

/// Registers lucid_passthrough_ioproc on `device` with `state` as client data.
OSStatus lucid_passthrough_create_ioproc(AudioObjectID device, LucidPassthrough *state,
                                         AudioDeviceIOProcID *outProc);

/// AudioDeviceIOProc. Pass the LucidPassthrough pointer as clientData.
OSStatus lucid_passthrough_ioproc(AudioObjectID device, const AudioTimeStamp *now,
                                  const AudioBufferList *input, const AudioTimeStamp *inputTime,
                                  AudioBufferList *output, const AudioTimeStamp *outputTime,
                                  void *clientData);
```

`app/Sources/LucidAudioC/LucidPassthrough.c`:

```c
#include "LucidPassthrough.h"

#include <mach/mach_time.h>
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct LucidPassthrough {
    LucidRouting routing;
    double secondsPerTick;
    _Atomic bool monitorEnabled;
    _Atomic float inputPeak;
    _Atomic float outputPeak;
    _Atomic double maxLoad;
    _Atomic uint64_t callbackCount;
};

static void atomic_max_float(_Atomic float *target, float value) {
    float current = atomic_load_explicit(target, memory_order_relaxed);
    while (value > current &&
           !atomic_compare_exchange_weak_explicit(target, &current, value, memory_order_relaxed,
                                                  memory_order_relaxed)) {
    }
}

static void atomic_max_double(_Atomic double *target, double value) {
    double current = atomic_load_explicit(target, memory_order_relaxed);
    while (value > current &&
           !atomic_compare_exchange_weak_explicit(target, &current, value, memory_order_relaxed,
                                                  memory_order_relaxed)) {
    }
}

LucidPassthrough *lucid_passthrough_create(LucidRouting routing) {
    LucidPassthrough *state = calloc(1, sizeof(LucidPassthrough));
    if (!state) return NULL;
    state->routing = routing;
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    state->secondsPerTick = (double)tb.numer / (double)tb.denom / 1e9;
    atomic_init(&state->monitorEnabled, false);
    atomic_init(&state->inputPeak, 0.0f);
    atomic_init(&state->outputPeak, 0.0f);
    atomic_init(&state->maxLoad, 0.0);
    atomic_init(&state->callbackCount, 0);
    return state;
}

void lucid_passthrough_destroy(LucidPassthrough *state) { free(state); }

void lucid_passthrough_set_monitor(LucidPassthrough *state, bool enabled) {
    atomic_store_explicit(&state->monitorEnabled, enabled, memory_order_relaxed);
}

float lucid_passthrough_take_input_peak(LucidPassthrough *state) {
    return atomic_exchange_explicit(&state->inputPeak, 0.0f, memory_order_relaxed);
}

float lucid_passthrough_take_output_peak(LucidPassthrough *state) {
    return atomic_exchange_explicit(&state->outputPeak, 0.0f, memory_order_relaxed);
}

double lucid_passthrough_take_max_load(LucidPassthrough *state) {
    return atomic_exchange_explicit(&state->maxLoad, 0.0, memory_order_relaxed);
}

uint64_t lucid_passthrough_callback_count(LucidPassthrough *state) {
    return atomic_load_explicit(&state->callbackCount, memory_order_relaxed);
}

static void zero_outputs(AudioBufferList *output) {
    for (UInt32 b = 0; b < output->mNumberBuffers; ++b) {
        if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    }
}

// Writes mono samples into every channel of an interleaved float stream.
static void write_mono(AudioBuffer *dst, const float *mono, UInt32 frames) {
    float *out = (float *)dst->mData;
    const UInt32 channels = dst->mNumberChannels;
    const UInt32 capacity = dst->mDataByteSize / (sizeof(float) * (channels ? channels : 1));
    const UInt32 n = frames < capacity ? frames : capacity;
    for (UInt32 i = 0; i < n; ++i) {
        for (UInt32 c = 0; c < channels; ++c) out[i * channels + c] = mono[i];
    }
}

OSStatus lucid_passthrough_ioproc(AudioObjectID device, const AudioTimeStamp *now,
                                  const AudioBufferList *input, const AudioTimeStamp *inputTime,
                                  AudioBufferList *output, const AudioTimeStamp *outputTime,
                                  void *clientData) {
    (void)device; (void)now; (void)inputTime; (void)outputTime;
    LucidPassthrough *state = (LucidPassthrough *)clientData;
    const uint64_t start = mach_absolute_time();
    const LucidRouting r = state->routing;

    zero_outputs(output);
    if (!input || r.inputBuffer >= input->mNumberBuffers || r.feedBuffer >= output->mNumberBuffers) {
        return noErr;
    }

    const AudioBuffer *in = &input->mBuffers[r.inputBuffer];
    const UInt32 inChannels = in->mNumberChannels ? in->mNumberChannels : 1;
    const UInt32 frames = in->mDataByteSize / (sizeof(float) * inChannels);
    const float *src = (const float *)in->mData;

    enum { kMaxFrames = 4096 };
    float mono[kMaxFrames];
    const UInt32 n = frames < kMaxFrames ? frames : kMaxFrames;
    float inPeak = 0.0f;
    for (UInt32 i = 0; i < n; ++i) {
        const float s = r.inputChannel < inChannels ? src[i * inChannels + r.inputChannel] : 0.0f;
        mono[i] = s;
        const float a = fabsf(s);
        if (a > inPeak) inPeak = a;
    }

    write_mono(&output->mBuffers[r.feedBuffer], mono, n);

    if (atomic_load_explicit(&state->monitorEnabled, memory_order_relaxed) && r.monitorFirstBuffer >= 0) {
        for (UInt32 m = 0; m < r.monitorBufferCount; ++m) {
            const UInt32 b = (UInt32)r.monitorFirstBuffer + m;
            if (b < output->mNumberBuffers) write_mono(&output->mBuffers[b], mono, n);
        }
    }

    atomic_max_float(&state->inputPeak, inPeak);
    atomic_max_float(&state->outputPeak, inPeak);  // pass-through: output == input
    atomic_fetch_add_explicit(&state->callbackCount, 1, memory_order_relaxed);

    if (r.sampleRate > 0 && n > 0) {
        const double elapsed = (double)(mach_absolute_time() - start) * state->secondsPerTick;
        atomic_max_double(&state->maxLoad, elapsed / ((double)n / r.sampleRate));
    }
    return noErr;
}

OSStatus lucid_passthrough_create_ioproc(AudioObjectID device, LucidPassthrough *state,
                                         AudioDeviceIOProcID *outProc) {
    return AudioDeviceCreateIOProcID(device, lucid_passthrough_ioproc, state, outProc);
}
```

**Step 4: Run the tests to verify they pass**

Run: `swift test --package-path app`
Expected: `Test run with 5 tests in 1 suite passed`.

**Step 5: Commit**

```bash
git add app/
git commit -m "feat(app): realtime pass-through IOProc with lock-free meters

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 7: Core Audio helpers, device model, and DeviceSelection, TDD

**Files:**
- Modify: `app/Package.swift` (add the `LucidAudio` target, below)
- Create: `app/Sources/LucidAudio/CoreAudioProperty.swift`, `app/Sources/LucidAudio/AudioDevice.swift`, `app/Sources/LucidAudio/DeviceSelection.swift`
- Test: `app/Tests/LucidAudioTests/TestDevices.swift`, `app/Tests/LucidAudioTests/DeviceSelectionTests.swift`

**Key rule under test:** LucidMic must never offer its own devices, or any aggregate, as the
source mic. Otherwise, making "LucidMic Microphone" the system default would create a feedback
loop.

**Step 1: Write the failing tests**

`app/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LucidMic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LucidAudioC", linkerSettings: [.linkedFramework("CoreAudio")]),
        .target(
            name: "LucidAudio",
            dependencies: ["LucidAudioC"],
            linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("AVFoundation")]
        ),
        .testTarget(name: "LucidAudioTests", dependencies: ["LucidAudio", "LucidAudioC"]),
    ]
)
```

`app/Tests/LucidAudioTests/TestDevices.swift`:

```swift
import LucidAudio

func device(_ uid: String, inputs: [Int] = [], outputs: [Int] = [], aggregate: Bool = false) -> AudioDevice {
    AudioDevice(id: 0, uid: uid, name: uid, inputStreams: inputs, outputStreams: outputs, isAggregate: aggregate)
}
```

`app/Tests/LucidAudioTests/DeviceSelectionTests.swift`:

```swift
import LucidAudio
import Testing

@Suite struct DeviceSelectionTests {
    let builtIn = device("BuiltInMic", inputs: [1])
    let usb = device("USBMic", inputs: [2])
    let lucidMic = device(LucidDeviceUID.microphone, inputs: [1])
    let feed = device(LucidDeviceUID.feed, outputs: [1])
    let aggregate = device("SomeAggregate", inputs: [1], outputs: [2], aggregate: true)
    let speakers = device("Speakers", outputs: [2])

    @Test func inputsExcludeOwnDevicesAndAggregates() {
        let result = DeviceSelection.selectableInputs([builtIn, lucidMic, feed, aggregate, usb, speakers])
        #expect(result.map(\.uid) == ["BuiltInMic", "USBMic"])
    }

    @Test func outputsExcludeOwnDevicesAndAggregates() {
        let result = DeviceSelection.selectableOutputs([builtIn, feed, aggregate, speakers])
        #expect(result.map(\.uid) == ["Speakers"])
    }

    @Test func prefersSavedThenDefaultThenFirst() {
        let candidates = [builtIn, usb]
        #expect(DeviceSelection.choose(candidates, savedUID: "USBMic", systemDefaultUID: "BuiltInMic")?.uid == "USBMic")
        #expect(DeviceSelection.choose(candidates, savedUID: "Gone", systemDefaultUID: "USBMic")?.uid == "USBMic")
        #expect(
            DeviceSelection.choose(candidates, savedUID: nil, systemDefaultUID: LucidDeviceUID.microphone)?.uid
                == "BuiltInMic")
        #expect(DeviceSelection.choose([], savedUID: nil, systemDefaultUID: nil) == nil)
    }
}
```

**Step 2: Run the tests to verify they fail**

Run: `swift test --package-path app`
Expected: FAIL (`LucidAudio` has no sources, or `cannot find 'DeviceSelection' in scope`).

**Step 3: Implement**

`app/Sources/LucidAudio/CoreAudioProperty.swift`:

```swift
import CoreAudio
import Foundation

public struct CoreAudioError: Error, CustomStringConvertible {
    public let status: OSStatus
    public let operation: String
    public var description: String { "\(operation) failed with OSStatus \(status)" }
}

@inline(__always)
func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, operation: operation()) }
}

func address(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func getScalar<T: BitwiseCopyable>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ initial: T) throws
    -> T
{
    var addr = addr
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value), "get \(addr.mSelector)")
    return value
}

func setScalar<T: BitwiseCopyable>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T) throws {
    var addr = addr
    var value = value
    try check(
        AudioObjectSetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &value),
        "set \(addr.mSelector)")
}

func getString(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress) throws -> String {
    var addr = addr
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value), "get string \(addr.mSelector)")
    return (value?.takeRetainedValue() as String?) ?? ""
}

func getArray<T: BitwiseCopyable>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, of _: T.Type) throws
    -> [T]
{
    var addr = addr
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size), "size \(addr.mSelector)")
    let count = Int(size) / MemoryLayout<T>.stride
    guard count > 0 else { return [] }
    let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
    defer { buffer.deallocate() }
    try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, buffer), "get \(addr.mSelector)")
    return Array(UnsafeBufferPointer(start: buffer, count: count))
}

/// Channel count of each stream of a device in one direction, in stream order.
func streamChannelCounts(_ device: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [Int] {
    var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size), "stream config size")
    guard size > 0 else { return [] }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
    try check(AudioObjectGetPropertyData(device, &addr, 0, nil, &size, list), "stream config")
    return UnsafeMutableAudioBufferListPointer(list).map { Int($0.mNumberChannels) }
}
```

`app/Sources/LucidAudio/AudioDevice.swift`:

```swift
import CoreAudio
import Foundation

public struct AudioDevice: Hashable, Identifiable, Sendable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String
    public let inputStreams: [Int]  // channels per input stream
    public let outputStreams: [Int]  // channels per output stream
    public let isAggregate: Bool

    public var inputChannels: Int { inputStreams.reduce(0, +) }
    public var outputChannels: Int { outputStreams.reduce(0, +) }

    public init(
        id: AudioObjectID, uid: String, name: String, inputStreams: [Int], outputStreams: [Int], isAggregate: Bool
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.inputStreams = inputStreams
        self.outputStreams = outputStreams
        self.isAggregate = isAggregate
    }
}

public enum LucidDeviceUID {
    public static let prefix = "com.sultanovazamat.lucidmic."
    public static let microphone = prefix + "microphone"
    public static let feed = prefix + "feed"
    public static let engineAggregate = prefix + "engine"
}

public enum AudioSystem {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    public static func devices() throws -> [AudioDevice] {
        try getArray(system, address(kAudioHardwarePropertyDevices), of: AudioObjectID.self).compactMap {
            try? device(id: $0)
        }
    }

    public static func device(id: AudioObjectID) throws -> AudioDevice {
        let transport = (try? getScalar(id, address(kAudioDevicePropertyTransportType), UInt32(0))) ?? 0
        return AudioDevice(
            id: id,
            uid: try getString(id, address(kAudioDevicePropertyDeviceUID)),
            name: try getString(id, address(kAudioObjectPropertyName)),
            inputStreams: try streamChannelCounts(id, scope: kAudioObjectPropertyScopeInput),
            outputStreams: try streamChannelCounts(id, scope: kAudioObjectPropertyScopeOutput),
            isAggregate: transport == kAudioDeviceTransportTypeAggregate)
    }

    /// Finds a device by UID, including hidden devices such as LucidMic Feed.
    public static func device(uid: String) -> AudioDevice? {
        var addr = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var qualifier: CFString = uid as CFString
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &qualifier) {
            AudioObjectGetPropertyData(system, &addr, UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return try? device(id: id)
    }

    public static func defaultDevice(input: Bool) -> AudioObjectID? {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        let id = (try? getScalar(system, address(selector), AudioObjectID(kAudioObjectUnknown))) ?? kAudioObjectUnknown
        return id == kAudioObjectUnknown ? nil : id
    }
}
```

`app/Sources/LucidAudio/DeviceSelection.swift`:

```swift
/// Pure device-choice rules, kept free of Core Audio calls so they are unit-testable.
public enum DeviceSelection {
    /// Physical inputs the user may pick: never LucidMic's own devices, never aggregates.
    public static func selectableInputs(_ devices: [AudioDevice]) -> [AudioDevice] {
        devices.filter { $0.inputChannels > 0 && !isOwn($0) && !$0.isAggregate }
    }

    public static func selectableOutputs(_ devices: [AudioDevice]) -> [AudioDevice] {
        devices.filter { $0.outputChannels > 0 && !isOwn($0) && !$0.isAggregate }
    }

    /// Saved choice if still present, else the system default, else the first candidate.
    public static func choose(_ candidates: [AudioDevice], savedUID: String?, systemDefaultUID: String?) -> AudioDevice?
    {
        if let saved = savedUID, let match = candidates.first(where: { $0.uid == saved }) { return match }
        if let def = systemDefaultUID, let match = candidates.first(where: { $0.uid == def }) { return match }
        return candidates.first
    }

    public static func isOwn(_ device: AudioDevice) -> Bool { device.uid.hasPrefix(LucidDeviceUID.prefix) }
}
```

**Step 4: Run the tests to verify they pass**

Run: `swift test --package-path app`
Expected: 8 tests pass.

**Step 5: Commit**

```bash
git add app/
git commit -m "feat(app): Core Audio device catalog and selection rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 8: SubdeviceLayout + AggregateDescription, TDD

**Files:**
- Create: `app/Sources/LucidAudio/SubdeviceLayout.swift`, `app/Sources/LucidAudio/AggregateDescription.swift`
- Test: `app/Tests/LucidAudioTests/SubdeviceLayoutTests.swift`, `app/Tests/LucidAudioTests/AggregateDescriptionTests.swift`

**Why:** an aggregate's IOProc buffer lists join each subdevice's streams in order (mic, feed,
monitor). A headset mic has its own outputs, which shift the feed to a later buffer index. Get
this wrong and the audio goes to the wrong device.

**Step 1: Write the failing tests**

`app/Tests/LucidAudioTests/SubdeviceLayoutTests.swift`:

```swift
import LucidAudio
import Testing

@Suite struct SubdeviceLayoutTests {
    let mic = device("Mic", inputs: [1])
    let headset = device("Headset", inputs: [1], outputs: [2])
    let feed = device(LucidDeviceUID.feed, outputs: [1])
    let speakers = device("Speakers", outputs: [2])

    @Test func feedFollowsMicOutputs() {
        let plan = SubdeviceLayout.plan(mic: mic, feed: feed, monitor: nil)
        #expect(plan == .init(inputBuffer: 0, feedBuffer: 0, monitorFirstBuffer: nil, monitorBufferCount: 0))
    }

    @Test func monitorAfterFeed() {
        let plan = SubdeviceLayout.plan(mic: mic, feed: feed, monitor: speakers)
        #expect(plan == .init(inputBuffer: 0, feedBuffer: 0, monitorFirstBuffer: 1, monitorBufferCount: 1))
    }

    @Test func headsetMicShiftsFeedAndMonitorsItself() {
        let plan = SubdeviceLayout.plan(mic: headset, feed: feed, monitor: headset)
        #expect(plan == .init(inputBuffer: 0, feedBuffer: 1, monitorFirstBuffer: 0, monitorBufferCount: 1))
    }

    @Test func rejectsMicWithoutInputs() {
        #expect(SubdeviceLayout.plan(mic: speakers, feed: feed, monitor: nil) == nil)
    }
}
```

`app/Tests/LucidAudioTests/AggregateDescriptionTests.swift`:

```swift
import CoreAudio
import LucidAudio
import Testing

@Suite struct AggregateDescriptionTests {
    @Test func micIsMainAndOthersAreDriftCompensated() {
        let d = AggregateDescription.engine(micUID: "Mic", feedUID: "Feed", monitorUID: "Speakers")
        #expect(d[kAudioAggregateDeviceMainSubDeviceKey] as? String == "Mic")
        #expect(d[kAudioAggregateDeviceIsPrivateKey] as? Int == 1)
        let subs = d[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]] ?? []
        #expect(subs.map { $0[kAudioSubDeviceUIDKey] as? String } == ["Mic", "Feed", "Speakers"])
        #expect(subs[0][kAudioSubDeviceDriftCompensationKey] == nil)
        #expect(subs[1][kAudioSubDeviceDriftCompensationKey] as? Int == 1)
    }

    @Test func headsetMonitorIsNotAddedTwice() {
        let d = AggregateDescription.engine(micUID: "Headset", feedUID: "Feed", monitorUID: "Headset")
        let subs = d[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]] ?? []
        #expect(subs.count == 2)
    }
}
```

**Step 2: Run the tests to verify they fail**

Run: `swift test --package-path app`
Expected: FAIL `cannot find 'SubdeviceLayout' in scope`.

**Step 3: Implement**

`app/Sources/LucidAudio/SubdeviceLayout.swift`:

```swift
import LucidAudioC

/// Computes where each subdevice's streams land in the aggregate's IOProc buffer lists.
/// Aggregate buffer lists concatenate subdevice streams in subdevice order: mic, feed, monitor.
public enum SubdeviceLayout {
    public struct Plan: Equatable, Sendable {
        public var inputBuffer: Int
        public var feedBuffer: Int
        public var monitorFirstBuffer: Int?
        public var monitorBufferCount: Int

        public init(inputBuffer: Int, feedBuffer: Int, monitorFirstBuffer: Int?, monitorBufferCount: Int) {
            self.inputBuffer = inputBuffer
            self.feedBuffer = feedBuffer
            self.monitorFirstBuffer = monitorFirstBuffer
            self.monitorBufferCount = monitorBufferCount
        }
    }

    public static func plan(mic: AudioDevice, feed: AudioDevice, monitor: AudioDevice?) -> Plan? {
        guard !mic.inputStreams.isEmpty, !feed.outputStreams.isEmpty else { return nil }
        let feedBuffer = mic.outputStreams.count
        guard let monitor, !monitor.outputStreams.isEmpty else {
            return Plan(inputBuffer: 0, feedBuffer: feedBuffer, monitorFirstBuffer: nil, monitorBufferCount: 0)
        }
        if monitor.uid == mic.uid {
            // Headset: the monitor streams are the mic subdevice's own outputs.
            return Plan(
                inputBuffer: 0, feedBuffer: feedBuffer, monitorFirstBuffer: 0,
                monitorBufferCount: mic.outputStreams.count)
        }
        return Plan(
            inputBuffer: 0, feedBuffer: feedBuffer, monitorFirstBuffer: feedBuffer + feed.outputStreams.count,
            monitorBufferCount: monitor.outputStreams.count)
    }

    public static func routing(_ plan: Plan, sampleRate: Double) -> LucidRouting {
        LucidRouting(
            inputBuffer: UInt32(plan.inputBuffer),
            inputChannel: 0,
            feedBuffer: UInt32(plan.feedBuffer),
            monitorFirstBuffer: Int32(plan.monitorFirstBuffer ?? -1),
            monitorBufferCount: UInt32(plan.monitorBufferCount),
            sampleRate: sampleRate)
    }
}
```

`app/Sources/LucidAudio/AggregateDescription.swift`: use the file below. It already contains the
`loopbackProbe`/`latencyProbe` builders used in Tasks 11–12. They are pure dictionary builders,
so committing them now is fine.

`app/Sources/LucidAudio/AggregateDescription.swift`:

```swift
import CoreAudio

/// Builds private aggregate descriptions. The first UID is the clock master;
/// every other subdevice is drift-compensated against it.
public enum AggregateDescription {
    public static func engine(micUID: String, feedUID: String, monitorUID: String?) -> [String: Any] {
        var others = [feedUID]
        if let monitorUID, monitorUID != micUID { others.append(monitorUID) }
        return make(name: "LucidMic Engine", uid: LucidDeviceUID.engineAggregate, mainUID: micUID, others: others)
    }

    public static func latencyProbe(micUID: String, lucidMicUID: String) -> [String: Any] {
        make(
            name: "LucidMic Latency Probe", uid: LucidDeviceUID.prefix + "latency-probe", mainUID: micUID,
            others: [lucidMicUID])
    }

    public static func loopbackProbe(lucidMicUID: String, feedUID: String) -> [String: Any] {
        make(
            name: "LucidMic Loopback Probe", uid: LucidDeviceUID.prefix + "loopback-probe", mainUID: lucidMicUID,
            others: [feedUID])
    }

    static func make(name: String, uid: String, mainUID: String, others: [String]) -> [String: Any] {
        let subdevices: [[String: Any]] =
            [[kAudioSubDeviceUIDKey: mainUID]]
            + others.map { [kAudioSubDeviceUIDKey: $0, kAudioSubDeviceDriftCompensationKey: 1] }
        return [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: mainUID,
            kAudioAggregateDeviceSubDeviceListKey: subdevices,
        ]
    }
}

/// Creates and destroys private aggregates. Kept nonisolated and free of
/// `[String: Any]` in callers to sidestep a Swift 6.3 region-analysis crash.
public enum AggregateDevice {
    public static func createEngine(micUID: String, feedUID: String, monitorUID: String?) throws -> AudioObjectID {
        try create(AggregateDescription.engine(micUID: micUID, feedUID: feedUID, monitorUID: monitorUID))
    }

    public static func createLatencyProbe(micUID: String, lucidMicUID: String) throws -> AudioObjectID {
        try create(AggregateDescription.latencyProbe(micUID: micUID, lucidMicUID: lucidMicUID))
    }

    public static func createLoopbackProbe(lucidMicUID: String, feedUID: String) throws -> AudioObjectID {
        try create(AggregateDescription.loopbackProbe(lucidMicUID: lucidMicUID, feedUID: feedUID))
    }

    public static func destroy(_ id: AudioObjectID) {
        AudioHardwareDestroyAggregateDevice(id)
    }

    private static func create(_ description: [String: Any]) throws -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &id), "create aggregate")
        return id
    }
}
```

**Step 4: Run the tests to verify they pass**

Run: `swift test --package-path app`
Expected: 14 tests pass.

**Step 5: Commit**

```bash
git add app/
git commit -m "feat(app): aggregate buffer layout and private aggregate description

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 9: DelayEstimator + LatencyEstimate, TDD

**Files:**
- Create: `app/Sources/LucidAudio/DelayEstimator.swift`, `app/Sources/LucidAudio/LatencyEstimate.swift`
- Test: `app/Tests/LucidAudioTests/DelayEstimatorTests.swift`, `app/Tests/LucidAudioTests/LatencyEstimateTests.swift`

**Step 1: Write the failing tests**

`app/Tests/LucidAudioTests/DelayEstimatorTests.swift`:

```swift
import LucidAudio
import Testing

@Suite struct DelayEstimatorTests {
    @Test func findsKnownDelay() {
        var reference = [Float](repeating: 0, count: 2000)
        for i in stride(from: 100, to: 1500, by: 97) { reference[i] = 1 }  // sparse clicks
        let lag = 37
        let delayed = [Float](repeating: 0, count: lag) + reference.dropLast(lag)
        #expect(DelayEstimator.estimateLag(reference: reference, delayed: delayed, maxLag: 200) == lag)
    }

    @Test func silenceGivesNil() {
        let zeros = [Float](repeating: 0, count: 1000)
        #expect(DelayEstimator.estimateLag(reference: zeros, delayed: zeros, maxLag: 100) == nil)
    }
}
```

`app/Tests/LucidAudioTests/LatencyEstimateTests.swift`:

```swift
import LucidAudio
import Testing

@Suite struct LatencyEstimateTests {
    @Test func twoBuffersPlusOutputLatency() {
        let ms = LatencyEstimate.addedMilliseconds(
            bufferFrames: 64, outputLatencyFrames: 32, outputSafetyFrames: 16, sampleRate: 48_000)
        #expect(abs(ms - 3.667) < 0.01)  // (2*64 + 32 + 16) / 48000 s
    }
}
```

**Step 2: Run the tests to verify they fail**

Run: `swift test --package-path app`
Expected: FAIL `cannot find 'DelayEstimator' in scope`.

**Step 3: Implement**

`app/Sources/LucidAudio/DelayEstimator.swift`:

```swift
import Accelerate

public enum DelayEstimator {
    /// Lag (in samples, 0...maxLag) at which `delayed` best matches `reference`,
    /// by normalized cross-correlation. Returns nil if either signal is silent.
    public static func estimateLag(reference: [Float], delayed: [Float], maxLag: Int) -> Int? {
        let n = min(reference.count, delayed.count) - maxLag
        guard n > 0 else { return nil }
        let refEnergy = vDSP.sumOfSquares(reference[0..<n])
        guard refEnergy > 0 else { return nil }

        var bestLag: Int?
        var bestScore: Float = 0
        for lag in 0...maxLag {
            let window = delayed[lag..<(lag + n)]
            let energy = vDSP.sumOfSquares(window)
            guard energy > 0 else { continue }
            let score = vDSP.dot(reference[0..<n], window) / (refEnergy * energy).squareRoot()
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        return bestLag
    }
}
```

`app/Sources/LucidAudio/LatencyEstimate.swift`:

```swift
public enum LatencyEstimate {
    /// Added latency vs. using the mic directly: our input buffer + our output buffer + the feed's output latency.
    public static func addedMilliseconds(
        bufferFrames: UInt32, outputLatencyFrames: UInt32, outputSafetyFrames: UInt32, sampleRate: Double
    ) -> Double {
        guard sampleRate > 0 else { return 0 }
        let frames = Double(2 * bufferFrames + outputLatencyFrames + outputSafetyFrames)
        return frames / sampleRate * 1000
    }
}
```

**Step 4: Run the tests to verify they pass**

Run: `swift test --package-path app`
Expected: 17 tests pass.

**Step 5: Commit**

```bash
git add app/
git commit -m "feat(app): cross-correlation delay estimator and latency estimate

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 10: PassthroughPipeline (aggregate + IOProc lifecycle)

**Files:**
- Create: `app/Sources/LucidAudio/PassthroughPipeline.swift`
- Modify: `app/Sources/LucidAudioC/include/LucidPassthrough.h` and `LucidPassthrough.c`. The
  Task 6 versions above already contain `lucid_passthrough_create_ioproc`. If you trimmed it,
  add it back now.

This is Core Audio glue with no pure logic left to unit-test. It is verified by building here
and by the end-to-end run in Task 13.

**Step 1: Implement**

`app/Sources/LucidAudio/PassthroughPipeline.swift`:

```swift
import AVFoundation
import CoreAudio
import LucidAudioC

public enum PipelineError: Error, CustomStringConvertible {
    case driverMissing
    case unusableDevices
    case outOfMemory

    public var description: String {
        switch self {
        case .driverMissing: "LucidMic driver is not installed (LucidMic Feed not found)."
        case .unusableDevices: "The selected microphone has no input streams."
        case .outOfMemory: "Could not allocate the audio state."
        }
    }
}

public struct Meters: Sendable, Equatable {
    public var inputPeak: Float = 0
    public var outputPeak: Float = 0
    public var load: Double = 0
    public var overloads: Int = 0

    public init(inputPeak: Float = 0, outputPeak: Float = 0, load: Double = 0, overloads: Int = 0) {
        self.inputPeak = inputPeak
        self.outputPeak = outputPeak
        self.load = load
        self.overloads = overloads
    }
}

/// Owns the private aggregate device and the realtime pass-through IOProc.
@MainActor
public final class PassthroughPipeline {
    public private(set) var isRunning = false
    public private(set) var estimatedAddedLatencyMs: Double = 0

    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var state: OpaquePointer?
    private var overloadCount = 0
    private var overloadListener: AudioObjectPropertyListenerBlock?

    public init() {}

    public static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func start(mic: AudioDevice, monitor: AudioDevice?, monitorEnabled: Bool, bufferFrames: UInt32 = 64) throws {
        stop()
        guard let feed = AudioSystem.device(uid: LucidDeviceUID.feed) else { throw PipelineError.driverMissing }
        guard let plan = SubdeviceLayout.plan(mic: mic, feed: feed, monitor: monitor) else {
            throw PipelineError.unusableDevices
        }
        let aggregate = try AggregateDevice.createEngine(micUID: mic.uid, feedUID: feed.uid, monitorUID: monitor?.uid)
        aggregateID = aggregate

        do {
            try? setScalar(aggregate, address(kAudioDevicePropertyNominalSampleRate), Float64(48_000))
            try? setScalar(aggregate, address(kAudioDevicePropertyBufferFrameSize), bufferFrames)
            let rate = try getScalar(aggregate, address(kAudioDevicePropertyNominalSampleRate), Float64(0))
            let frames = try getScalar(aggregate, address(kAudioDevicePropertyBufferFrameSize), UInt32(0))

            guard let newState = lucid_passthrough_create(SubdeviceLayout.routing(plan, sampleRate: rate)) else {
                throw PipelineError.outOfMemory
            }
            state = newState
            lucid_passthrough_set_monitor(newState, monitorEnabled)

            let newProc = try Self.createIOProc(on: aggregate, state: newState)
            procID = newProc
            installOverloadListener(on: aggregate)
            try check(AudioDeviceStart(aggregate, newProc), "start aggregate")
            isRunning = true

            let outLatency =
                (try? getScalar(
                    aggregate, address(kAudioDevicePropertyLatency, kAudioObjectPropertyScopeOutput), UInt32(0))) ?? 0
            let outSafety =
                (try? getScalar(
                    aggregate, address(kAudioDevicePropertySafetyOffset, kAudioObjectPropertyScopeOutput), UInt32(0)))
                ?? 0
            estimatedAddedLatencyMs = LatencyEstimate.addedMilliseconds(
                bufferFrames: frames, outputLatencyFrames: outLatency, outputSafetyFrames: outSafety, sampleRate: rate)
        } catch {
            stop()
            throw error
        }
    }

    nonisolated private static func createIOProc(on device: AudioObjectID, state: OpaquePointer) throws
        -> AudioDeviceIOProcID
    {
        var proc: AudioDeviceIOProcID?
        try check(
            lucid_passthrough_create_ioproc(device, state, &proc),
            "create IOProc")
        guard let proc else { throw CoreAudioError(status: -1, operation: "create IOProc") }
        return proc
    }

    public func setMonitor(_ enabled: Bool) {
        if let state { lucid_passthrough_set_monitor(state, enabled) }
    }

    public func takeMeters() -> Meters {
        guard let state else { return Meters() }
        return Meters(
            inputPeak: lucid_passthrough_take_input_peak(state),
            outputPeak: lucid_passthrough_take_output_peak(state),
            load: lucid_passthrough_take_max_load(state),
            overloads: overloadCount)
    }

    public func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            removeOverloadListener(from: aggregateID)
            AggregateDevice.destroy(aggregateID)
        }
        if let state { lucid_passthrough_destroy(state) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        procID = nil
        state = nil
        isRunning = false
        estimatedAddedLatencyMs = 0
    }

    private func installOverloadListener(on device: AudioObjectID) {
        var addr = address(kAudioDeviceProcessorOverload)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.overloadCount += 1 }
        }
        if AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main, listener) == noErr {
            overloadListener = listener
        }
    }

    private func removeOverloadListener(from device: AudioObjectID) {
        guard let listener = overloadListener else { return }
        var addr = address(kAudioDeviceProcessorOverload)
        AudioObjectRemovePropertyListenerBlock(device, &addr, DispatchQueue.main, listener)
        overloadListener = nil
    }
}
```

**Step 2: Build and run the existing tests**

Run: `swift build --package-path app && swift test --package-path app`
Expected: `Build complete!` and 17 tests pass.

**Step 3: Commit**

```bash
git add app/
git commit -m "feat(app): passthrough pipeline over a private aggregate device

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 11: Driver loopback integration test (runs after the driver is installed)

**Files:**
- Create: `app/Sources/LucidAudioC/include/LucidProbe.h`, `app/Sources/LucidAudioC/LucidProbe.c`,
  `app/Sources/LucidAudioC/include/LucidRecorder.h`, `app/Sources/LucidAudioC/LucidRecorder.c`
- Modify: `app/Sources/LucidAudioC/include/LucidAudioC.h` (final umbrella below)
- Test: `app/Tests/LucidAudioTests/DriverLoopbackTests.swift`

**Step 1: Write the test (opt-in with `LUCIDMIC_INTEGRATION=1`)**

`app/Tests/LucidAudioTests/DriverLoopbackTests.swift`:

```swift
import CoreAudio
import Foundation
import LucidAudio
import LucidAudioC
import Testing

/// Requires the installed driver. Run with: LUCIDMIC_INTEGRATION=1 swift test --filter DriverLoopback
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LUCIDMIC_INTEGRATION"] == "1"))
struct DriverLoopbackTests {
    @Test func feedComesBackBitExactFromMicrophone() async throws {
        let mic = try #require(AudioSystem.device(uid: LucidDeviceUID.microphone), "driver not installed")
        let feed = try #require(AudioSystem.device(uid: LucidDeviceUID.feed), "feed device not found")

        let frames = 48_000  // 1 s
        var generator = SystemRandomNumberGenerator()
        let signal = (0..<frames).map { _ in Float.random(in: -0.5...0.5, using: &generator) }

        let aggregate = try AggregateDevice.createLoopbackProbe(lucidMicUID: mic.uid, feedUID: feed.uid)
        defer { AggregateDevice.destroy(aggregate) }
        let probe = try #require(
            signal.withUnsafeBufferPointer { lucid_probe_create($0.baseAddress, UInt32(frames), 0, 0) })
        defer { lucid_probe_destroy(probe) }

        var proc: AudioDeviceIOProcID?
        #expect(lucid_probe_create_ioproc(aggregate, probe, &proc) == noErr)
        #expect(AudioDeviceStart(aggregate, proc) == noErr)
        while lucid_probe_frames_done(probe) < UInt32(frames) { try await Task.sleep(for: .milliseconds(50)) }
        AudioDeviceStop(aggregate, proc)
        AudioDeviceDestroyIOProcID(aggregate, try #require(proc))

        let recorded = Array(UnsafeBufferPointer(start: lucid_probe_recorded(probe), count: frames))
        let lag = try #require(DelayEstimator.estimateLag(reference: signal, delayed: recorded, maxLag: 4_800) as Int?)
        print("Feed → Microphone loopback delay: \(lag) samples (\(Double(lag) / 48.0) ms)")

        let checked = frames - lag - 1_000
        let mismatches = (0..<checked).filter { recorded[lag + $0] != signal[$0] }.count
        #expect(mismatches == 0)
    }
}
```

**Step 2: Run it to verify it fails**

Run: `make test-integration`
Expected: compile error `cannot find 'lucid_probe_create' in scope`.

**Step 3: Implement the probe and recorder**

`app/Sources/LucidAudioC/include/LucidAudioC.h`:

```c
// Umbrella header for the LucidAudioC module.
#pragma once

#include "LucidPassthrough.h"
#include "LucidProbe.h"
#include "LucidRecorder.h"
```

`app/Sources/LucidAudioC/include/LucidProbe.h`:

```c
// Realtime loopback probe for integration tests: plays a known signal into one
// output stream and records one input stream, sample-aligned by IO cycle.
#pragma once

#include <CoreAudio/CoreAudio.h>
#include <stdint.h>

typedef struct LucidProbe LucidProbe;

/// `signal` (copied) is played into output buffer `outputBuffer`; input buffer `inputBuffer` channel 0 is recorded.
LucidProbe *lucid_probe_create(const float *signal, uint32_t frames, uint32_t inputBuffer, uint32_t outputBuffer);
void lucid_probe_destroy(LucidProbe *probe);
uint32_t lucid_probe_frames_done(const LucidProbe *probe);
const float *lucid_probe_recorded(const LucidProbe *probe);

OSStatus lucid_probe_create_ioproc(AudioObjectID device, LucidProbe *probe, AudioDeviceIOProcID *outProc);
OSStatus lucid_probe_ioproc(AudioObjectID device, const AudioTimeStamp *now, const AudioBufferList *input,
                            const AudioTimeStamp *inputTime, AudioBufferList *output,
                            const AudioTimeStamp *outputTime, void *clientData);
```

`app/Sources/LucidAudioC/LucidProbe.c`:

```c
#include "LucidProbe.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct LucidProbe {
    uint32_t frames;
    uint32_t inputBuffer;
    uint32_t outputBuffer;
    _Atomic uint32_t done;
    float *signal;
    float *recorded;
};

LucidProbe *lucid_probe_create(const float *signal, uint32_t frames, uint32_t inputBuffer, uint32_t outputBuffer) {
    LucidProbe *p = calloc(1, sizeof(LucidProbe));
    if (!p) return NULL;
    p->frames = frames;
    p->inputBuffer = inputBuffer;
    p->outputBuffer = outputBuffer;
    p->signal = malloc(frames * sizeof(float));
    p->recorded = calloc(frames, sizeof(float));
    atomic_init(&p->done, 0);
    if (!p->signal || !p->recorded) {
        lucid_probe_destroy(p);
        return NULL;
    }
    memcpy(p->signal, signal, frames * sizeof(float));
    return p;
}

void lucid_probe_destroy(LucidProbe *p) {
    if (!p) return;
    free(p->signal);
    free(p->recorded);
    free(p);
}

uint32_t lucid_probe_frames_done(const LucidProbe *p) {
    return atomic_load_explicit(&((LucidProbe *)p)->done, memory_order_acquire);
}

const float *lucid_probe_recorded(const LucidProbe *p) { return p->recorded; }

OSStatus lucid_probe_ioproc(AudioObjectID device, const AudioTimeStamp *now, const AudioBufferList *input,
                            const AudioTimeStamp *inputTime, AudioBufferList *output,
                            const AudioTimeStamp *outputTime, void *clientData) {
    (void)device; (void)now; (void)inputTime; (void)outputTime;
    LucidProbe *p = (LucidProbe *)clientData;
    for (UInt32 b = 0; b < output->mNumberBuffers; ++b) {
        if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    }
    const uint32_t done = atomic_load_explicit(&p->done, memory_order_relaxed);
    if (done >= p->frames || !input || p->inputBuffer >= input->mNumberBuffers ||
        p->outputBuffer >= output->mNumberBuffers) {
        return noErr;
    }
    AudioBuffer *out = &output->mBuffers[p->outputBuffer];
    const AudioBuffer *in = &input->mBuffers[p->inputBuffer];
    const uint32_t outCh = out->mNumberChannels ? out->mNumberChannels : 1;
    const uint32_t inCh = in->mNumberChannels ? in->mNumberChannels : 1;
    uint32_t n = out->mDataByteSize / (sizeof(float) * outCh);
    const uint32_t inFrames = in->mDataByteSize / (sizeof(float) * inCh);
    if (inFrames < n) n = inFrames;
    if (n > p->frames - done) n = p->frames - done;

    float *o = (float *)out->mData;
    const float *i = (const float *)in->mData;
    for (uint32_t f = 0; f < n; ++f) {
        for (uint32_t c = 0; c < outCh; ++c) o[f * outCh + c] = p->signal[done + f];
        p->recorded[done + f] = i[f * inCh];
    }
    atomic_store_explicit(&p->done, done + n, memory_order_release);
    return noErr;
}

OSStatus lucid_probe_create_ioproc(AudioObjectID device, LucidProbe *probe, AudioDeviceIOProcID *outProc) {
    return AudioDeviceCreateIOProcID(device, lucid_probe_ioproc, probe, outProc);
}
```

`app/Sources/LucidAudioC/include/LucidRecorder.h`:

```c
// Realtime two-stream recorder used by lucidmic-latency.
// Captures channel 0 of input buffers `first` and `second` into preallocated arrays.
#pragma once

#include <CoreAudio/CoreAudio.h>
#include <stdint.h>

typedef struct LucidRecorder LucidRecorder;

LucidRecorder *lucid_recorder_create(uint32_t capacityFrames, uint32_t firstBuffer, uint32_t secondBuffer);
void lucid_recorder_destroy(LucidRecorder *recorder);
uint32_t lucid_recorder_frames(const LucidRecorder *recorder);
const float *lucid_recorder_first(const LucidRecorder *recorder);
const float *lucid_recorder_second(const LucidRecorder *recorder);

OSStatus lucid_recorder_create_ioproc(AudioObjectID device, LucidRecorder *recorder,
                                      AudioDeviceIOProcID *outProc);

OSStatus lucid_recorder_ioproc(AudioObjectID device, const AudioTimeStamp *now,
                               const AudioBufferList *input, const AudioTimeStamp *inputTime,
                               AudioBufferList *output, const AudioTimeStamp *outputTime,
                               void *clientData);
```

`app/Sources/LucidAudioC/LucidRecorder.c`:

```c
#include "LucidRecorder.h"

#include <stdatomic.h>
#include <stdlib.h>

struct LucidRecorder {
    uint32_t capacity;
    uint32_t firstBuffer;
    uint32_t secondBuffer;
    _Atomic uint32_t frames;
    float *first;
    float *second;
};

LucidRecorder *lucid_recorder_create(uint32_t capacityFrames, uint32_t firstBuffer, uint32_t secondBuffer) {
    LucidRecorder *r = calloc(1, sizeof(LucidRecorder));
    if (!r) return NULL;
    r->capacity = capacityFrames;
    r->firstBuffer = firstBuffer;
    r->secondBuffer = secondBuffer;
    r->first = calloc(capacityFrames, sizeof(float));
    r->second = calloc(capacityFrames, sizeof(float));
    atomic_init(&r->frames, 0);
    if (!r->first || !r->second) {
        lucid_recorder_destroy(r);
        return NULL;
    }
    return r;
}

void lucid_recorder_destroy(LucidRecorder *r) {
    if (!r) return;
    free(r->first);
    free(r->second);
    free(r);
}

uint32_t lucid_recorder_frames(const LucidRecorder *r) {
    return atomic_load_explicit(&((LucidRecorder *)r)->frames, memory_order_acquire);
}

const float *lucid_recorder_first(const LucidRecorder *r) { return r->first; }
const float *lucid_recorder_second(const LucidRecorder *r) { return r->second; }

static void copy_channel0(const AudioBuffer *src, float *dst, uint32_t offset, uint32_t n) {
    const uint32_t channels = src->mNumberChannels ? src->mNumberChannels : 1;
    const float *in = (const float *)src->mData;
    for (uint32_t i = 0; i < n; ++i) dst[offset + i] = in[i * channels];
}

OSStatus lucid_recorder_ioproc(AudioObjectID device, const AudioTimeStamp *now,
                               const AudioBufferList *input, const AudioTimeStamp *inputTime,
                               AudioBufferList *output, const AudioTimeStamp *outputTime,
                               void *clientData) {
    (void)device; (void)now; (void)inputTime; (void)output; (void)outputTime;
    LucidRecorder *r = (LucidRecorder *)clientData;
    if (!input || r->firstBuffer >= input->mNumberBuffers || r->secondBuffer >= input->mNumberBuffers) {
        return noErr;
    }
    const uint32_t done = atomic_load_explicit(&r->frames, memory_order_relaxed);
    if (done >= r->capacity) return noErr;

    const AudioBuffer *a = &input->mBuffers[r->firstBuffer];
    const AudioBuffer *b = &input->mBuffers[r->secondBuffer];
    const uint32_t fa = a->mDataByteSize / (sizeof(float) * (a->mNumberChannels ? a->mNumberChannels : 1));
    const uint32_t fb = b->mDataByteSize / (sizeof(float) * (b->mNumberChannels ? b->mNumberChannels : 1));
    uint32_t n = fa < fb ? fa : fb;
    if (n > r->capacity - done) n = r->capacity - done;

    copy_channel0(a, r->first, done, n);
    copy_channel0(b, r->second, done, n);
    atomic_store_explicit(&r->frames, done + n, memory_order_release);
    return noErr;
}

OSStatus lucid_recorder_create_ioproc(AudioObjectID device, LucidRecorder *recorder,
                                      AudioDeviceIOProcID *outProc) {
    return AudioDeviceCreateIOProcID(device, lucid_recorder_ioproc, recorder, outProc);
}
```

**Step 4: Run it to verify it passes (driver from Task 5 must be installed)**

Run: `make test-integration`
Expected: it prints `Feed → Microphone loopback delay: N samples (…)` and passes with 0
mismatches, meaning the loopback is bit-exact. Run `swift test --package-path app`: it reports
`Test run with 18 tests in 7 suites passed` (the integration suite is skipped).

If it fails with `feed device not found`: hidden devices can't be looked up by UID on this
macOS version. Set `feed->SetIsHidden(false)` in `Driver.cpp` (and keep `CanBeDefault=false`),
rebuild, reinstall, and log the finding.

**Step 5: Commit**

```bash
git add app/
git commit -m "test(app): bit-exact feed-to-microphone loopback integration test

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 12: `lucidmic-latency` CLI

**Files:**
- Modify: `app/Package.swift` (adds the latency executable; the app target comes in Task 13)
- Create: `app/Sources/LucidMicLatency/main.swift`

**Step 1: Implement**

`app/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LucidMic",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lucidmic-latency", targets: ["LucidMicLatency"])
    ],
    targets: [
        .target(name: "LucidAudioC", linkerSettings: [.linkedFramework("CoreAudio")]),
        .target(
            name: "LucidAudio",
            dependencies: ["LucidAudioC"],
            linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("AVFoundation")]
        ),
        .executableTarget(name: "LucidMicLatency", dependencies: ["LucidAudio", "LucidAudioC"]),
        .testTarget(name: "LucidAudioTests", dependencies: ["LucidAudio", "LucidAudioC"]),
    ]
)
```

`app/Sources/LucidMicLatency/main.swift`:

```swift
// lucidmic-latency: measures how much delay LucidMic adds on this Mac.
// Records the physical mic and "LucidMic Microphone" side by side while you
// clap or talk, then finds the lag between them by cross-correlation.
import CoreAudio
import Foundation
import LucidAudio
import LucidAudioC

let seconds = 5.0
let sampleRate = 48_000.0

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard await PassthroughPipeline.requestMicrophoneAccess() else { fail("Microphone access denied.") }
guard let lucid = AudioSystem.device(uid: LucidDeviceUID.microphone) else { fail("LucidMic driver not installed.") }
let inputs = DeviceSelection.selectableInputs((try? AudioSystem.devices()) ?? [])
let defaultUID = AudioSystem.defaultDevice(input: true).flatMap { try? AudioSystem.device(id: $0).uid }
guard
    let mic = DeviceSelection.choose(
        inputs, savedUID: CommandLine.arguments.dropFirst().first, systemDefaultUID: defaultUID)
else { fail("No physical microphone found.") }

print("Physical mic: \(mic.name)\nMake sure LucidMic is ON, then clap or talk for \(Int(seconds)) s…")

guard let aggregate = try? AggregateDevice.createLatencyProbe(micUID: mic.uid, lucidMicUID: lucid.uid) else {
    fail("Could not create the probe aggregate.")
}
defer { AggregateDevice.destroy(aggregate) }

let capacity = UInt32(seconds * sampleRate)
guard let recorder = lucid_recorder_create(capacity, 0, UInt32(mic.inputStreams.count)) else { fail("Out of memory.") }
defer { lucid_recorder_destroy(recorder) }

var proc: AudioDeviceIOProcID?
guard lucid_recorder_create_ioproc(aggregate, recorder, &proc) == noErr,
    AudioDeviceStart(aggregate, proc) == noErr
else { fail("Could not start recording.") }

while lucid_recorder_frames(recorder) < capacity { try await Task.sleep(for: .milliseconds(100)) }
AudioDeviceStop(aggregate, proc)
AudioDeviceDestroyIOProcID(aggregate, proc!)

let frames = Int(lucid_recorder_frames(recorder))
let reference = Array(UnsafeBufferPointer(start: lucid_recorder_first(recorder), count: frames))
let delayed = Array(UnsafeBufferPointer(start: lucid_recorder_second(recorder), count: frames))
guard let lag = DelayEstimator.estimateLag(reference: reference, delayed: delayed, maxLag: Int(0.1 * sampleRate)) else {
    fail("No signal on one of the inputs. Is LucidMic ON and is the mic unmuted?")
}
print(String(format: "LucidMic adds %.2f ms (%d samples @ 48 kHz)", Double(lag) / sampleRate * 1000, lag))
```

`app/Sources/LucidMicLatency/main.swift`:

```swift
// lucidmic-latency: measures how much delay LucidMic adds on this Mac.
// Records the physical mic and "LucidMic Microphone" side by side while you
// clap or talk, then finds the lag between them by cross-correlation.
import CoreAudio
import Foundation
import LucidAudio
import LucidAudioC

let seconds = 5.0
let sampleRate = 48_000.0

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard await PassthroughPipeline.requestMicrophoneAccess() else { fail("Microphone access denied.") }
guard let lucid = AudioSystem.device(uid: LucidDeviceUID.microphone) else { fail("LucidMic driver not installed.") }
let inputs = DeviceSelection.selectableInputs((try? AudioSystem.devices()) ?? [])
let defaultUID = AudioSystem.defaultDevice(input: true).flatMap { try? AudioSystem.device(id: $0).uid }
guard
    let mic = DeviceSelection.choose(
        inputs, savedUID: CommandLine.arguments.dropFirst().first, systemDefaultUID: defaultUID)
else { fail("No physical microphone found.") }

print("Physical mic: \(mic.name)\nMake sure LucidMic is ON, then clap or talk for \(Int(seconds)) s…")

guard let aggregate = try? AggregateDevice.createLatencyProbe(micUID: mic.uid, lucidMicUID: lucid.uid) else {
    fail("Could not create the probe aggregate.")
}
defer { AggregateDevice.destroy(aggregate) }

let capacity = UInt32(seconds * sampleRate)
guard let recorder = lucid_recorder_create(capacity, 0, UInt32(mic.inputStreams.count)) else { fail("Out of memory.") }
defer { lucid_recorder_destroy(recorder) }

var proc: AudioDeviceIOProcID?
guard lucid_recorder_create_ioproc(aggregate, recorder, &proc) == noErr,
    AudioDeviceStart(aggregate, proc) == noErr
else { fail("Could not start recording.") }

while lucid_recorder_frames(recorder) < capacity { try await Task.sleep(for: .milliseconds(100)) }
AudioDeviceStop(aggregate, proc)
AudioDeviceDestroyIOProcID(aggregate, proc!)

let frames = Int(lucid_recorder_frames(recorder))
let reference = Array(UnsafeBufferPointer(start: lucid_recorder_first(recorder), count: frames))
let delayed = Array(UnsafeBufferPointer(start: lucid_recorder_second(recorder), count: frames))
guard let lag = DelayEstimator.estimateLag(reference: reference, delayed: delayed, maxLag: Int(0.1 * sampleRate)) else {
    fail("No signal on one of the inputs. Is LucidMic ON and is the mic unmuted?")
}
print(String(format: "LucidMic adds %.2f ms (%d samples @ 48 kHz)", Double(lag) / sampleRate * 1000, lag))
```

**Step 2: Build**

Run: `swift build --package-path app -c release --product lucidmic-latency`
Expected: `Build complete!`. It runs for real in Task 15.

**Step 3: Commit**

```bash
git add app/
git commit -m "feat(app): lucidmic-latency measurement tool

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 13: Menu-bar app + app bundle

**Files:**
- Modify: `app/Package.swift` (final version below)
- Create: `app/Sources/LucidMicApp/AppModel.swift`, `app/Sources/LucidMicApp/LucidMicApp.swift`
- Create: `app/Resources/Info.plist`, `scripts/bundle-app.sh`, `Installer/uninstall.sh` (bundled into the app)

**Step 1: Implement**

`app/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LucidMic",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LucidMic", targets: ["LucidMicApp"]),
        .executable(name: "lucidmic-latency", targets: ["LucidMicLatency"]),
    ],
    targets: [
        .target(
            name: "LucidAudioC",
            linkerSettings: [.linkedFramework("CoreAudio")]
        ),
        .target(
            name: "LucidAudio",
            dependencies: ["LucidAudioC"],
            linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("AVFoundation")]
        ),
        .executableTarget(name: "LucidMicApp", dependencies: ["LucidAudio"]),
        .executableTarget(name: "LucidMicLatency", dependencies: ["LucidAudio", "LucidAudioC"]),
        .testTarget(name: "LucidAudioTests", dependencies: ["LucidAudio", "LucidAudioC"]),
    ]
)
```

`app/Sources/LucidMicApp/AppModel.swift`:

```swift
import AppKit
import Foundation
import LucidAudio
import Observation

@MainActor
@Observable
final class AppModel {
    var inputs: [AudioDevice] = []
    var outputs: [AudioDevice] = []
    var selectedInputUID: String? { didSet { save(selectedInputUID, "inputUID"); restartIfOn() } }
    var selectedMonitorUID: String? { didSet { save(selectedMonitorUID, "monitorUID"); restartIfOn() } }
    var isOn = false
    var monitorEnabled = false { didSet { pipeline.setMonitor(monitorEnabled) } }
    var meters = Meters()
    var latencyMs: Double = 0
    var errorMessage: String?
    var driverInstalled = false

    private let pipeline = PassthroughPipeline()
    private let defaults = UserDefaults.standard
    private var meterTask: Task<Void, Never>?

    init() {
        selectedInputUID = defaults.string(forKey: "inputUID")
        selectedMonitorUID = defaults.string(forKey: "monitorUID")
        refreshDevices()
    }

    func refreshDevices() {
        let all = (try? AudioSystem.devices()) ?? []
        inputs = DeviceSelection.selectableInputs(all)
        outputs = DeviceSelection.selectableOutputs(all)
        driverInstalled = AudioSystem.device(uid: LucidDeviceUID.feed) != nil
    }

    func setOn(_ on: Bool) async {
        if on {
            guard await PassthroughPipeline.requestMicrophoneAccess() else {
                errorMessage = "Allow microphone access in System Settings › Privacy & Security › Microphone."
                return
            }
            start()
        } else {
            stop()
        }
    }

    private func start() {
        refreshDevices()
        let defaultIn = AudioSystem.defaultDevice(input: true).flatMap { try? AudioSystem.device(id: $0).uid }
        let defaultOut = AudioSystem.defaultDevice(input: false).flatMap { try? AudioSystem.device(id: $0).uid }
        guard let mic = DeviceSelection.choose(inputs, savedUID: selectedInputUID, systemDefaultUID: defaultIn) else {
            errorMessage = "No microphone found."
            return
        }
        let monitor = DeviceSelection.choose(outputs, savedUID: selectedMonitorUID, systemDefaultUID: defaultOut)
        do {
            try pipeline.start(mic: mic, monitor: monitor, monitorEnabled: monitorEnabled)
            isOn = true
            errorMessage = nil
            latencyMs = pipeline.estimatedAddedLatencyMs
            startMeters()
        } catch {
            isOn = false
            errorMessage = String(describing: error)
        }
    }

    private func stop() {
        pipeline.stop()
        meterTask?.cancel()
        meterTask = nil
        isOn = false
        meters = Meters()
    }

    private func restartIfOn() {
        if isOn { start() }
    }

    private func startMeters() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                self.meters = self.pipeline.takeMeters()
            }
        }
    }

    func uninstall() {
        guard let script = Bundle.main.url(forResource: "uninstall", withExtension: "sh") else {
            errorMessage = "uninstall.sh missing from the app bundle."
            return
        }
        stop()
        let source = "do shell script \"/bin/sh '\(script.path)'\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            errorMessage = "Uninstall failed: \(error)"
        } else {
            NSApp.terminate(nil)
        }
    }

    private func save(_ value: String?, _ key: String) { defaults.set(value, forKey: key) }
}
```

`app/Sources/LucidMicApp/LucidMicApp.swift`:

```swift
import LucidAudio
import SwiftUI

@main
struct LucidMicApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Image(systemName: model.isOn ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("LucidMic", isOn: Binding(get: { model.isOn }, set: { on in Task { await model.setOn(on) } }))
                .toggleStyle(.switch)
                .font(.headline)
                .disabled(!model.driverInstalled)

            if !model.driverInstalled {
                Text("Driver not installed. Reinstall LucidMic.pkg.").foregroundStyle(.red)
            }

            Picker("Microphone", selection: $model.selectedInputUID) {
                ForEach(model.inputs) { Text($0.name).tag(Optional($0.uid)) }
            }
            Toggle("Listen to myself", isOn: $model.monitorEnabled)
            Picker("Headphones", selection: $model.selectedMonitorUID) {
                ForEach(model.outputs) { Text($0.name).tag(Optional($0.uid)) }
            }
            .disabled(!model.monitorEnabled)

            LevelRow(label: "In", peak: model.meters.inputPeak)
            LevelRow(label: "Out", peak: model.meters.outputPeak)
            HStack {
                Text(String(format: "Latency ≈ %.1f ms", model.latencyMs))
                Spacer()
                Text(String(format: "Load %.0f%%", model.meters.load * 100))
                Text("Overloads \(model.meters.overloads)")
            }
            .font(.caption.monospacedDigit())

            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("In your call app, choose “LucidMic Microphone”.").font(.caption).foregroundStyle(.secondary)

            Divider()
            HStack {
                Button("Uninstall…") { model.uninstall() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear { model.refreshDevices() }
    }
}

struct LevelRow: View {
    let label: String
    let peak: Float

    var body: some View {
        HStack {
            Text(label).frame(width: 28, alignment: .leading).font(.caption)
            ProgressView(value: Double(min(peak, 1)))
        }
    }
}
```

`app/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>LucidMic</string>
	<key>CFBundleIdentifier</key>
	<string>com.sultanovazamat.lucidmic</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>LucidMic</string>
	<key>CFBundleDisplayName</key>
	<string>LucidMic</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>__VERSION__</string>
	<key>CFBundleVersion</key>
	<string>__VERSION__</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSMicrophoneUsageDescription</key>
	<string>LucidMic processes your microphone to make your voice clearer in any app.</string>
</dict>
</plist>
```

`scripts/bundle-app.sh`:

```sh
#!/bin/sh
# Builds LucidMic.app from the SwiftPM executable. Usage: scripts/bundle-app.sh <version> <out-dir>
set -eu
VERSION="$1"
OUT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$OUT/LucidMic.app"

swift build --package-path "$ROOT/app" -c release --product LucidMic
BIN="$(swift build --package-path "$ROOT/app" -c release --show-bin-path)/LucidMic"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LucidMic"
sed "s/__VERSION__/$VERSION/g" "$ROOT/app/Resources/Info.plist" > "$APP/Contents/Info.plist"
cp "$ROOT/Installer/uninstall.sh" "$APP/Contents/Resources/uninstall.sh"
codesign --force --sign - "$APP"
echo "Built $APP"
```

`Installer/uninstall.sh`:

```sh
#!/bin/sh
# Removes LucidMic completely. Run as root (the app runs it via an admin prompt).
set -eu
rm -rf "/Applications/LucidMic.app"
rm -rf "/Library/Audio/Plug-Ins/HAL/LucidMic.driver"
pkgutil --forget com.sultanovazamat.lucidmic >/dev/null 2>&1 || true
killall -9 coreaudiod >/dev/null 2>&1 || true
echo "LucidMic uninstalled."
```

Run `chmod +x scripts/bundle-app.sh Installer/uninstall.sh`.

**Step 2: Build the bundle**

Run: `make app && plutil -lint build/LucidMic.app/Contents/Info.plist && codesign -dv build/LucidMic.app 2>&1 | grep Signature`
Expected: `Built build/LucidMic.app`, `OK`, `Signature=adhoc`.

**Step 3: Manual end-to-end check (driver installed from Task 5)**

1. `open build/LucidMic.app`. A waveform icon appears in the menu bar.
2. Turn LucidMic on and allow microphone access.
3. Open Voice Memos or QuickTime (New Audio Recording), pick **LucidMic Microphone**, record 10 s of
   speech, and play it back. You should hear your voice unchanged.
4. Turn on **Listen to myself** with wired headphones. You should hear yourself with no noticeable delay.
5. The In/Out meters move, **Overloads** stays at 0, and **Latency ≈** shows a few ms.

Note: an ad-hoc signature changes on every rebuild, so macOS may ask for microphone permission again.

**Step 4: Commit**

```bash
git add app/ scripts/ Installer/uninstall.sh
git commit -m "feat(app): LucidMic menu-bar app and bundle script

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 14: Installer package

**Files:**
- Create: `Installer/build-pkg.sh`, `Installer/scripts/postinstall`

**Step 1: Implement**

`Installer/build-pkg.sh`:

```sh
#!/bin/sh
# Packages LucidMic.app + LucidMic.driver into one installer.
# Usage: Installer/build-pkg.sh <version> <app> <driver> <out.pkg>
set -eu
VERSION="$1"
APP="$2"
DRIVER="$3"
OUT_PKG="$4"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/root/Applications" "$WORK/root/Library/Audio/Plug-Ins/HAL"
cp -R "$APP" "$WORK/root/Applications/"
cp -R "$DRIVER" "$WORK/root/Library/Audio/Plug-Ins/HAL/"
xattr -cr "$WORK/root"  # keep AppleDouble ._ files out of the payload

# Never let Installer "relocate" the app to an older copy elsewhere on disk.
pkgbuild --analyze --root "$WORK/root" "$WORK/components.plist"
COUNT=$(/usr/libexec/PlistBuddy -c "Print" "$WORK/components.plist" | grep -c "RootRelativeBundlePath")
i=0
while [ "$i" -lt "$COUNT" ]; do
    plutil -replace "$i.BundleIsRelocatable" -bool NO "$WORK/components.plist"
    i=$((i + 1))
done

mkdir -p "$(dirname "$OUT_PKG")"
pkgbuild \
    --root "$WORK/root" \
    --component-plist "$WORK/components.plist" \
    --scripts "$ROOT/Installer/scripts" \
    --identifier com.sultanovazamat.lucidmic \
    --version "$VERSION" \
    --install-location / \
    "$OUT_PKG"
echo "Built $OUT_PKG"
```

`Installer/scripts/postinstall`:

```sh
#!/bin/sh
# Make coreaudiod load the freshly installed driver (launchd restarts it).
chown -R root:wheel "/Library/Audio/Plug-Ins/HAL/LucidMic.driver"
killall -9 coreaudiod >/dev/null 2>&1 || true
exit 0
```

Run `chmod +x Installer/build-pkg.sh Installer/scripts/postinstall`.

**Step 2: Build and inspect**

Run: `make pkg && pkgutil --payload-files dist/LucidMic-0.1.0.pkg | grep -E "LucidMic(\.app|\.driver)$|uninstall.sh"`
Expected: the `.app`, the `.driver`, and `Contents/Resources/uninstall.sh` are listed. Then check
`pkgutil --payload-files dist/LucidMic-0.1.0.pkg | grep -c "\._"` prints `0`.

**Step 3: Install via the pkg (USER RUNS)**

```bash
sudo rm -rf /Library/Audio/Plug-Ins/HAL/LucidMic.driver   # remove the Task 5 manual copy
make install-dev
```

Expected: `installer: The install was successful.`, `/Applications/LucidMic.app` exists, and
LucidMic Microphone appears without a reboot.

**Step 4: Commit**

```bash
git add Installer/
git commit -m "feat(installer): LucidMic.pkg with driver, app, and postinstall

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 15: Phase-1 acceptance run

**Step 1: Quality gates**

Run: `make check`
Expected: lint prints nothing, and it reports `100% tests passed, 0 tests failed out of 2` and
`Test run with 18 tests in 7 suites passed` (the integration suite is skipped).

**Step 2: Loopback + latency (driver and app installed)**

1. `make test-integration`: passes, 0 mismatches. Record the delay.
2. Launch LucidMic from /Applications and turn it on.
3. `make latency` while clapping near the mic. Record the printed ms. **Target: ≤ 5 ms.** If it's
   higher, look at the buffer size first (the app requests 64 frames; some devices clamp it).

**Step 3: Apps**

Select **LucidMic Microphone** in Zoom, Google Meet (Chrome and Safari), and Voice Memos. Each
shows the device and carries your voice.

**Step 4: Soak**

Leave a 30-minute Zoom test call (or a Voice Memos recording) running. **Overloads** must stay at 0.

**Step 5: Second Mac or VM (the #1 risk from the design)**

Copy `dist/LucidMic-0.1.0.pkg` to another Apple-silicon Mac through a download (AirDrop or a
GitHub draft release), so it gets the quarantine flag. Install it with **Open Anyway**. Confirm
that LucidMic Microphone appears and passes audio. If coreaudiod refuses to load the ad-hoc
driver there, stop and escalate to the user (the fallback is Developer ID + notarization).

**Step 6: Uninstall**

Use **Uninstall…** in the menu. Confirm that `/Applications/LucidMic.app` and the driver are
gone and the device disappears.

**Step 7: Record the results**

Append a `## Phase 1 results` section to `docs/plans/2026-09-30-lucidmic-design.md` with the
loopback delay, the measured latency, the apps tested, the soak result, and the second-Mac
result. Then commit:

```bash
git add docs/plans/2026-09-30-lucidmic-design.md
git commit -m "docs: phase 1 acceptance results

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 16: First GitHub release (OUTWARD-FACING: ask the user first)

Only after Task 15 passes **and the user explicitly approves**: creating a repo and publishing a
release is public-facing and hard to undo.

1. Ask the user: repo name (`lucidmic`?), and public or private (coworkers need read access).
2. `gh repo create sultanovazamat/<name> --<visibility> --source . --push`
3. `gh release create v0.1.0 dist/LucidMic-0.1.0.pkg --title "LucidMic 0.1.0" --notes "Pass-through skeleton. Install steps: see README."`
4. Send coworkers the release link. The README has the Gatekeeper **Open Anyway** steps.
