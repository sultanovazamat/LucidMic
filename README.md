<p align="center">
  <img src="docs/assets/logo.png" width="128" height="128" alt="LucidMic's icon: a white microphone monogram on blue and cyan">
</p>

<h1 align="center">LucidMic</h1>

<p align="center">
  Your voice. Minus the noise.<br>
  Free, on-device AI noise removal for your Mac. One switch in the menu bar.
</p>

<p align="center">
  <a href="https://github.com/sultanovazamat/LucidMic/releases/latest"><img alt="Release 1.0.0" src="https://img.shields.io/badge/release-1.0.0-blue"></a>
  <a href="https://github.com/sultanovazamat/LucidMic/actions/workflows/ci.yml"><img alt="GitHub Actions" src="https://img.shields.io/badge/CI-GitHub_Actions-000000?logo=githubactions&logoColor=white"></a>
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-required-000000">
  <a href="LICENSE"><img alt="GPL-3.0 licence" src="https://img.shields.io/badge/licence-GPL--3.0-blue"></a>
</p>

<p align="center">
  <a href="https://github.com/sultanovazamat/LucidMic/releases/download/v1.0.0/LucidMic-1.0.0.dmg"><b>Download LucidMic for Mac</b></a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/hero-dark.png">
  <img alt="LucidMic's menu: a noise-removal switch, launch at login, and uninstall control" src="docs/assets/hero-light.png">
</picture>

## Why it exists

Calls do not wait for a quiet room. Fans, keyboards and background noise can
follow you into every meeting. LucidMic cleans your microphone before the
sound reaches your call app, so you control it from one place.

## What it does

- **Reduces background noise.** A local speech-enhancement model cleans your
  microphone in real time. Results depend on your microphone and environment.
- **Works across your call apps.** Apps using the system-default input receive
  the cleaned audio. If you picked a specific microphone in an app, choose
  *LucidMic Microphone* there instead.
- **Lets you hear the difference.** Flip the switch during a call or recording.
  Turning noise removal off passes your original audio through without
  disconnecting the virtual microphone.
- **Stays in the menu bar.** One switch, a status line, and optional launch at
  login. Quitting restores your physical microphone as the default.
- **Installs its own microphone.** Approve the driver installation once. Remove
  it later from the same menu.

## Privacy

- Audio processing runs entirely on your Mac. Audio is not uploaded.
- The model and inference libraries are included in the download. The installed
  app works offline and does not need to fetch a model on first launch.
- No account, subscription or analytics.
- LucidMic uses your microphone, which macOS asks you to allow under
  **Privacy & Security → Microphone**.

## Install

You need a Mac with Apple silicon and macOS 14 Sonoma or later.

1. Download [LucidMic-1.0.0.dmg](https://github.com/sultanovazamat/LucidMic/releases/download/v1.0.0/LucidMic-1.0.0.dmg)
   and drag LucidMic into Applications.
2. Open it. LucidMic is not notarised yet, so macOS may stop the first launch.
   Open **System Settings → Privacy & Security** and click **Open Anyway**
   after trying to open the app.
3. Click the waveform in your menu bar and turn **Noise removal** on. Allow
   microphone access and approve the one-time driver installation.

Install before joining a call: installing the driver restarts the macOS audio
service. In apps where you selected a microphone manually, choose **LucidMic
Microphone** in their audio settings.

## Using it

Everything is in the menu bar icon:

- **Noise removal** — cleans your voice when on; passes your original audio
  through when off. This switch does not mute the microphone.
- **Launch at login** — opens LucidMic when you sign in.
- **Uninstall…** — removes the virtual microphone and restores the physical one.
- **Quit** — stops routing and restores your physical microphone as the default.

Nearby people talking and music vocals may remain: the model preserves speech
and does not identify a particular speaker. Use headphones so your call
partner's voice does not feed back through your microphone. For a comparison,
try turning off your call app's own noise suppression.

If Spotlight cannot find LucidMic, open it from Applications. Check Spotlight's
search-privacy settings and, if necessary,
[reindex the Applications folder](https://support.apple.com/en-us/102321).
LucidMic does not show a Dock icon.

## How it works

A native SwiftUI menu controls a C audio engine. The audio callback moves
samples through ring buffers; a worker thread runs the noise-removal model.
A customised BlackHole driver makes the result available as a microphone.

```text
Physical microphone ──▶ DPDFNet2 ──▶ LucidMic Microphone ──▶ Your call app
                         48 kHz
                       on your Mac
```

[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) and ONNX Runtime run the
[DPDFNet2](https://github.com/ceva-ip/DPDFNet) model. The engine buffers **70 ms**
of audio; your devices and call app can add further delay. The same engine is
used by the app, the file-processing tool, and the tests.

## Build from source

With full Xcode and Swift 6 or later on an Apple silicon Mac, plus
[uv](https://docs.astral.sh/uv/) and [ShellCheck](https://www.shellcheck.net/):

```sh
git clone https://github.com/sultanovazamat/LucidMic.git
cd LucidMic
scripts/check.sh          # pinned dependencies, format/lint, build, tests
scripts/build.sh 1.0.0    # checked DMG, corresponding source, and checksums
```

Select Xcode as your active developer directory. The build downloads pinned
dependencies and verifies their checksums. The **Prepare release** workflow
builds the same artifacts and creates a draft release.

To regenerate the icon and installer/repository artwork:

```sh
uv run --no-project --with-requirements requirements-dev.txt python scripts/make-art.py
```

For the offline file-processing tool, run `swift run lucidmic-file` to see usage.
The source layout and release steps are in [CONTRIBUTING.md](CONTRIBUTING.md).
Runtime build provenance is in [docs/runtime-build.md](docs/runtime-build.md).

## Contributing

Issues and focused pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md)
explains the code layout and checks. See [CHANGELOG.md](CHANGELOG.md) for releases.

## Credits

- [DPDFNet2](https://github.com/ceva-ip/DPDFNet) by Ceva: the speech-enhancement
  model. Apache-2.0.
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx): the model API. Its own code
  is Apache-2.0; the distributed runtime includes separately licensed components,
  including GPL-3.0 eSpeak NG.
- [ONNX Runtime](https://github.com/microsoft/onnxruntime) by Microsoft: inference.
  MIT.
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) by Existential Audio:
  the virtual microphone driver. GPL-3.0.
- [dmgbuild](https://github.com/dmgbuild/dmgbuild), for the install window.

Their licences and notices are in
[Resources/THIRD_PARTY_NOTICES.txt](Resources/THIRD_PARTY_NOTICES.txt) and
[Resources/Licenses](Resources/Licenses), which also ship inside the app.
The release includes matching driver and runtime source archives; exact runtime
revisions are in [scripts/runtime-sources.json](scripts/runtime-sources.json).

## Licence

[GPL-3.0](LICENSE) © 2026 Azamat Sultanov
