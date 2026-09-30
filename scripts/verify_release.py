"""Validate the actual app bundle before a DMG is distributed."""

import argparse
import json
import plistlib
import subprocess
from pathlib import Path


def verify(app: Path, version: str) -> None:
    contents = app / "Contents"
    with (contents / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    expected = {
        "CFBundleIdentifier": "com.sultanovazamat.lucidmic",
        "CFBundleName": "LucidMic",
        "CFBundleExecutable": "LucidMic",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "CFBundleIconFile": "AppIcon",
        "CFBundlePackageType": "APPL",
        "LSMinimumSystemVersion": "14.0",
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise SystemExit(f"{key}: expected {value!r}, got {info.get(key)!r}")
    resources = [
        "AppIcon.icns",
        "dpdfnet2_48khz_hr.onnx",
        "THIRD_PARTY_NOTICES.txt",
        "LICENSE",
        "Runtime-Sources.json",
        "Licenses/BlackHole-GPL-3.0.txt",
        "Licenses/DPDFNet-Apache-2.0.txt",
        "Licenses/sherpa-onnx-Apache-2.0.txt",
        "Licenses/onnxruntime-MIT.txt",
        "Licenses/onnxruntime-ThirdPartyNotices.txt",
        "install-driver.sh",
        "uninstall-driver.sh",
        "LucidMic.driver/Contents/MacOS/BlackHole",
    ]
    for name in resources:
        path = contents / "Resources" / name
        if not path.is_file() or not path.stat().st_size:
            raise SystemExit(f"Missing or empty resource: {name}")
    manifest = json.loads((contents / "Resources/Runtime-Sources.json").read_text())
    for entry in manifest:
        for name in entry["license_files"]:
            path = contents / "Resources/Licenses" / Path(name).name
            if not path.is_file() or not path.stat().st_size:
                raise SystemExit(f"Missing runtime license: {name}")
    binaries = [contents / "MacOS/LucidMic"] + [
        contents / "Frameworks" / name for name in ("libsherpa-onnx-c-api.dylib", "libonnxruntime.dylib")
    ]
    binaries.append(contents / "Resources/LucidMic.driver/Contents/MacOS/BlackHole")
    for binary in binaries:
        subprocess.run(["lipo", str(binary), "-verify_arch", "arm64"], check=True)
        linked = "\n".join(subprocess.check_output(["otool", "-L", str(binary)], text=True).splitlines()[1:])
        if "/build/" in linked or "/Users/" in linked or "/private/tmp/" in linked:
            raise SystemExit(f"Development library path in {binary}")
    load_commands = "\n".join(subprocess.check_output(["otool", "-l", str(binaries[0])], text=True).splitlines()[1:])
    if "/build/" in load_commands or "/Users/" in load_commands or "/private/tmp/" in load_commands:
        raise SystemExit("Development path in executable load commands")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    print(f"Verified {app}: LucidMic {version}, arm64, resources, library paths, signature")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("version")
    args = parser.parse_args()
    verify(args.app, args.version)
