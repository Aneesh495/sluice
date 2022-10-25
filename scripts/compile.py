#!/usr/bin/env python3
"""Content-addressed compilation for macOS's timestamp-coarse system make.

Every object rule calls this helper. A matching command and source/header digest
reuses its object. Atomic publication keeps interrupted builds from validating a
partial object. Link steps always run, so same-second edits cannot leave a stale
executable. No Python packages are needed.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    output = Path(sys.argv[1])
    source = Path(sys.argv[2])
    command = sys.argv[3:]
    digest = hashlib.sha256(b"sluice.compile.v1\0")
    digest.update(json.dumps(command).encode())
    digest.update(source.read_bytes())
    for header in sorted(Path("Sources").rglob("*.h")):
        digest.update(str(header).encode())
        digest.update(header.read_bytes())
    for header in sorted(Path("Tests/Unit").glob("*.h")):
        digest.update(str(header).encode())
        digest.update(header.read_bytes())
    digest.update(subprocess.check_output(command[:2] + ["--version"]))
    signature = digest.hexdigest()
    marker = output.with_suffix(output.suffix + ".sha256")
    if output.is_file() and marker.is_file() and marker.read_text() == signature:
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as staging:
        temporary = Path(staging) / "object.o"
        subprocess.run([*command, "-c", str(source), "-o", str(temporary)], check=True)
        temporary.replace(output)
        staged_marker = Path(staging) / "signature"
        staged_marker.write_text(signature)
        staged_marker.replace(marker)


if __name__ == "__main__":
    main()
