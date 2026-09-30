# Contributing to LucidMic

Start with the build instructions in the README. Run `scripts/check.sh` before
opening a pull request. Keep changes focused and add a regression test for changes
to audio processing. Avoid allocations, locks, logging, and model inference in the
Core Audio callback.

For bug reports, include your macOS version, Mac model, microphone, call app,
LucidMic version, and steps to reproduce. Do not attach private call recordings.
If an audio sample helps, make a short recording specifically for the report.

## Project layout

- `Sources/LucidMic`: native menu, SwiftUI Settings, device discovery, and audio routing.
- `Sources/LucidEngine`: C audio engine and inference worker.
- `Sources/LucidFileProcessing`: audio conversion and complete offline rendering.
- `Sources/lucidmic-file`: command-line entry point for file processing.
- `Tests/LucidEngineTests`: engine behavior, channel selection, recovery, and live/offline parity.
- `Tests/LucidEngineTestSupport`: deterministic worker scheduling and queue faults, linked only into tests.
- `Tests/LucidFileTests`: downmix, resampling, duration, and end-of-file regressions.
- `Tests/LucidMicUITests`: device configuration, routing lifecycle, menu, and keyboard tests.
- `scripts/tests`: installer rollback and packaging-tool regressions using disposable files.
- `Resources`: logo, installer art, app metadata, and dependency licenses.
- `scripts`: pinned dependencies, artwork, checks, driver build, and DMG packaging.
- `docs/plans`: development plans and review records; the README describes the current checkout.

Use `xcrun swift-format format --in-place --recursive Sources Tests Package.swift scripts/render-menu.swift`
for Swift and `uv run --no-project --with-requirements requirements-dev.txt ruff format scripts`
for Python. Shell scripts are checked by ShellCheck.

Live routing requires 48 kHz Float32 audio and callback sizes of 1–512 frames.
The engine's declared delay is 3,456 frames (72 ms). Regression tests measure
that delay across buffer sizes and after recovery; the file tool removes it
from saved output. Keep model work and recovery resets on the worker thread.

## Releases

The current local candidate is **1.0.2**. The default build and CI packaging use
that version; published download links remain on 1.0.1 until a new release is published.

The drag-to-Applications installer is created with
[dmgbuild](https://github.com/dmgbuild/dmgbuild), pinned in `requirements-dev.txt`.
It is a build tool and is not bundled in the installed app.

Update the changelog and version defaults, then run the full checks and
`scripts/build.sh <version>`. Verify the app from the mounted DMG on macOS, not
only the development executable. The **Prepare release** GitHub Actions workflow
builds the same artifacts and creates a draft release for review.

Before sharing the candidate, exercise the mounted app on real hardware: select
a microphone and channel, switch cleaning off and change inputs, disconnect and
reconnect the microphone, retry routing, and verify default-input restoration on
quit. Automated audio tests use synthetic buffers and do not access a microphone.

Attach the DMG, `SHA256SUMS.txt`, `BlackHole-0.7.1-source.tar.gz`, and the matching
`LucidMic-<version>-runtime-source.tar.gz`.
Keep the release tag on the exact source used for the build. Never commit signing
credentials or notarization secrets. Contributions are provided under GPL-3.0.
