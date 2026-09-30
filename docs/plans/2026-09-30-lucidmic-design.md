# LucidMic — Design

- **Date:** 2026-09-30
- **Status:** Approved during brainstorming
- **Context:** Pet project for a quarterly competition between coworkers. Success = coworkers install it, use it daily, and the demo convinces them. Not a commercial product.

## 1. Goal

An installable macOS app that makes the user's voice **clearer** in any app (Zoom, Meet, Teams, Slack, Voice Memos, Notes) by running a neural speech-enhancement model live with minimum latency — and that lets us compare several state-of-the-art models on the same code path to pick the best one.

Framing: LucidMic makes the voice clearer and more intelligible; it is not a "silence" product.

### Non-goals (v1)

Video, accent conversion, translation, processing incoming (far-end) audio, Mac App Store distribution, Intel Macs, notarization (optional later upgrade).

## 2. User experience

1. Download `LucidMic-<version>.pkg` from GitHub Releases. First open is blocked by Gatekeeper (ad-hoc signed) → System Settings › Privacy & Security › **Open Anyway**. One admin prompt installs the app and the driver.
2. Menu-bar icon: **On/Off**, **model picker**, **Listen to myself** (headphone monitor), input device picker, live meters (input/output level, CPU %, latency ms).
3. In any call app, select **"LucidMic Microphone"** as the microphone.
4. **Lab window:** record or import clips, render them through every model, blind A/B listening with a preference tally.

## 3. Architecture

```
LucidMic.pkg ──► /Applications/LucidMic.app  +  /Library/Audio/Plug-Ins/HAL/LucidMic.driver

Physical mic ─┐  private aggregate device (mic = clock master, drift compensation on)
              ├─► IOProc ─► SPSC ring ─► inference thread (joined to the device's os_workgroup)
LucidMic Feed ◄┘                               │  Engine: Bypass | RNNoise | DFN3 | GTCRN | UL-UNAS
 (hidden, out)                                 ▼
      │                            resample + reblock + crossfade
      ▼
"LucidMic Microphone" (visible, in) ──► Zoom / Meet / Voice Memos     (optional monitor → headphones)
```

### 3.1 Driver — `LucidMic.driver` (AudioServerPlugIn, C++17, libASPL, MIT)

- Two devices inside one plug-in, sharing one lock-free ring buffer inside `coreaudiod`:
  - **LucidMic Microphone** — visible, input only, mono, 48 kHz.
  - **LucidMic Feed** — hidden (`kAudioDevicePropertyIsHidden = 1`), output only; only LucidMic.app writes to it.
- Both devices take their timestamps from the same host clock at the same nominal rate, so the feed and the microphone never drift against each other.
- Ring buffer ≈ 100 ms. When the feed is idle (the app is not running), the microphone outputs silence.
- Written from scratch on libASPL rather than BlackHole, because BlackHole requires the embedding app to be GPL-3.0.

### 3.2 App — `LucidMic.app` (Swift 6, SwiftUI `MenuBarExtra`, macOS 14+, arm64)

