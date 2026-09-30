# Audio example sources and reproduction

Six genuine recordings of people speaking in everyday environments, before and
after LucidMic. Speech and surrounding sounds were recorded together. No TTS,
added noise, normalization, or second noise-removal stage is used.

All six before/after pairs are linked in the
[main README's comparison table](../../README.md#hear-the-difference).

## Source and attribution

**Microsoft and DNS Challenge contributors**, *Initial Testset for DNS Challenge*,
Microsoft real recordings, from the INTERSPEECH 2020 DNS Challenge repository at
revision `70f19285c36cca4df2338f9248775ddc50980c6b`.

- [Dataset description](https://github.com/microsoft/DNS-Challenge/blob/70f19285c36cca4df2338f9248775ddc50980c6b/datasets/test_set/README.md)
- [Original recordings directory](https://github.com/microsoft/DNS-Challenge/tree/70f19285c36cca4df2338f9248775ddc50980c6b/datasets/test_set/real_recordings)
- [Upstream license](https://github.com/microsoft/DNS-Challenge/blob/70f19285c36cca4df2338f9248775ddc50980c6b/LICENSE)
- [Source and processing manifest](manifest.json), including exact filenames, URLs, and SHA-256 values

The source recordings and processed adaptations are provided under
**[Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)**;
the complete license is in [LICENSE-audio.txt](LICENSE-audio.txt). This audio
license is separate from LucidMic's GPL-3.0 code license. The LucidMic files are
modified versions. Microsoft and the speakers do not endorse LucidMic.

These are the `ms_realrec_speakerphone` clips collected internally at Microsoft,
which the source documentation distinguishes from its synthetic mixtures and
AudioSet examples. Titles and capture-device descriptions follow the original
filenames; individual recording conditions were not independently measured.

The six clips were selected by recording condition before processing, with a
quiet-room control. They were not ranked by improvement. Each clip is complete;
the original WAV files are byte-identical to upstream Git LFS objects.

## Processing and limitations

Rendered with LucidMic **1.0.2 candidate**, app/engine commit
[`8161529`](https://github.com/sultanovazamat/LucidMic/commit/8161529), DPDFNet2
48 kHz HR, and the pinned sherpa-onnx runtime used by the app.

```sh
swift run -c release lucidmic-file original.wav lucidmic.wav
```

The existing file processor converts the 16 kHz mono input to 48 kHz, denoises
it, drains the ending, trims the initial engine delay, and writes 16-bit mono
PCM. No extra gain, equalization, cropping, or loudness normalization is applied.
The complete duration is retained. Model, runtime, processing-source, and output
hashes are recorded in the manifest.

The originals have **16 kHz bandwidth limitations**. Saving processed files at
48 kHz does not restore missing high-frequency information. These are offline
engine examples, not recordings of the live virtual microphone. The live
engine adds 72 ms of delay, in addition to device/application latency.

**Copier edge case:** the original peaks at −0.035 dBFS. The processed WAV has
15 full-scale samples out of 240,000. We retain that output and disclose the
clipping rather than changing levels or selecting a different recording.
This is a known limitation for this loud input, not a claim of transparent
processing. Nearby voices can also remain: the model does not identify a
particular speaker.

These examples are **not a benchmark**. No subjective quality scores,
aggregate improvement claim, or clean reference is available for these real
noisy recordings. Listen to the voice as well as the background.

## Reproduce and verify

On an Apple silicon Mac with the project's normal Swift build prerequisites:

```sh
scripts/fetch-deps.sh
python3 scripts/prepare-demo.py --render
```

The script uses the checked-in originals if their hashes match, otherwise it
downloads the pinned source objects and checks their upstream hashes. It runs
the release-mode file processor and records the generated hashes and file
measurements. A changed engine/runtime can produce changed output; the manifest
records the exact code and libraries used in each render. For the original
processing behavior, use the engine revision and hashes specified above.

Verification alone needs only Python's standard library, without audio hardware,
network access, or model loading:

```sh
python3 scripts/prepare-demo.py --verify
```

Checks cover source/output hashes, mono PCM format, nonempty audio, complete
duration, and consistency with the saved [file measurements](verification.json).
The measured full-scale sample counts are diagnostics, not listening scores.
The repository's standard Python tests exercise corrupted originals, truncated
outputs, and stale published measurements.
