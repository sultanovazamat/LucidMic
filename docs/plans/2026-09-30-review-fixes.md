# Code review fixes implementation plan

Status: implemented and independently reviewed on `fix/review-hardening`; local 1.0.2 artifacts built and verified. Authorized by the user's “fix all” response to the comprehensive review.

**Classification:** Issues/bugs, plus the review's scoped cleanup. No new product architecture.

**Goal:** Correct all actionable review findings before sharing LucidMic.

**Architecture:** Preserve the C callback/inference-worker boundary, native menu, and SwiftUI Settings. Use explicit configuration validation, bounded audio recovery, device-change observation, and small injectable system boundaries for deterministic lifecycle tests.

**Tech stack:** Swift 6, Core Audio, C atomics, Swift Testing, shell, Python standard-library tests.

## 1. Audio callback and recovery

- Broken: permitted null stream buffers crash; worker stalls leave permanent extra latency; callback sizes beyond the assumed size underrun; channel zero is hard-coded.
- Cause: unchecked pointers, no discontinuity recovery, assumed hardware configuration and channel layout.
- Files: `Sources/LucidEngine/LucidEngine.c`, `Sources/LucidEngine/include/LucidEngine.h`, `Tests/LucidEngineTests/EngineTests.swift` and focused test support as needed.
- Fix: validate buffers, define bounded recovery without violating ring ownership, expose input-channel selection, and correct the latency comment.
- Regression: null input/output, selected channel, missing selected channel, stall/overrun recovery, measured latency, live callback-size behavior.
- Acceptance: no callback allocation/model calls; no crash for disabled streams; resumed processing returns to the declared delay. Hardware settings outside the supported callback contract are rejected before routing starts.

**Completed and reviewed:** Null and absent buffers produce safe silence; selected channels are mapped explicitly. Queue discontinuities use a four-state callback/worker handshake so each queue retains its single consumer and the worker alone resets model history. The handoff reserve is 1,536 frames; with the model's 1,920-frame delay the measured total is 3,456 frames (72 ms). This covers supported callback sizes through 512 frames, including 511-frame callbacks that exposed the previous reserve's shortfall.

**Evidence:** Live regression tests cover eight callback sizes, four stalled-worker sizes, input/output queue saturation, missing channels/buffers, disabled-stream reactivation, and denoiser-history reset. Existing quality, throughput, and offline/live equivalence checks pass. Strict Clang diagnostics and static analysis pass. A disposable concurrent ThreadSanitizer stress probe reported no data race and recovered to the declared delay after induced underruns. Independent engine review found no additional material issue.

## 2. Device configuration and lifecycle

- Broken: unplugging a microphone leaves false running state; rejected rate/default-input changes are ignored; other virtual microphones are selected as physical inputs.
- Files: `Sources/LucidMic/AudioSystem.swift`, `Router.swift`, `AppState.swift`, `SettingsView.swift`, `LucidMicApp.swift`, new lifecycle/configuration tests.
- Fix: checked setters and asynchronous readback, physical-device filtering, live device/configuration observation, transactional activation/default restoration, explicit input/channel selection.
- Regression: rejected and delayed property writes, default-write failure/rollback, device disappearance and retry, virtual source rejection, concurrent toggle guard, restoration failure.
- Acceptance: success means configured audio and verified default selection; lost devices yield safe, retryable state; users can select a non-first physical input channel.

**Completed and reviewed:** Property changes are checked and read back before activation. Valid existing buffers are preserved instead of forcing 512 frames. Active routes watch device availability, format, layout, running state, and audio-service restart; failures stop routing, restore a physical input where available, and offer retry. Other virtual/aggregate devices are excluded from automatic selection. Settings provides microphone/channel selection and observes automatic-source changes. Quit waits for pending default-input writes, but does not wait indefinitely for an unanswered microphone-permission prompt. Operation tokens prevent a pending input change from restarting audio after Quit.

**Evidence:** Nineteen configuration/lifecycle tests pass, including failures, delayed writes, rollback, restoration failure, permission denial, concurrent toggles, shutdown races, channel selection, bypass preservation, and observation notifications. The automatic-input notification regression failed before the final fix and passed afterward. Ten native-menu tests pass. Independent lifecycle review identified four additional edge cases and the Settings observation defect; all are addressed and re-reviewed. An offscreen layout probe verified normal and long-error Settings windows resize to their content without clipping. No hardware capture or system-default write was performed during these tests.

## 3. Offline file processing

- Broken: final delayed audio is discarded and stereo right-channel content is lost.
- Files: `Sources/lucidmic-file/main.swift`, reusable file-processing source/target if required, `Package.swift`, file-processing tests.
- Fix: deliberate downmix, drain pipeline and trim initial delay while preserving duration, sensible empty/short-file behavior.
- Regression: final-only signal, files shorter than pipeline latency, odd frame lengths, left/right stereo, exact output duration.
- Acceptance: complete duration and final content survive; both stereo channels contribute.

