#!/usr/bin/env python3
"""Execute source-bound verification and preserve every gate's raw output."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_manifest():
    paths = [ROOT / name for name in ("Makefile", ".gitattributes", ".clang-format")]
    for directory in ("Sources", "Tests", "scripts", "examples"):
        paths.extend(path for path in (ROOT / directory).rglob("*") if path.is_file() and "__pycache__" not in path.parts)
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(paths)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/acceptance")
    parser.add_argument("--fuzz-runs", type=int, default=1000000)
    args = parser.parse_args()
    if args.fuzz_runs < 20000:
        parser.error("The full campaign requires at least 20000 fuzz runs")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    before = source_manifest()
    gates = [
        ("native", ["make", "all", "test", "app"]),
        ("integration", ["make", "integration"]),
        ("differential", ["make", "differential"]),
        ("build-cache", ["python3", "Tests/Integration/test_build.py"]),
        ("app", ["make", "app-smoke"]),
        ("analyzer", ["make", "analyze"]),
        ("sanitizers", ["make", "BUILD=build/sanitize", "EXTRA_FLAGS=-fsanitize=address,undefined -fno-omit-frame-pointer -O1", "test", "all", "integration"]),
        ("fuzz", ["make", "fuzz", f"FUZZ_RUNS={args.fuzz_runs}"]),
    ]
    report = {"version": 1, "platform": platform.platform(), "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "source": before, "gates": [], "fuzzRunsRequested": args.fuzz_runs}
    for name, command in gates:
        print(f"Running {name}", flush=True)
        started = time.monotonic()
        path = output / f"{name}.log"
        with path.open("wb") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        report["gates"].append({"name": name, "command": command, "returncode": result.returncode, "elapsedSeconds": round(time.monotonic()-started, 3), "log": path.name, "sha256": digest(path)})
        print(f"{name}: {'PASS' if result.returncode == 0 else 'FAIL'}", flush=True)
        # Preserve a complete partial report even if interrupted at the next gate.
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    report["sourceUnchanged"] = before == source_manifest()
    report["passed"] = report["sourceUnchanged"] and all(gate["returncode"] == 0 for gate in report["gates"])
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Evidence: {output / 'report.json'}", flush=True)
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
