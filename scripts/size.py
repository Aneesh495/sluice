#!/usr/bin/env python3
"""Physical source accounting with string-aware C/Objective-C comment removal."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]


def stripped(text):
    result = []
    state, escaped, at = "code", False, 0
    while at < len(text):
        char = text[at]
        following = text[at+1] if at+1 < len(text) else ""
        if state == "line":
            result.append("\n" if char == "\n" else " ")
            if char == "\n":
                state = "code"
        elif state == "block":
            if char == "*" and following == "/":
                result.extend("  ")
                at += 1
                state = "code"
            else:
                result.append("\n" if char == "\n" else " ")
        elif state in ("string", "character"):
            result.append(char)
            if not escaped and char == ("\"" if state == "string" else "'"):
                state = "code"
            if not escaped and char == "\\":
                escaped = True
            else:
                escaped = False
        elif char == "/" and following in ("/", "*"):
            state = "line" if following == "/" else "block"
            result.extend("  ")
            at += 1
        else:
            result.append(char)
            if char in ("\"", "'"):
                state = "string" if char == "\"" else "character"
        at += 1
    return "".join(result)


def count(paths, objc=False):
    result = {"files": 0, "physical": 0, "code": 0, "commentsOnly": 0, "blank": 0}
    for path in paths:
        original = path.read_text().splitlines()
        cleaned = stripped(path.read_text()).splitlines() if objc else original
        result["files"] += 1
        for raw, code in zip(original, cleaned):
            result["physical"] += 1
            if not raw.strip():
                result["blank"] += 1
            elif (not code.strip()) if objc else raw.lstrip().startswith("#"):
                result["commentsOnly"] += 1
            else:
                result["code"] += 1
    return result


def sizes():
    production = sorted(path for path in (ROOT / "Sources").rglob("*") if path.suffix in (".m", ".h"))
    tests = sorted(path for path in (ROOT / "Tests").rglob("*") if path.suffix in (".m", ".h"))
    glue = sorted(path for directory in ("scripts", "Tests") for path in (ROOT / directory).rglob("*.py"))
    docs = [ROOT / "README.md", *sorted((ROOT / "docs").rglob("*.md"))]
    return {"objectiveCProductionIncludingHeaders": count(production, True), "objectiveCTestsIncludingHeaders": count(tests, True), "pythonGlueAndTests": count(glue), "documentationLines": sum(len(path.read_text().splitlines()) for path in docs)}


if __name__ == "__main__":
    print(json.dumps(sizes(), indent=2))