**Completed and reviewed:** File conversion deliberately averages all channels, reads every decoded block, resamples to mono 48 kHz, drains the engine's delayed output, and trims the initial delay. Empty and shorter-than-delay files are supported. The command-line entry point delegates to a small reusable file-processing target.

**Evidence:** Seven test functions cover 26 cases, including signal present only at EOF, odd frame counts, the final partial decoded block, either stereo channel, empty WAVs, and 16/44.1/96 kHz resampling. Actual command-line smoke conversion and independent source review pass. Whole-file memory use remains the existing CLI design; streaming very large files is a separate enhancement.

## 4. Installation and build tools

- Broken: driver is deleted before replacement copy succeeds; local source packaging assumes undeclared Python >=3.11.
- Files: `scripts/install-driver.sh`, `scripts/package-runtime-sources.py`, `scripts/check.sh`, shell/Python regression tests.
- Fix: validate source, stage and validate replacement, retain rollback until commit; use compatible hashing or explicitly select a supported Python.
- Regression: bad arguments/source, copy/validation/replacement failure preserve previous driver; test only disposable destinations and stub system operations.
- Acceptance: no destructive preflight failure; standard checks include regression suite; no live driver installation during automated verification.

**Completed and reviewed:** Driver installation validates the source, stages a complete copy beside the destination, verifies it after permissions are applied, and keeps the existing driver available for rollback until promotion succeeds. Source packaging uses chunked SHA-256 compatible with system Python 3.9. Cached runtime libraries are checked against their pinned hashes on every dependency-fetch invocation.

**Evidence:** Fifteen Python tests pass, covering installer preflight failures, partial copy, invalid signature/identity, permission failure, promotion rollback, success, symlink rejection, hashing compatibility, and corrupt-cache repair. Installer tests use disposable HAL directories and stub privilege/audio-service commands. A separate disposable installation probe verified the real signed driver bundle. No installed driver was changed and no audio service was restarted.

## 5. Cleanup, review, and release verification

- Evaluate denoiser-only runtime packaging and remove unnecessary bundled functionality only with a reproducible build and verified parity; preserve required dependency notices/source provenance.
- Correct misleading test names/comments and update README/CONTRIBUTING for actual channel and recovery behavior.
- Run targeted regression tests first, then `scripts/check.sh` (format, lint, build/typecheck, tests), C diagnostics, `git diff --check`, and independent review.
- Build a new local patch-version DMG and verify its signature, architecture, resources, minimum OS, and hashes. No publishing, system driver installation, or microphone capture is part of this task.
- Record remaining hardware-only verification limits explicitly. Review results and acceptance evidence belong below each issue group when completed.

**Completed cleanup:** Use the official pinned sherpa-onnx 1.13.8 no-TTS binary distribution, retaining the same ONNX Runtime and DPDFNet model. Six deterministic input/reset/flush scenarios produced bit-identical output before and after this change. The C API library shrank from 4,172,832 to 2,999,920 bytes (28.1%); two unused synthesis dependency archives and their notices were removed from current release packaging. No custom inference-runtime fork was introduced. Broader recognition components remain in the upstream distribution; removing them would require a separate custom build without a supported denoising-only preset.

**Verification:** The final `scripts/check.sh` run passed formatting, Swift formatting/lint, Ruff, ShellCheck, plist validation, compilation/typechecking, all 15 Python tests, and all 56 Swift test functions across six suites. `git diff --check` passed. Independent reviewers covered the engine, app lifecycle/Settings, file processing, installation, CI, and packaging. README, CONTRIBUTING, changelog, release notes, build defaults, and CI describe the local 1.0.2 candidate; published 1.0.1 download links remain accurate.

**Release artifact verification:** `scripts/build.sh 1.0.2` succeeded. The DMG passed `hdiutil verify`; its app was then mounted read-only and passed the same release validation, including arm64 architecture, resources, dependency notices, library paths, version, and strict deep signature checks. Mounted executable, dylibs, driver, and model hashes match the build byte for byte. Mach-O minimum OS versions are 14.0 for app/driver and 11.0 for both runtime libraries, compatible with the declared macOS 14 minimum. All three entries in `dist/SHA256SUMS.txt` pass. The DMG is 22,829,883 bytes. The image was detached after verification. No app was installed or published.

**Remaining verification:** Real microphone unplug/replug, audio-service restart, sleep/wake, live conferencing, and first installation on another Mac require hardware smoke testing. No known reviewed code blocker remains. The candidate retains the existing Apple-silicon/macOS-14 requirement and ad-hoc signing; notarization and publication are outside this task.
