#!/usr/bin/env python3
"""Validate preserved logs against the current source and required gate set."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = {"native", "integration", "differential", "build-cache", "app", "analyzer", "sanitizers", "fuzz", "coverage"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(path):
    report = json.loads(path.read_text())
    if report.get("version") != 1 or not report.get("passed") or not report.get("sourceUnchanged"):
        raise ValueError("Report is incomplete or contains failed gates")
    gates = report.get("gates", [])
    if len(gates) != len(REQUIRED) or {gate["name"] for gate in gates} != REQUIRED:
        raise ValueError("Required gate set is missing or duplicated")
    if report.get("fuzzRunsRequested", 0) < 20000:
        raise ValueError("Fuzz campaign is below the verification minimum")
    for gate in gates:
        log = (path.parent / gate["log"]).resolve()
        if not log.is_relative_to(path.parent.resolve()) or gate["returncode"] != 0 or sha(log) != gate["sha256"]:
            raise ValueError(f"Invalid gate log: {gate['name']}")
    actual = {}
    for name in ("Makefile", ".gitattributes", ".clang-format"):
        actual[name] = sha(ROOT / name)
    for folder in ("Sources", "Tests", "scripts", "examples"):
        for source in (ROOT / folder).rglob("*"):
            if source.is_file() and "__pycache__" not in source.parts:
                actual[str(source.relative_to(ROOT))] = sha(source)
    if actual != report.get("source"):
        raise ValueError("Source manifest is stale, incomplete, or altered")
    return {"verified": True, "gates": len(gates), "sourceFiles": len(actual), "fuzzRunsRequested": report["fuzzRunsRequested"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.report)))
    except (ValueError, KeyError, OSError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
