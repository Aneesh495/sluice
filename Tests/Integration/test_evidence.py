"""Negative controls for a completed, source-bound verification report."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
REPORT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build/acceptance/report.json"
sys.argv = sys.argv[:1]


class EvidenceTests(unittest.TestCase):
    def test_log_manifest_and_gate_tampering_are_rejected(self):
        command = ["python3", str(ROOT / "scripts/verify_evidence.py")]
        baseline = subprocess.run([*command, str(REPORT)], cwd=ROOT, capture_output=True)
        self.assertEqual(baseline.returncode, 0, baseline.stderr)
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as folder:
            destination = Path(folder) / "evidence"
            shutil.copytree(REPORT.parent, destination)
            path = destination / REPORT.name
            original = path.read_text()
            document = json.loads(original)
            log = destination / document["gates"][0]["log"]
            original_log = log.read_bytes()
            log.write_bytes(original_log + b"\naltered\n")
            self.assertNotEqual(subprocess.run([*command, str(path)], capture_output=True).returncode, 0)
            log.write_bytes(original_log)
            document["gates"].pop()
            path.write_text(json.dumps(document))
            self.assertNotEqual(subprocess.run([*command, str(path)], capture_output=True).returncode, 0)
            document = json.loads(original)
            document["source"]["Makefile"] = "0" * 64
            path.write_text(json.dumps(document))
            self.assertNotEqual(subprocess.run([*command, str(path)], capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
