"""Package pinned source archives corresponding to the shipped inference runtime."""

import argparse
import gzip
import hashlib
import io
import json
import re
import subprocess
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def reproducible(info: tarfile.TarInfo) -> tarfile.TarInfo:
    info.uid = info.gid = info.mtime = 0
    info.uname = info.gname = ""
    return info


def package(version: str) -> None:
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise SystemExit("Expected numeric major.minor.patch version")
    manifest = ROOT / "scripts/runtime-sources.json"
    entries = json.loads(manifest.read_text())
    cache = ROOT / "build/runtime-sources"
    cache.mkdir(parents=True, exist_ok=True)
    archives = []
    for entry in entries:
        name = entry["name"]
        if not re.fullmatch(r"[a-zA-Z0-9_.-]+", name):
            raise SystemExit(f"Invalid source name: {name}")
        archive = cache / f"{name}.tar.gz"
        if not archive.exists() or digest(archive) != entry["sha256"]:
            partial = archive.with_suffix(".gz.part")
            subprocess.run(
                [
                    "curl",
                    "--fail",
                    "--location",
                    "--silent",
                    "--show-error",
                    "--retry",
                    "3",
                    entry["url"],
                    "-o",
                    str(partial),
                ],
                check=True,
            )
            if digest(partial) != entry["sha256"]:
                partial.unlink()
                raise SystemExit(f"Source checksum mismatch: {name}")
            partial.replace(archive)
        archives.append(archive)
        print(f"Verified source: {name} ({entry['revision']})", flush=True)

    output = ROOT / "dist" / f"LucidMic-{version}-runtime-source.tar.gz"
    output.parent.mkdir(exist_ok=True)
    readme = (
        f"LucidMic {version}: corresponding inference-runtime source\n\n"
        "The archives in archives/ are unmodified upstream sources pinned by sources.json.\n"
        "Every archive is SHA-256 verified. Extract the individual archives to inspect\n"
        "their source, license files, CMake build files and upstream build workflows.\n\n"
        "LucidMic ships the official sherpa-onnx v1.13.8 macOS arm64 shared runtime.\n"
        "Its source archive contains the CMake dependency recipes and release workflows.\n"
        "BUILD.md documents the upstream build, ONNX library-version patch, and build commands.\n"
        "The large, separately MIT-licensed ONNX Runtime source is hosted upstream:\n"
        "https://github.com/microsoft/onnxruntime/archive/refs/tags/v1.28.2.tar.gz\n"
        "Use the revisions in sources.json, not moving upstream default branches.\n\n"
        "LucidMic source and its build scripts are available in the same release's\n"
        "Source code archive. BlackHole's corresponding source is supplied separately.\n"
        "Dependency license texts are also distributed inside LucidMic.app/Contents/Resources/Licenses.\n"
    ).encode()
    with output.open("wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
        with tarfile.open(mode="w", fileobj=compressed) as bundle:
            for source in archives:
                bundle.add(source, arcname=f"RuntimeSource/archives/{source.name}", filter=reproducible)
            bundle.add(manifest, arcname="RuntimeSource/sources.json", filter=reproducible)
            bundle.add(ROOT / "docs/runtime-build.md", arcname="RuntimeSource/BUILD.md", filter=reproducible)
            info = tarfile.TarInfo("RuntimeSource/README.txt")
            info.size = len(readme)
            bundle.addfile(info, io.BytesIO(readme))
    print(f"Built {output.relative_to(ROOT)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    package(parser.parse_args().version)
