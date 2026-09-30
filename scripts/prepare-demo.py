"""Render or verify the pinned real-recording examples. No TTS, mixing, or normalization."""

import argparse
import array
import hashlib
import json
import math
import shutil
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def audio_info(path):
    with wave.open(str(path), "rb") as audio:
        if audio.getnchannels() != 1 or audio.getsampwidth() != 2 or audio.getcomptype() != "NONE":
            raise ValueError(f"{path.name}: expected mono 16-bit PCM")
        frames, rate = audio.getnframes(), audio.getframerate()
        samples = array.array("h", audio.readframes(frames))
    if sys.byteorder != "little":
        samples.byteswap()
    if len(samples) != frames or not frames or max(map(abs, samples), default=0) < 32:
        raise ValueError(f"{path.name}: missing, truncated, or silent audio")
    peak = max(map(abs, samples)) / 32768
    return {
        "frames": frames,
        "sample_rate_hz": rate,
        "duration_seconds": frames / rate,
        "peak_dbfs": round(20 * math.log10(peak), 3),
        "clipped_samples": sum(value in (-32768, 32767) for value in samples),
    }


def paths(directory, sample):
    identifier = sample["id"]
    if not identifier or any(character not in "abcdefghijklmnopqrstuvwxyz0123456789-" for character in identifier):
        raise ValueError("Invalid sample identifier")
    return directory / "audio" / f"{identifier}-original.wav", directory / "audio" / f"{identifier}-lucidmic.wav"


def verify_pair(directory, sample):
    original, processed = paths(directory, sample)
    for path, expected in [(original, sample["source_sha256"]), (processed, sample["processed_sha256"])]:
        if digest(path) != expected:
            raise ValueError(f"{path.name}: SHA-256 mismatch")
    before, after = audio_info(original), audio_info(processed)
    if before["sample_rate_hz"] != sample["source_sample_rate_hz"] or after["sample_rate_hz"] != 48_000:
        raise ValueError(f"{sample['id']}: unexpected sample rate")
    expected_frames = round(before["frames"] * 48_000 / before["sample_rate_hz"])
    if after["frames"] != expected_frames:
        raise ValueError(f"{sample['id']}: output duration does not match the complete original")
    return {"id": sample["id"], "original": before, "lucidmic": after}


def render(directory, manifest):
    model = ROOT / "build/deps/dpdfnet2_48khz_hr.onnx"
    if digest(model) != manifest["processing"]["model_sha256"]:
        raise ValueError("Model SHA-256 mismatch; use scripts/fetch-deps.sh")
    subprocess.run(["swift", "build", "-c", "release", "--product", "lucidmic-file"], cwd=ROOT, check=True)
    binary_directory = subprocess.check_output(
        ["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True
    ).strip()
    binary = Path(binary_directory) / "lucidmic-file"
    directory.mkdir(parents=True, exist_ok=True)
    # Validate every new pair before replacing any checked-in audio.
    with tempfile.TemporaryDirectory(prefix="lucidmic-demo-") as temporary:
        staging = Path(temporary)
        (staging / "audio").mkdir()
        for sample in manifest["samples"]:
            cached, _ = paths(directory, sample)
            original, processed = paths(staging, sample)
            if cached.exists() and digest(cached) == sample["source_sha256"]:
                shutil.copyfile(cached, original)
            else:
                subprocess.run(
                    [
                        "curl",
                        "--fail",
                        "--location",
                        "--silent",
                        "--show-error",
                        "--retry",
                        "2",
                        "--max-time",
                        "60",
                        "--output",
                        str(original),
                        sample["source_url"],
                    ],
                    check=True,
                )
            if digest(original) != sample["source_sha256"]:
                raise ValueError(f"{sample['id']}: source SHA-256 mismatch")
            subprocess.run([str(binary), str(original), str(processed), str(model)], cwd=ROOT, check=True)
            sample["processed_sha256"] = digest(processed)
            verify_pair(staging, sample)
        (directory / "audio").mkdir(exist_ok=True)
        for source in (staging / "audio").iterdir():
            shutil.copyfile(source, directory / "audio" / source.name)
    manifest["processing"]["app_commit"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()
    manifest["processing"]["source_hashes"] = {
        name: digest(ROOT / name)
        for name in [
            "Sources/LucidEngine/LucidEngine.c",
            "Sources/LucidEngine/include/LucidEngine.h",
            "Sources/LucidFileProcessing/AudioFileProcessor.swift",
            "Sources/lucidmic-file/main.swift",
        ]
    }
    manifest["processing"]["runtime_hashes"] = {
        name: digest(ROOT / "build/deps/sherpa/lib" / name)
        for name in ["libsherpa-onnx-c-api.dylib", "libonnxruntime.dylib"]
    }
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--render", action="store_true", help="Render all pairs and update their hashes")
    action.add_argument("--verify", action="store_true", help="Check existing assets without downloading or building")
    parser.add_argument("--directory", type=Path, default=ROOT / "docs/demo")
    args = parser.parse_args()
    try:
        manifest = json.loads((args.directory / "manifest.json").read_text())
        if args.render:
            render(args.directory, manifest)
        report = [verify_pair(args.directory, sample) for sample in manifest["samples"]]
        if args.render:
            (args.directory / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
        elif json.loads((args.directory / "verification.json").read_text()) != report:
            raise ValueError("Stored verification report differs from the audio measurements")
        for result in report:
            print(
                f"{result['id']}: verified source/output hashes, {result['original']['duration_seconds']:.2f}s, "
                f"{result['lucidmic']['clipped_samples']} full-scale output samples"
            )
    except (OSError, ValueError, KeyError, wave.Error, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Demo verification failed: {error}\n")


if __name__ == "__main__":
    main()
