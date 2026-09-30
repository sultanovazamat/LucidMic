# LucidMic

One switch in your menu bar that makes your voice clearer in every app. It removes background
noise (keyboard, fans, street, kids) with RNNoise before Zoom, Meet, Teams, Slack or Voice Memos
hear you. No Terminal and no per-app setup.

## Install

Requires an Apple silicon Mac with macOS 14 or later.

1. Open `LucidMic-<version>.dmg` and drag **LucidMic** to **Applications**.
2. Open LucidMic from Applications. The first time, macOS may block it because the app is not
   notarized. Go to **System Settings › Privacy & Security** and click **Open Anyway**.
3. Click the waveform icon in the menu bar and turn LucidMic on. The first time, it installs its
   microphone and asks for your password once. Then allow microphone access.

That's it. Zoom (set to "Same as System"), Meet, Teams, FaceTime and Voice Memos now get your
clean voice. To remove LucidMic, click **Uninstall…** in its menu, then delete the app.

## How it works

When you turn LucidMic on, it makes **LucidMic Microphone** your default microphone. It then streams
your real mic through RNNoise into that device. Turning it off, or quitting, switches your real
mic back. Apps where you picked a specific mic by hand keep using that mic.

## Build

```bash
swift test          # engine tests
scripts/build.sh    # dist/LucidMic-0.1.0.dmg (also builds the driver on first run)
```

Third-party code:
- RNNoise 0.2 (BSD-3-Clause, Xiph.Org / Jean-Marc Valin) is vendored in `Sources/CRNNoise`.
- The microphone driver is BlackHole v0.7.1 (GPL-3.0, Existential Audio), renamed and built by
  `scripts/build-driver.sh`.

Both licenses ship inside the app bundle.
