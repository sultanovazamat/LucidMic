# Contributing to LucidMic

Start with the build instructions in the README. Run `scripts/check.sh` before
opening a pull request. Keep changes focused and add a regression test for changes
to audio processing. Avoid allocations, locks, logging, and model inference in the
Core Audio callback.

For bug reports, include your macOS version, Mac model, microphone, call app,
LucidMic version, and steps to reproduce. Do not attach private call recordings.
If an audio sample helps, make a short recording specifically for the report.

## Project layout

- `Sources/LucidMic`: menu-bar UI, device discovery, and audio routing.
- `Sources/LucidEngine`: C audio engine and inference worker.
- `Sources/lucidmic-file`: offline file-processing tool.
- `Tests/LucidEngineTests`: engine behavior and live/offline parity tests.
- `Resources`: logo, installer art, app metadata, and dependency licenses.
- `scripts`: pinned dependencies, artwork, checks, driver build, and DMG packaging.
- `docs/plans`: historical development notes; the README describes shipped behavior.

Use `xcrun swift-format format --in-place --recursive Sources Tests Package.swift`
for Swift and `uv run --no-project --with-requirements requirements-dev.txt ruff format scripts`
for Python. Shell scripts are checked by ShellCheck.

## Releases

The drag-to-Applications installer is created with
[dmgbuild](https://github.com/dmgbuild/dmgbuild), pinned in `requirements-dev.txt`.
It is a build tool and is not bundled in the installed app.

Update the changelog and version defaults, then run the full checks and
`scripts/build.sh <version>`. Verify the app from the mounted DMG on macOS, not
only the development executable. The **Prepare release** GitHub Actions workflow
builds the same artifacts and creates a draft release for review.

Attach the DMG, `SHA256SUMS.txt`, `BlackHole-0.7.1-source.tar.gz`, and the matching
`LucidMic-<version>-runtime-source.tar.gz`.
Keep the release tag on the exact source used for the build. Never commit signing
credentials or notarization secrets. Contributions are provided under GPL-3.0.
