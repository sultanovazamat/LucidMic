# LucidMic

One switch in your menu bar that makes your voice clearer in every app. It removes background
noise (keyboard, fans, street, kids) with RNNoise before Zoom, Meet, Teams, Slack or Voice Memos
hear you. No per-app setup is needed.

## Install

Requires an Apple silicon Mac with macOS 14 or later.

1. Install the free BlackHole 2ch virtual microphone: `brew install blackhole-2ch`, or use the
   installer from https://existential.audio/blackhole/.
2. Download `LucidMic-<version>.zip` from Releases, unzip it, and move **LucidMic** to Applications.
3. Open LucidMic. If macOS blocks it, go to **System Settings › Privacy & Security** and click
   **Open Anyway**.
4. Click the waveform icon in the menu bar and turn LucidMic on. Allow microphone access.

## How it works

When you turn LucidMic on, it makes the BlackHole virtual mic your default microphone. It then
streams your real mic through RNNoise into BlackHole, so every app using the default microphone
hears the cleaned audio. Turning it off, or quitting, switches your real mic back. Apps where you
picked a specific mic by hand keep using that mic; set them to the default (in Zoom, "Same as
System").

## Build

```bash
swift test          # engine tests
scripts/build.sh    # dist/LucidMic.app + dist/LucidMic-0.1.0.zip
```

RNNoise 0.2 (BSD-3-Clause, Xiph.Org / Jean-Marc Valin) is vendored in `Sources/CRNNoise`. Its
license is in `Sources/CRNNoise/COPYING`.
