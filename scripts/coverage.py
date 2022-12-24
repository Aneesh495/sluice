#!/usr/bin/env python3
"""Measure source coverage from native unit, socket integration, and app runs."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build/coverage"
PROFILES = OUTPUT / "profiles"
PROFILES.mkdir(parents=True, exist_ok=True)
for profile in PROFILES.glob("*.profraw"):
    profile.unlink()
environment = {**os.environ, "LLVM_PROFILE_FILE": str(PROFILES / "%p.profraw")}
flags = "-fprofile-instr-generate -fcoverage-mapping -O0"
subprocess.run(["make", "BUILD=build/coverage", f"EXTRA_FLAGS={flags}", "test", "all", "integration", "app"], cwd=ROOT, env=environment, check=True)
subprocess.run([str(OUTPUT / "Sluice.app/Contents/MacOS/Sluice"), "--workspace", str(OUTPUT / "app-workspace"), "--exercise"], cwd=ROOT, env=environment, check=True, timeout=15)
profiles = sorted(PROFILES.glob("*.profraw"))
if not profiles:
    raise SystemExit("No instrumented execution profiles were produced")
merged = OUTPUT / "merged.profdata"
subprocess.run(["xcrun", "llvm-profdata", "merge", "-sparse", *map(str, profiles), "-o", str(merged)], check=True)
objects = [str(OUTPUT / "unit"), "-object", str(OUTPUT / "sluice"), "-object", str(OUTPUT / "Sluice.app/Contents/MacOS/Sluice"), f"-instr-profile={merged}"]
raw = subprocess.check_output(["xcrun", "llvm-cov", "export", *objects, "-summary-only"], cwd=ROOT)
document = json.loads(raw)
files = []
for group in document["data"]:
    for item in group["files"]:
        filename = Path(item["filename"])
        if filename.is_relative_to(ROOT / "Sources"):
            files.append({"file": str(filename.relative_to(ROOT)), "summary": item["summary"]})
if not files:
    raise SystemExit("No production source coverage records were found")
summary = {"version": 1, "profiles": len(profiles), "files": files}
for section in ("core", "app", "all"):
    selected = [entry for entry in files if section == "all" or (("/App/" in entry["file"]) == (section == "app"))]
    count = sum(entry["summary"]["lines"]["count"] for entry in selected)
    covered = sum(entry["summary"]["lines"]["covered"] for entry in selected)
    summary[section] = {"lines": count, "covered": covered, "percent": round(100*covered/count, 2) if count else 0}
(OUTPUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
report = subprocess.check_output(["xcrun", "llvm-cov", "report", *objects, "-ignore-filename-regex=Tests/|/SDKs/"], cwd=ROOT, text=True)
(OUTPUT / "report.txt").write_text(report.replace(str(ROOT) + "/", ""))
print(json.dumps({key: summary[key] for key in ("profiles", "core", "app", "all")}, indent=2))
