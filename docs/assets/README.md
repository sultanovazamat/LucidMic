# LucidMic brand assets

- `logo.png`: the transparent PNG master, generated with the built-in image tool.
- `wordmark.png`: the mark with the LucidMic wordmark, on a transparent background.
- `banner.png`: optional branded cover artwork.
- `menu-light.png` and `menu-dark.png`: illustrations rendered from the app's
  actual `NativeMenu` items, using system fonts and colors. The staged state is
  cleaning with a sample “Built-in Microphone”. These are not desktop screenshots;
  macOS supplies the installed menu's exact spacing, material, and appearance.
- `hero-light.png` and `hero-dark.png`: the labelled menu previews framed for the
  README's light/dark presentation, following the author's Bilby repository layout.
- `../../Resources/AppIcon.icns`: macOS icon with standard and Retina sizes.

Run `scripts/render-menu.sh` to regenerate the menu illustrations without
Screen Recording access or microphone capture. Then run `scripts/make-art.py`
with the dependencies in `requirements-dev.txt` to regenerate the framed
previews, packaged icon, and layouts from the committed master.

Design prompt: a simple white microphone monogram with an M-shaped capsule and a
curved cradle, on an electric-blue-to-cyan macOS rounded-square tile. Keep the mark
legible at small sizes, with transparent margins, no text, and no decorative detail.
A second generation pass requested clean alpha edges while preserving the design.

The logo was generated using the built-in image tool, not the fallback API CLI.
Typography and installer/repository layouts are rendered by `scripts/make-art.py`.
