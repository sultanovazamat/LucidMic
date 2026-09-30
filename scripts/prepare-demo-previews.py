"""Create labeled MP4 listening previews; the WAVs remain the lossless references."""

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/demo-previews")
    parser.add_argument("--font", type=Path, default=Path("/System/Library/Fonts/Supplemental/Arial.ttf"))
    args = parser.parse_args()
    if not args.font.is_file():
        parser.error("Provide a TrueType font with --font")
    subprocess.run([sys.executable, str(ROOT / "scripts/prepare-demo.py"), "--verify"], check=True)
    samples = json.loads((ROOT / "docs/demo/manifest.json").read_text())["samples"]
    durations = {
        sample["id"]: sample["original"]["duration_seconds"]
        for sample in json.loads((ROOT / "docs/demo/verification.json").read_text())
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    # Filter paths are quoted separately from shell arguments; subprocess never uses a shell.
    font = str(args.font.resolve()).replace("\\", "\\\\").replace(":", "\\:").replace("'", "'\\''")
    report = {
        "encoder": subprocess.check_output(["ffmpeg", "-version"], text=True).splitlines()[0],
        "encoding": "480x270 H.264, 25 fps; mono 48 kHz AAC at 256 kb/s; no gain adjustment",
        "files": [],
    }
    for sample in samples:
        for version, label in [("original", "Original"), ("lucidmic", "LucidMic")]:
            stem = f"{sample['id']}-{version}"
            source = ROOT / "docs/demo/audio" / f"{stem}.wav"
            output = args.output_dir / f"{stem}.mp4"
            subprocess.run(
                [
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-y",
                    "-f",
                    "lavfi",
                    "-i",
                    "color=c=0xf5f7fa:s=480x270:r=25",
                    "-i",
                    str(source),
                    "-map",
                    "0:v:0",
                    "-map",
                    "1:a:0",
                    "-vf",
                    f"drawtext=fontfile='{font}':text='{label}':fontsize=38:fontcolor=0x162337:x=(w-tw)/2:y=(h-th)/2",
                    "-t",
                    str(durations[sample["id"]]),
                    "-c:v",
                    "libx264",
                    "-preset",
                    "medium",
                    "-crf",
                    "23",
                    "-pix_fmt",
                    "yuv420p",
                    "-c:a",
                    "aac",
                    "-b:a",
                    "256k",
                    "-ar",
                    "48000",
                    "-ac",
                    "1",
                    "-movflags",
                    "+faststart",
                    "-map_metadata",
                    "-1",
                    str(output),
                ],
                check=True,
            )
            report["files"].append(
                {
                    "id": sample["id"],
                    "version": version,
                    "source": str(source.relative_to(ROOT)),
                    "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                    "filename": output.name,
                    "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                    "bytes": output.stat().st_size,
                    "duration_seconds": durations[sample["id"]],
                }
            )
            print(f"Rendered {output.name}")
    (args.output_dir / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
