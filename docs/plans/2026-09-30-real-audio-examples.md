# Real-recording repository examples

Status: simplified to a main-README table at the user's explicit request and verified locally. The user authorized committing and pushing these repository examples on 2026-10-01.

**Classification:** Feature, with a presentation correction. The user requested repository examples and clarified that they belong in a simple table on the repository's main page. A separate HTML/CSS/JavaScript player added unnecessary scope.

**Goal:** Let repository visitors compare genuine noisy human recordings with the same recordings processed by LucidMic, using a table in the main README.

**Architecture:** Six complete Microsoft DNS Challenge real recordings, attributed to a pinned source revision and CC BY 4.0 license. The existing release-mode `lucidmic-file` executable produces the processed WAVs. A Markdown table links each original and processed recording. Supporting documentation contains attribution, methodology, and reproduction commands.

**Expected outcome:** The main README contains recording names, durations, and Before/After WAV links. The separate player and its server instructions are removed. Audio, licensing, provenance, and reproducibility remain available in the repository.

**Files:** Update `README.md`, `docs/demo/README.md`, and descriptive text in `docs/demo/manifest.json`. Remove `docs/demo/index.html`, `docs/demo/player.js`, and `docs/demo/style.css`. Retain `docs/demo/audio/*.wav`, `docs/demo/LICENSE-audio.txt`, `docs/demo/verification.json`, `scripts/prepare-demo.py`, and `scripts/tests/test_demo_assets.py`.

**Acceptance criteria:**
- Six rows in the main README, with both WAV links and the correct duration.
- Genuine human recordings; no TTS, added noise, or level normalization.
- Original bytes and complete durations preserved; output uses the app's actual engine.
- Source attribution, audio license, hashes, and reproduction steps remain linked.
- No separate web player, hosting dependency, or local-server instructions.
- Known copier clipping and the illustrative scope remain documented.

**Implementation:** Simplify the existing main-README table, remove its player call-to-action, reduce the supporting README to provenance/methodology, remove the player files, and reconcile this plan with the clarified scope.

**Test plan:** Verify all local documentation links, all twelve audio hashes and durations, and the six displayed durations against `verification.json`. Run `scripts/check.sh` and `git diff --check`. No new tests are needed for this documentation simplification; the existing asset regressions remain relevant.

## Audio verification and review

- Twelve WAVs total 5,408,520 bytes. Original hashes match pinned upstream Git LFS objects. The audio license preserves the upstream wording; line endings and trailing whitespace are normalized.
- Two renders produced identical output hashes and processing metadata on this machine.
- The asset verifier checks hashes, mono PCM format, sample rates, complete duration, nonempty audio, and saved measurements.
- Four Python regression tests cover valid assets, corrupted originals, truncated output, and stale measurements. A review finding about stale reports was reproduced and fixed by comparing saved and freshly measured values.
- After simplification, `scripts/check.sh` passed formatting, lint, build, 19 Python tests, and 56 Swift tests. All six asset pairs passed `--verify`; all six displayed durations and 27 local documentation links were checked. `git diff --check` passed. The separate player files and server instructions are absent, and the temporary preview server was stopped.

## Remaining limits

The copier output has 15 full-scale samples out of 240,000; its original peaks at −0.035 dBFS. The README and measurements disclose this without changing levels or substituting another recording. Listening quality has not been assessed by a human. These are illustrative offline engine examples, not quality scores or live microphone captures. Source bandwidth is limited by the original 16 kHz recordings. The README table contains file links, not embedded audio controls.
