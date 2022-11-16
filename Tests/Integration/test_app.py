"""Native window rendering and stop-before-reactor-publication lifecycle check."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "build/Sluice.app/Contents/MacOS/Sluice"


class AppTests(unittest.TestCase):
    def test_background_window_rendering_and_start_stop_lifecycle(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as folder:
            directory = Path(folder)
            image = directory / "app.png"
            result = subprocess.run([str(APP), "--workspace", str(directory / "workspace"), "--snapshot", str(image), "--smoke"], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('"appSmoke":true', result.stdout)
            self.assertTrue(image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"))
            result = subprocess.run([str(APP), "--workspace", str(directory / "workspace"), "--exercise"], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('"appSmoke":true', result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
