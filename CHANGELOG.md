# Changelog

## 1.0.2 — Unreleased

- Choose a physical microphone and input channel in Settings. Changes briefly
  restart routing while preserving the Noise Removal setting.
- Stop safely and offer a retry when an active device disconnects or its audio
  configuration becomes unsupported; report failed default-input changes.
- Validate 48 kHz audio and buffers up to 512 frames before routing starts.
- Handle disabled audio streams safely and recover from processing stalls
  without retaining extra delay. The engine's declared latency is now 72 ms.
- Preserve the duration and ending of offline recordings and include every
  source channel when converting to mono.
- Stage and validate driver replacements before replacing an existing installation.
- Bundle the upstream runtime without speech synthesis, retaining the existing
  model and library versions; expand audio, lifecycle, installer, and packaging regressions.

## 1.0.1 — 2026-09-30

- Native macOS menu with a checkmarked Noise Removal command and grouped actions.
- Clear idle, cleaning, original-audio, setup, and error states, with the actual input name.
- Separate Settings window for launch at login and confirmed virtual-microphone removal.
- Native About panel, offline usage help, and standard keyboard commands.
- Login-item status refreshes when returning from System Settings.
- Updated light/dark README previews and focused runtime credits.

The noise-removal model and audio engine are unchanged.

## 1.0.0 — 2026-09-30

First packaged release of LucidMic for Apple silicon Macs running macOS 14 or later.

- Local 48 kHz microphone noise removal powered by DPDFNet2.
- A menu-bar switch that toggles cleaning without disconnecting the microphone.
- Bundled LucidMic Microphone driver with one-time installation and in-app removal.
- Automatic system-default input routing and restoration on quit.
- Optional launch at login.
- New microphone monogram, macOS icon, and drag-to-Applications installer.
- GPL-3.0 source, dependency licenses, verified downloads, and release checksums.

The release is ad-hoc signed and not notarized. Intel Macs are not supported.
