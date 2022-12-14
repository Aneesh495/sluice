#!/usr/bin/env python3
"""A complete local outage rehearsal. No internet or third-party packages."""
from __future__ import annotations
import argparse
import http.client
import http.server
import json
from pathlib import Path
import select
import signal
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "build/sluice"


class Dependency(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        documents = {
            "/catalog": {"items": [{"sku": "notebook", "available": 14}, {"sku": "pencil", "available": 80}], "currency": "USD"},
            "/inventory": {"warehouse": "west", "stock": 94, "updated": "2026-10-18T12:00:00Z"},
            "/profile": {"name": "Demo account", "email": "private@example.test", "token": "never-store-this"},
            "/cart": {"items": 2, "subtotal": 2400, "currency": "USD"},
            "/checkout": {"order": "demo-1042", "state": "ready", "payment": "test-only"},
            "/health": {"ready": True, "dependencies": 3},
        }
        body = json.dumps(documents.get(self.path, {"error": "missing"}), separators=(",", ":")).encode()
        self.send_response(200 if self.path in documents else 404)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Demo", "synthetic-local-data")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class Listener:
    def __init__(self, mode, workspace, *options):
        self.process = subprocess.Popen([str(BINARY), mode, "--workspace", str(workspace), "--port", "0", "--privacy", str(ROOT / "examples/privacy.json"), *map(str, options)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if not select.select([self.process.stdout], [], [], 8)[0]:
            self.process.kill()
            raise RuntimeError("Listener did not become ready")
        line = self.process.stdout.readline()
        if not line:
            _, error = self.process.communicate(timeout=5)
            raise RuntimeError(error)
        self.port = json.loads(line)["port"]

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.process.send_signal(signal.SIGTERM)
        output, error = self.process.communicate(timeout=8)
        if self.process.returncode:
            raise RuntimeError(f"Listener failed: {output} {error}")


def get(port, target):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        connection.request("GET", target)
        response = connection.getresponse()
        return response.status, json.loads(response.read())
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path)
    args = parser.parse_args()
    if args.workspace:
        workspace = args.workspace.resolve()
        workspace.mkdir(parents=True, exist_ok=False)
    else:
        (ROOT / "work").mkdir(exist_ok=True)
        workspace = Path(tempfile.mkdtemp(prefix="demo-", dir=ROOT / "work"))
    origin = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Dependency)
    origin.daemon_threads = True
    thread = threading.Thread(target=origin.serve_forever, daemon=True)
    thread.start()
    try:
        with Listener("record", workspace, "--upstream", f"http://127.0.0.1:{origin.server_port}") as listener:
            for target in ("/catalog", "/inventory", "/profile", "/cart", "/checkout", "/health"):
                status, _ = get(listener.port, target)
                if status != 200:
                    raise RuntimeError("Dependency capture failed")
    finally:
        origin.shutdown()
        origin.server_close()
        thread.join()
    # The real origin has been closed before any replay request is issued.
    with Listener("replay", workspace, "--scenario", ROOT / "examples/outage.json") as listener:
        first, unavailable = get(listener.port, "/catalog")
        second, available = get(listener.port, "/catalog")
        _, profile = get(listener.port, "/profile")
    if (first, second) != (503, 200) or profile["token"] != "[redacted]":
        raise RuntimeError("Offline outage rehearsal did not match its contract")
    report = subprocess.check_output([str(BINARY), "report", "--workspace", str(workspace)], text=True)
    print(json.dumps({"workspace": str(workspace), "originStoppedBeforeReplay": True, "observedStatus": [first, second], "firstResponse": unavailable, "recoveredItems": len(available["items"]), "report": json.loads(report)}, indent=2))
    print(f'\nInspect it: build/Sluice.app/Contents/MacOS/Sluice --workspace "{workspace}" --privacy examples/privacy.json --scenario examples/outage.json')


if __name__ == "__main__":
    main()
