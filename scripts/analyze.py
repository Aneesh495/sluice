#!/usr/bin/env python3
"""Run Clang's static analyzer and fail on diagnostic-bearing plist outputs."""
from pathlib import Path
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build/analyze"
OUTPUT.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
includes = ["-I" + str(path) for path in sorted((ROOT / "Sources").iterdir()) if path.is_dir()]
failed = []
for source in sorted((ROOT / "Sources").rglob("*.m")):
    destination = OUTPUT / (str(source.relative_to(ROOT)).replace("/", "_") + ".plist")
    command = ["xcrun", "clang", "--analyze", "-Xanalyzer", "-analyzer-output=plist", "-fobjc-arc", "-fobjc-arc-exceptions", "-fblocks", "-std=gnu11", "-Wall", "-Wextra", "-Wno-unused-parameter", "-isysroot", sdk, "-mmacosx-version-min=13.0", *includes, str(source), "-o", str(destination)]
    result = subprocess.run(command, cwd=ROOT)
    diagnostics = plistlib.loads(destination.read_bytes()).get("diagnostics", []) if destination.exists() else []
    if result.returncode or diagnostics:
        failed.append(str(source.relative_to(ROOT)))
    print(f"{source.relative_to(ROOT)}: {len(diagnostics)} diagnostics", flush=True)
print(f"Analyzed {len(list((ROOT / 'Sources').rglob('*.m')))} translation units; {len(failed)} failed")
sys.exit(bool(failed))
