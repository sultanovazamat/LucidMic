# LucidMic

One switch in your menu bar that makes your voice clearer in every app. It removes background
noise (keyboard clicks, café buzz, fans and AC, traffic, munching, dogs and doors, hum and hiss,
echoey rooms) in real time, before Zoom, Meet, Teams, Slack or Voice Memos hear you. No Terminal
and no per-app setup.

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
your real mic through **DPDFNet2** (48 kHz, Ceva, Apache-2.0) into that device. Everything runs on
your Mac, with about 70 ms of delay and about 18% of one CPU core. The switch turns noise removal
on and off instantly, even mid-recording. Quitting LucidMic switches your real mic back. Apps
where you picked a specific mic by hand keep using that mic.

Not removed: a nearby person talking clearly (the model treats any voice as speech) and song
vocals. Use headphones on calls, because a call partner's voice from your speakers is speech too.

## Build

```bash
scripts/fetch-deps.sh   # sherpa-onnx runtime + DPDFNet model into build/deps
swift test              # engine tests (offline and live paths)
scripts/build.sh        # dist/LucidMic-0.1.0.dmg (also builds the driver on first run)
```

To redraw the icon or the installer background, run
`uv run --no-project --with pillow python scripts/make-art.py`.

Third-party code:
- DPDFNet model (Apache-2.0, Ceva), sherpa-onnx (Apache-2.0) and ONNX Runtime (MIT), fetched by
  `scripts/fetch-deps.sh`.
- The microphone driver is BlackHole v0.7.1 (GPL-3.0, Existential Audio), renamed and built by
  `scripts/build-driver.sh`.

The notices ship inside the app (`THIRD_PARTY_NOTICES.txt`).
