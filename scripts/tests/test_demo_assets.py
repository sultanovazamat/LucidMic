"""Keep the public listening examples complete and tied to their source recordings."""

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEMO = ROOT / "docs/demo"


class DemoAssetsTests(unittest.TestCase):
    def verify(self, directory):
        return subprocess.run(
            [sys.executable, str(ROOT / "scripts/prepare-demo.py"), "--verify", "--directory", str(directory)],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_checked_in_pairs_match_sources_and_preserve_duration(self):
        result = self.verify(DEMO)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_changed_original_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "demo"
            shutil.copytree(DEMO, directory)
            original = directory / "audio/typing-original.wav"
            data = bytearray(original.read_bytes())
            data[-2] ^= 1
            original.write_bytes(data)
            result = self.verify(directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("SHA-256", result.stderr)

    def test_truncated_output_is_rejected_even_with_updated_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "demo"
            shutil.copytree(DEMO, directory)
            output = directory / "audio/typing-lucidmic.wav"
            with wave.open(str(output), "rb") as audio:
                parameters = audio.getparams()
                frames = audio.readframes(audio.getnframes() // 2)
            with wave.open(str(output), "wb") as audio:
                audio.setparams(parameters)
                audio.writeframes(frames)
            manifest_path = directory / "manifest.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["samples"][0]["processed_sha256"] = hashlib.sha256(output.read_bytes()).hexdigest()
            manifest_path.write_text(json.dumps(manifest))
            result = self.verify(directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("duration", result.stderr)

    def test_stale_measurement_report_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "demo"
            shutil.copytree(DEMO, directory)
            report_path = directory / "verification.json"
            report = json.loads(report_path.read_text())
            report[2]["lucidmic"]["clipped_samples"] = 0
            report_path.write_text(json.dumps(report))
            result = self.verify(directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("report", result.stderr)
