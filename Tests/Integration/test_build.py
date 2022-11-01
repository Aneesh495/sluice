"""Exercise content signatures independently of filesystem modification times."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BuildTests(unittest.TestCase):
    def test_same_timestamp_source_change_invalidates_object(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as folder:
            directory = Path(folder)
            source, output, executable = directory / "probe.m", directory / "probe.o", directory / "probe"
            source.write_text("int main(void) { return 3; }\n")
            original = source.stat()
            command = ["python3", "scripts/compile.py", str(output), str(source), "xcrun", "clang", "-x", "objective-c"]
            subprocess.run(command, cwd=ROOT, check=True)
            before = output.read_bytes()
            source.write_text("int main(void) { return 4; }\n")
            os.utime(source, ns=(original.st_atime_ns, original.st_mtime_ns))
            subprocess.run(command, cwd=ROOT, check=True)
            self.assertNotEqual(before, output.read_bytes())
            subprocess.run(["xcrun", "clang", str(output), "-o", str(executable)], check=True)
            self.assertEqual(subprocess.run([str(executable)]).returncode, 4)
            unchanged = output.stat().st_mtime_ns
            subprocess.run(command, cwd=ROOT, check=True)
            self.assertEqual(output.stat().st_mtime_ns, unchanged)


if __name__ == "__main__":
    unittest.main(verbosity=2)
