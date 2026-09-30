# Inline audio previews in the README

Status: implemented and verified on 2026-10-01. Approved by the user after the renderer experiment and proposed MP4 attachment approach.

**Classification:** Presentation feature correcting the inconvenient download-only examples.

**Expected versus actual:** Visitors should play both versions from the repository README. The current table links to WAV files, requiring navigation or a download. GitHub removes ordinary audio tags and video tags that point to repository files. Its renderer accepts GitHub video attachments inside table cells.

**Plan:**
1. Render twelve H.264/AAC MP4 previews from the existing verified WAVs. Use only a static Original/LucidMic label; preserve the full recording and its level. Keep previews separate from lossless reference audio.
2. Upload the approved previews to GitHub's attachment storage using its authenticated upload flow, without posting messages or comments.
3. Put each attachment video in the existing Before/After table cell, with the corresponding WAV link underneath. Add a short unmute instruction and identify the previews as compressed audio.
4. Record source hashes, preview hashes, attachment URLs, and reproduction instructions. Verify actual GitHub rendering and browser playback before committing and pushing; omit co-author trailers.

**Files:** `README.md`, `docs/demo/README.md`, `docs/demo/previews.json`, a small `scripts/prepare-demo-previews.py` renderer, and this plan. Generated MP4s stay under ignored `build/demo-previews`; GitHub hosts the embedded attachments. Original WAVs and engine processing are unchanged.

**Acceptance criteria:** All six rows render two inline players in GitHub's README; all twelve players load and play; every row retains lossless WAV links; preview/source mappings are correct; no TTS, extra noise, normalization, or extra denoising; no separate webpage; uploaded URLs are stable attachment URLs, not signed or expiring download URLs.

**Verification:** Check WAV hashes first; use ffprobe to verify codecs, mono audio, sample rates, and duration within encoding/frame precision; decode every preview; compare decoded audio with its source for alignment and preserved level. Test README markup through GitHub's Markdown API and the rendered page in Chromium. Run the standard format/lint/build/test gates and inspect the staged diff before commit.

## Results

- Generated twelve previews totaling 1,611,164 bytes. All use H.264/yuv420p video and mono 48 kHz AAC. Audio durations match their complete sources; the café MP4 containers round the last video frame from 5.66 to 5.68 seconds.
- Decoded every preview and compared it with its source at 48 kHz: each correlation exceeded 0.98 and each RMS level difference was below 0.2 dB. These checks detect wrong files, timing shifts, and unintended gain changes; they are not perceptual quality scores.
- Uploaded all previews through the same repository-scoped attachment endpoint used by GitHub CLI. No issue or comment was created. Downloaded every hosted file and verified its SHA-256 against the generated MP4.
- GitHub's authenticated Markdown renderer returned all twelve native players inside the table. Chromium played and decoded audio from every hosted preview, unmuted successfully, and sought within a clip. Desktop rendering fits the content area; mobile uses GitHub's horizontal table scrolling without page-wide overflow.
- The repository is private. Browser verification used authenticated API-rendered HTML with GitHub's stylesheets and hosted media in a temporary local preview; it did not use a logged-in GitHub browser session. Only stable attachment URLs are saved in repository files.
- `scripts/check.sh` passed format, lint, shell/plist checks, build, 19 Python tests, and 56 Swift tests. Source/preview/README mappings, local documentation links, and `git diff --check` passed. Original WAV hashes remain unchanged.

## Remaining limits

GitHub's players begin muted, so the README explains the speaker control. AAC previews are compressed; lossless WAV links remain directly below each player. Native table players have independent playback controls. GitHub controls their styling and availability. The original documented copier clipping remains visible in the lossless reference and has not been hidden by gain adjustment.