- **AudioCore** (Swift package; real-time-critical parts in C):
  - Device discovery and change handling (hot-plug, default-device changes).
  - A private aggregate device made of the physical mic (clock master), LucidMic Feed and, optionally, the monitor output, with drift compensation on the non-master subdevices. Fallback if this proves unreliable: separate IOProcs with an adaptive resampler.
  - IOProc: only copies to and from lock-free SPSC rings — no allocation, locks, or Swift/ObjC runtime calls.
  - Inference thread: joined to the device's `os_workgroup`; drives the active engine or engines hop by hop.
  - Reblocker (arbitrary IO buffer size ↔ the engine's hop), resampler (48 ↔ 16 kHz), 20 ms crossfade on engine switch, level/CPU/latency meters.
- **Engines** — the common contract:

  ```swift
  protocol Engine {
      var id: String { get }
      var sampleRate: Double { get }   // native rate
      var hopSize: Int { get }         // samples per process() call at the native rate
      var latencySamples: Int { get }  // algorithmic latency at the native rate
      func process(_ input: UnsafePointer<Float>, _ output: UnsafeMutablePointer<Float>)  // hopSize samples
      func reset()
  }
  ```

  Engines preallocate everything in `init`. In **Compare mode** all enabled engines run in parallel, so switching is instant and every engine's recurrent state is warm.

### 3.3 `lucidmic-render` CLI

Uses the same AudioCore and Engines code as the app to render a folder of WAV files through every engine. Whatever is measured is exactly what ships.

### 3.4 `bench/` (Python, uv)

`score.py` computes DNSMOS P.835 (SIG/BAK/OVRL) and P.808, PESQ, STOI and SI-SDR, plus the latency and CPU load reported by the renderer. `report.py` produces a table and a quality-vs-latency Pareto chart.

## 4. Candidate engines

| Engine | Integration | Native rate / latency | License |
|---|---|---|---|
| Bypass | — | 48 kHz / 0 | — |
| RNNoise 0.2 | C library, vendored | 48 kHz, 480-sample frames, ~10 ms look-ahead | BSD-3 |
| DeepFilterNet3 | Rust `libDF` C API (`df_create`, `df_process_frame`) → static lib | 48 kHz, 40 ms | MIT / Apache-2.0 |
| GTCRN (DNS3 checkpoint) | ONNX Runtime, streaming model | 16 kHz, 512-sample window / 256-sample hop (32 ms) | MIT |
| UL-UNAS | ONNX Runtime, streaming model | TBD (measured in phase 3) | MIT |
| Apple Voice Isolation | voice-processing input | live only | system |
| LucidMic-8 (optional) | GTCRN retrained with asymmetric windows | 16 kHz, 8 ms | ours |

## 5. Bake-off methodology

- **Datasets:**
  1. The user's own MacBook-mic recordings (blender, keyboard, café, fan, dishes, street) — primary, because these are the demo conditions.
  2. The DNS Challenge blind-test real recordings (DNSMOS only).
  3. The VoiceBank-DEMAND test set (PESQ/STOI/SI-SDR).
- **Contamination:** use DNS3-trained checkpoints and report results on VoiceBank-DEMAND separately, because some checkpoints were trained on it.
- **Selection rule (fixed before measuring):** among the engines on the quality-vs-latency Pareto front, pick the winner of blind A/B preference on the user's recordings; tie-break on lower latency.

## 6. Latency budget

| Stage | Target |
|---|---|
| IO buffers (64 frames @ 48 kHz, in + out) | ~2.7 ms |
| Ring hand-off to the inference thread | ≤ 1 hop |
| Resampler (16 kHz engines) | ≤ 1 ms |
| Engine algorithmic latency | per engine (0–40 ms) |
| **Pass-through total added latency** | **≤ 5 ms** |

## 7. Distribution

- GitHub Releases, repo owned by `sultanovazamat`.
- An ad-hoc-signed `.pkg`: the app goes to `/Applications`, the driver to `/Library/Audio/Plug-Ins/HAL`; `postinstall` restarts `coreaudiod`.
- `uninstall.sh`, and an **Uninstall** item in the app.
- Later upgrade: Developer ID + notarization, then a GitHub Actions release workflow.
- Dependency licenses are all permissive. DNSMOS models are used only in the `bench/` tooling and are not shipped.

## 8. Phases

1. **Installable skeleton:** driver, app with pass-through, bypass, monitor and meters, pkg, uninstall script. Verify the driver loads on a second Mac or VM.
2. **Engine layer**, RNNoise 0.2, DeepFilterNet3, hot-swap and Compare mode.
3. **ONNX Runtime**, GTCRN and UL-UNAS.
4. **Bake-off:** `lucidmic-render`, `bench/`, the Lab window with blind A/B; choose the default engine.
5. **Optional:** train LucidMic-8 and enter it in the same bake-off.

## 9. Acceptance criteria

1. Installing on a clean second Mac needs one admin prompt, and "LucidMic Microphone" appears in Zoom, Meet and Voice Memos. Uninstalling leaves nothing behind.
2. Pass-through adds ≤ 5 ms of latency (measured).
3. A 30-minute run on every engine has zero IO overloads or dropouts.
4. Each engine's measured delay equals its reported `latencySamples` ± 1 sample.
5. The app's engine output matches the reference implementation (difference ≥ 40 dB below the signal).
6. Switching engines is click-free.
7. A bake-off report covers every engine on all three datasets.

## 10. Testing

- **Unit (Swift Testing):**
  - SPSC ring buffer.
  - Reblocker and resampler: IO buffer sizes of 32, 64, 127 and 512 all give identical output.
  - Crossfader.
- **Engine contract:**
  - Impulse test: measured delay == `latencySamples`.
  - Silence in → near silence out.
  - No NaN or Inf.
  - `reset()` is deterministic.
- **Parity:** app engine output vs the reference Python/Rust implementation on the same file.
- **Driver integration:** a known signal written to the feed is read back from the microphone — bit-exact at the expected delay.
- **Real-time:** per-hop processing-time histogram with p99 < 50% of the hop duration; a 30-minute soak with an overload counter.
- **Installer:** install and uninstall on a second Mac or a macOS VM.
- **Quality gates:** `swift-format lint`, `ruff format --check`, `ruff check`, `xcodebuild test`, `pytest`.

## 11. Risks

| Risk | Mitigation |
|---|---|
| An ad-hoc-signed driver may not load on other Macs | Test first, in phase 1. Fallback: Developer ID + notarization |
| Aggregate-device drift compensation misbehaves with a virtual subdevice | Separate IOProcs + an adaptive resampler |
| ONNX Runtime or tract allocates during inference | Run engines only on the inference thread, never in the IOProc |
| Bluetooth headphones add ~100+ ms to the monitor path | Recommend wired headphones for the "hear yourself" demo |
| The call app's own noise suppression double-processes the audio | Document per-app settings; turn it off for the demo |
| A physical mic without 48 kHz support | Aggregate at 48 kHz; resample if needed |
