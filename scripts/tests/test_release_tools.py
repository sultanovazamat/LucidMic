"""Release regressions using disposable directories; never touches installed audio drivers."""

import hashlib
import importlib.util
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]


class RuntimeDigestTests(unittest.TestCase):
    def test_digest_does_not_require_python_311(self):
        spec = importlib.util.spec_from_file_location("runtime_sources", SCRIPTS / "package-runtime-sources.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        data = b"source archive\x00" * 100_000
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "source.tar.gz"
            archive.write_bytes(data)
            # Python 3.10 and earlier have no hashlib.file_digest.
            with patch.object(hashlib, "file_digest", create=True) as unsupported:
                unsupported.side_effect = AssertionError("hashlib.file_digest requires Python 3.11")
                self.assertEqual(module.digest(archive), hashlib.sha256(data).hexdigest())


class RuntimeCacheTests(unittest.TestCase):
    def test_cached_libraries_are_verified_against_pinned_hashes(self):
        for damaged in ("libsherpa-onnx-c-api.dylib", "libonnxruntime.dylib"):
            with self.subTest(library=damaged), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                script = (SCRIPTS / "fetch-deps.sh").read_text()
                archive_name = re.search(r'mv "\$DEPS/(sherpa-onnx-[^"]+)"', script).group(1)
                source = root / archive_name
                (source / "lib").mkdir(parents=True)
                header = source / "include/sherpa-onnx/c-api/c-api.h"
                header.parent.mkdir(parents=True)
                header.write_text("header")
                libraries = {"libsherpa-onnx-c-api.dylib": b"no-tts runtime", "libonnxruntime.dylib": b"onnx runtime"}
                for name, data in libraries.items():
                    (source / "lib" / name).write_bytes(data)
                archive = root / "runtime.tar.bz2"
                with tarfile.open(archive, "w:bz2") as bundle:
                    bundle.add(source, arcname=archive_name)
                archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
                model = b"model fixture"
                for name, value in {
                    "SHERPA_SHA": archive_hash,
                    "SHERPA_LIB_SHA": hashlib.sha256(libraries["libsherpa-onnx-c-api.dylib"]).hexdigest(),
                    "ONNX_LIB_SHA": hashlib.sha256(libraries["libonnxruntime.dylib"]).hexdigest(),
                    "MODEL_SHA": hashlib.sha256(model).hexdigest(),
                }.items():
                    script = re.sub(rf"^{name}=.*$", name + "=" + value, script, flags=re.MULTILINE)
                scripts = root / "scripts"
                scripts.mkdir()
                (scripts / "fetch-deps.sh").write_text(script)
                cache = root / "build/deps/sherpa"
                shutil.copytree(source, cache)
                (cache / (".verified-" + archive_hash)).touch()
                (cache / "lib" / damaged).write_bytes(b"wrong or corrupted variant")
                (root / "build/deps/dpdfnet2_48khz_hr.onnx").write_bytes(model)
                curl = scripts / "curl"
                curl.write_text(
                    f"#!{sys.executable}\n"
                    "import pathlib, shutil, sys\n"
                    "root = pathlib.Path(__file__).resolve().parent.parent\n"
                    "shutil.copyfile(root / 'runtime.tar.bz2', sys.argv[sys.argv.index('-o') + 1])\n"
                )
                curl.chmod(0o755)
                result = subprocess.run(
                    ["/bin/sh", str(scripts / "fetch-deps.sh")],
                    env={"PATH": str(scripts) + ":/usr/bin:/bin:/usr/sbin:/sbin"},
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((cache / "lib" / damaged).read_bytes(), libraries[damaged])


class DriverInstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lucidmic install test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.destination = self.root / "HAL"
        self.destination.mkdir()
        self.installed = self.destination / "LucidMic.driver"
        self.installed.mkdir()
        (self.installed / "old-driver").write_text("keep the previous driver")
        self.source = self.root / "source" / "LucidMic.driver"
        executable = self.source / "Contents" / "MacOS" / "BlackHole"
        executable.parent.mkdir(parents=True)
        executable.write_text("new driver")
        executable.chmod(0o755)
        self.info = self.source / "Contents" / "Info.plist"
        self.info.write_bytes(
            plistlib.dumps(
                {"CFBundleIdentifier": "com.sultanovazamat.lucidmic.driver", "CFBundleExecutable": "BlackHole"}
            )
        )
        self.log = self.root / "commands.log"
        self.failure = self.root / "failure"
        self.commands = self.root / "commands"
        self.commands.mkdir()
        shim = (
            f"#!{sys.executable}\n"
            + r"""
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
command = pathlib.Path(sys.argv[0]).name
arguments = sys.argv[1:]
with (root / "commands.log").open("a") as log:
    log.write(command + " " + repr(arguments) + "\n")
failure = (root / "failure").read_text() if (root / "failure").exists() else ""
if command == "id":
    print("0")
elif command == "codesign":
    if failure == "verify" or (failure == "stage-verify" and ".LucidMic-install." in arguments[-1]):
        sys.exit(1)
elif command in ("chown", "xattr", "killall"):
    if command == failure:
        sys.exit(1)
elif command == "cp":
    if failure == "copy":
        partial = pathlib.Path(arguments[-1])
        partial.mkdir()
        (partial / "incomplete").touch()
        sys.exit(1)
    sys.exit(subprocess.call(["/bin/cp"] + arguments))
elif command == "mv":
    source = pathlib.Path(arguments[-2])
    if failure == "promote" and ".LucidMic-install." in str(source) and source.name == "LucidMic.driver":
        sys.exit(1)
    sys.exit(subprocess.call(["/bin/mv"] + arguments))
else:
    raise AssertionError(command)
"""
        )
        for name in ("id", "codesign", "chown", "xattr", "killall", "cp", "mv"):
            command = self.commands / name
            command.write_text(shim)
            command.chmod(0o755)

        # Change only fixed locations/tool paths in a disposable copy. Production has
        # no environment-variable destination override that an elevated caller could abuse.
        script = (SCRIPTS / "install-driver.sh").read_text()
        script = script.replace("DST=/Library/Audio/Plug-Ins/HAL", "DST=" + shlex.quote(str(self.destination)))
        self.assertNotIn("/Library/Audio", script)
        for path in ("/usr/bin/id", "/usr/bin/codesign", "/usr/sbin/chown", "/usr/bin/xattr", "/usr/bin/killall"):
            script = script.replace(path, shlex.quote(str(self.commands / Path(path).name)))
        for path in ("/bin/cp", "/bin/mv"):
            script = script.replace(path, shlex.quote(str(self.commands / Path(path).name)))
        self.script = self.root / "install-driver.sh"
        self.script.write_text(script)

    def run_install(self, *arguments, failure=""):
        self.failure.write_text(failure)
        # PATH also redirects the original script's unqualified commands during
        # the regression's red phase; the fixed installer uses absolute paths.
        return subprocess.run(
            ["/bin/sh", str(self.script), *map(str, arguments)],
            env={"PATH": str(self.commands) + ":/usr/bin:/bin:/usr/sbin:/sbin"},
            text=True,
            capture_output=True,
            check=False,
        )

    def assert_old_driver_preserved(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.installed / "old-driver").is_file(), result.stdout + result.stderr)
        self.assertEqual(list(self.destination.iterdir()), [self.installed])
        self.assertNotIn("killall", self.log.read_text() if self.log.exists() else "")

    def test_missing_argument_preserves_existing_driver(self):
        self.assert_old_driver_preserved(self.run_install())

    def test_extra_argument_preserves_existing_driver(self):
        self.assert_old_driver_preserved(self.run_install(self.source, self.root / "other-destination"))

    def test_missing_source_preserves_existing_driver(self):
        self.assert_old_driver_preserved(self.run_install(self.root / "missing.driver"))

    def test_wrong_bundle_identifier_preserves_existing_driver(self):
        self.info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "wrong.driver", "CFBundleExecutable": "BlackHole"}))
        self.assert_old_driver_preserved(self.run_install(self.source))

    def test_wrong_executable_preserves_existing_driver(self):
        info = plistlib.loads(self.info.read_bytes())
        info["CFBundleExecutable"] = "other-program"
        self.info.write_bytes(plistlib.dumps(info))
        self.assert_old_driver_preserved(self.run_install(self.source))

    def test_symlink_in_bundle_is_rejected(self):
        (self.source / "Contents" / "outside").symlink_to(self.installed)
        self.assert_old_driver_preserved(self.run_install(self.source))

    def test_invalid_signature_preserves_existing_driver(self):
        self.assert_old_driver_preserved(self.run_install(self.source, failure="verify"))

    def test_partial_copy_failure_preserves_existing_driver(self):
        self.assert_old_driver_preserved(self.run_install(self.source, failure="copy"))

    def test_staged_verification_failure_preserves_existing_driver(self):
        self.assert_old_driver_preserved(self.run_install(self.source, failure="stage-verify"))

    def test_ownership_failure_preserves_existing_driver(self):
        self.assert_old_driver_preserved(self.run_install(self.source, failure="chown"))

    def test_promotion_failure_restores_existing_driver(self):
        self.assert_old_driver_preserved(self.run_install(self.source, failure="promote"))

    def test_success_replaces_driver_then_restarts_audio(self):
        result = self.run_install(self.source)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.installed / "old-driver").exists())
        self.assertEqual((self.installed / "Contents" / "MacOS" / "BlackHole").read_text(), "new driver")
        self.assertEqual(list(self.destination.iterdir()), [self.installed])
        commands = self.log.read_text().splitlines()
        self.assertTrue(commands[-1].startswith("killall "), commands)
        self.assertIn("root:wheel", self.log.read_text())

    def test_first_install_succeeds_with_world_readable_driver(self):
        (self.installed / "old-driver").unlink()
        self.installed.rmdir()
        result = self.run_install(self.source)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        executable = self.installed / "Contents" / "MacOS" / "BlackHole"
        self.assertEqual(executable.stat().st_mode & 0o7777, 0o755)
        self.assertEqual(self.installed.stat().st_mode & 0o7777, 0o755)
        self.assertEqual(list(self.destination.iterdir()), [self.installed])


if __name__ == "__main__":
    unittest.main()
