# LucidMic brand assets

- `logo.png`: the transparent PNG master, generated with the built-in image tool.
- `wordmark.png`: the mark with the LucidMic wordmark, on a transparent background.
- `banner.png`: optional branded cover artwork.
- `menu-light.png` and `menu-dark.png`: native snapshots rendered from the actual
  SwiftUI `MenuView`, in its idle state with the driver installed. These are UI
  previews, not recordings of a call.
- `hero-light.png` and `hero-dark.png`: the native menu snapshots framed for the
  README's light/dark presentation, following the author's Bilby repository layout.
- `../../Resources/AppIcon.icns`: macOS icon with standard and Retina sizes.

Run `scripts/make-art.py` with the dependencies in `requirements-dev.txt` to
regenerate the packaged icon and layouts from the committed master.

Design prompt: a simple white microphone monogram with an M-shaped capsule and a
curved cradle, on an electric-blue-to-cyan macOS rounded-square tile. Keep the mark
legible at small sizes, with transparent margins, no text, and no decorative detail.
A second generation pass requested clean alpha edges while preserving the design.

The logo was generated using the built-in image tool, not the fallback API CLI.
Typography and installer/repository layouts are rendered by `scripts/make-art.py`.
