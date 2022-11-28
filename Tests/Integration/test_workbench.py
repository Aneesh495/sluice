"""Independent clients exercise compiled Objective-C code over real TCP sockets.

No production parser, planner, redactor, or database reader is imported here.
Temporary workspaces remain below build/ and are removed after each test.
"""
from __future__ import annotations
import concurrent.futures
import contextlib
import http.client
import http.server
import json
import os
from pathlib import Path
import select
import signal
import socket
import sqlite3
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
BINARY = Path(os.environ.get("SLUICE_BINARY", ROOT / "build/sluice"))
PRIVACY = ROOT / "examples/privacy.json"


class Origin(http.server.BaseHTTPRequestHandler):
    serial = 0
    serial_lock = threading.Lock()
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        body = json.dumps({"ok": True, "path": self.path.split("?")[0], "token": "origin-secret"}, separators=(",", ":")).encode()
        if self.path.startswith("/changing"):
            with self.serial_lock:
                Origin.serial += 1
                serial = Origin.serial
            body = json.dumps({"revision": serial}).encode()
        if self.path.startswith("/binary"):
            body = bytes(range(256))
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream" if self.path.startswith("/binary") else "application/json")
        if self.path.startswith("/chunked"):
            self.send_header("Transfer-Encoding", "chunked")
        else:
            self.send_header("Content-Length", str(len(body)))
        self.send_header("Set-Cookie", "session=origin-secret")
        self.end_headers()
        if self.path.startswith("/chunked"):
            for at in range(0, len(body), 7):
                chunk = body[at:at+7]
                self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
            self.wfile.write(b"0\r\n\r\n")
        else:
            self.wfile.write(body)

    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Length", "123")
        self.end_headers()

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.send_response(201)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class Process:
    def __init__(self, mode, workspace, *options):
        self.proc = subprocess.Popen([str(BINARY), mode, "--workspace", str(workspace), "--port", "0", *map(str, options)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        ready, _, _ = select.select([self.proc.stdout], [], [], 5)
        if not ready:
            self.proc.kill()
            out, err = self.proc.communicate()
            raise AssertionError(f"No readiness event: {out} {err}")
        line = self.proc.stdout.readline()
        if not line:
            out, err = self.proc.communicate(timeout=5)
            raise AssertionError(f"Startup failed: {out} {err}")
        self.ready = json.loads(line)
        self.port = self.ready["port"]

    def stop(self):
        if self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
        out, err = self.proc.communicate(timeout=8)
        if self.proc.returncode:
            raise AssertionError(f"Process exited {self.proc.returncode}: {out} {err}")
        return out

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.stop()


def cli(*args, success=True):
    result = subprocess.run([str(BINARY), *map(str, args)], cwd=ROOT, capture_output=True, text=True, timeout=15)
    if success and result.returncode:
        raise AssertionError(result.stderr)
    return json.loads(result.stdout) if success else result


def request(port, target="/catalog", method="GET", body=None, headers=None, timeout=5):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        connection.request(method, target, body=body, headers=headers or {})
        response = connection.getresponse()
        return response.status, response.read(), dict(response.getheaders())
    finally:
        connection.close()


def raw_request(port, wire):
    with socket.create_connection(("127.0.0.1", port), timeout=5) as client:
        client.sendall(wire)
        result = bytearray()
        while data := client.recv(65536):
            result.extend(data)
        return bytes(result)


class WorkbenchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.origin = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Origin)
        cls.origin.daemon_threads = True
        cls.thread = threading.Thread(target=cls.origin.serve_forever, daemon=True)
        cls.thread.start()
        cls.upstream = f"http://127.0.0.1:{cls.origin.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.origin.shutdown()
        cls.origin.server_close()
        cls.thread.join()

    def setUp(self):
        (ROOT / "build/work").mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / "build/work")
        self.directory = Path(self.temp.name)
        self.workspace = self.directory / "workspace"

    def tearDown(self):
        self.temp.cleanup()

    def capture(self, target="/catalog", **kwargs):
        with Process("record", self.workspace, "--upstream", self.upstream, "--privacy", PRIVACY) as proxy:
            result = request(proxy.port, target, **kwargs)
        return result

    def scenario(self, action, **rule):
        path = self.directory / "scenario.json"
        document = {"version": 1, "name": "integration", "seed": 9, "rules": [{"id": "fault", "match": {}, "action": action, **rule}]}
        path.write_text(json.dumps(document))
        return path

    def fixtures(self):
        return cli("fixtures", "--workspace", self.workspace)

    def test_live_capture_offline_replay_and_receipts(self):
        status, body, _ = self.capture()
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["token"], "origin-secret")
        fixtures = self.fixtures()
        self.assertEqual(len(fixtures), 1)
        self.assertTrue(fixtures[0]["replayable"])
        with Process("replay", self.workspace, "--privacy", PRIVACY) as proxy:
            status, body, headers = request(proxy.port)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["token"], "[redacted]")
        self.assertEqual(headers["Connection"], "close")
        receipts = cli("receipts", "--workspace", self.workspace)
        self.assertEqual(len(receipts), 2)
        for receipt in receipts:
            self.assertEqual(receipt["outcome"], "complete")
            self.assertEqual(receipt["acceptedBytes"], receipt["plan"]["wireBytes"])
        self.assertEqual(cli("check", "--workspace", self.workspace)["fixtures"], 1)

    def test_real_truncation_keeps_original_content_length(self):
        self.capture()
        scenario = self.scenario({"truncateAfter": 7})
        with Process("replay", self.workspace, "--privacy", PRIVACY, "--scenario", scenario) as proxy:
            wire = raw_request(proxy.port, b"GET /catalog HTTP/1.1\r\nHost: test\r\n\r\n")
        head, body = wire.split(b"\r\n\r\n", 1)
        self.assertEqual(len(body), 7)
        length = int(next(x.split(b":", 1)[1] for x in head.split(b"\r\n") if x.lower().startswith(b"content-length:")))
        self.assertGreater(length, len(body))
        receipt = cli("receipts", "--workspace", self.workspace)[0]
        self.assertTrue(receipt["plan"]["truncated"])

    def test_paced_delivery_has_measurable_delay(self):
        self.capture()
        scenario = self.scenario({"delayMs": 60, "chunkBytes": 8, "bytesPerSecond": 80})
        with Process("replay", self.workspace, "--privacy", PRIVACY, "--scenario", scenario) as proxy:
            start = time.monotonic()
            status, body, _ = request(proxy.port)
            elapsed = time.monotonic() - start
        expected = 0.06 + ((len(body) - 1) // 8) * 8 / 80
        self.assertEqual(status, 200)
        self.assertGreaterEqual(elapsed, expected - 0.035)
        self.assertLess(elapsed, expected + 1.5)

    def test_first_occurrence_failure_then_success(self):
        self.capture()
        scenario = self.scenario({"status": 503, "bodyJSON": {"error": "retry"}}, limit=1)
        with Process("replay", self.workspace, "--privacy", PRIVACY, "--scenario", scenario) as proxy:
            self.assertEqual(request(proxy.port)[0], 503)
            self.assertEqual(request(proxy.port)[0], 200)
            self.assertEqual(request(proxy.port, "/unrecorded")[0], 409)

    def test_parallel_clients_keep_independent_valid_receipts(self):
        self.capture()
        with Process("replay", self.workspace, "--privacy", PRIVACY) as proxy:
            with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
                results = list(pool.map(lambda _: request(proxy.port)[0], range(80)))
        self.assertEqual(results, [200] * 80)
        receipts = [r for r in cli("receipts", "--workspace", self.workspace, "--limit", 100) if r["mode"] == "replay"]
        self.assertEqual(sorted(r["occurrence"] for r in receipts), list(range(1, 81)))

    def test_secrets_never_reach_database_or_wal(self):
        with Process("record", self.workspace, "--upstream", self.upstream, "--privacy", PRIVACY) as proxy:
            request(proxy.port, "/catalog?token=query-secret", headers={"Authorization": "Bearer header-secret", "Cookie": "cookie-secret"})
            request(proxy.port, "/echo", method="POST", body=b'{"password":"body-secret","id":2}', headers={"Content-Type": "application/json"})
            for path in self.workspace.iterdir():
                if path.is_file():
                    data = path.read_bytes()
                    for secret in (b"query-secret", b"header-secret", b"cookie-secret", b"body-secret", b"origin-secret"):
                        self.assertNotIn(secret, data, str(path))
        with Process("replay", self.workspace, "--privacy", PRIVACY) as proxy:
            status, body, _ = request(proxy.port, "/echo", method="POST", body=b'{"password":"different","id":2}', headers={"Content-Type": "application/json"})
        self.assertEqual(status, 201)
        self.assertEqual(json.loads(body)["password"], "[redacted]")

    def test_metadata_capture_is_not_silently_replayed(self):
        with Process("record", self.workspace, "--upstream", self.upstream) as proxy:
            self.assertEqual(request(proxy.port)[0], 200)
        self.assertFalse(self.fixtures()[0]["replayable"])
        with Process("replay", self.workspace) as proxy:
            status, body, _ = request(proxy.port)
        self.assertEqual(status, 409)
        self.assertEqual(json.loads(body)["error"], "replay.body")

    def test_ambiguous_fixtures_require_explicit_selection(self):
        self.capture("/changing")
        self.capture("/changing")
        fixtures = self.fixtures()
        self.assertEqual(len(fixtures), 2)
        with Process("replay", self.workspace, "--privacy", PRIVACY) as proxy:
            status, body, _ = request(proxy.port, "/changing")
        self.assertEqual(status, 409)
        self.assertEqual(json.loads(body)["error"], "replay.ambiguous")
        with Process("replay", self.workspace, "--privacy", PRIVACY, "--fixture", fixtures[0]["id"]) as proxy:
            self.assertEqual(request(proxy.port, "/changing")[0], 200)

    def test_smuggling_and_pipelining_are_rejected(self):
        with Process("record", self.workspace, "--upstream", self.upstream) as proxy:
            cases = [
                b"POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
                b"GET / HTTP/1.1\r\nHost: x\r\n\r\nGET /other HTTP/1.1\r\nHost: x\r\n\r\n",
            ]
            for wire in cases:
                response = raw_request(proxy.port, wire)
                self.assertTrue(response.startswith(b"HTTP/1.1 400"), response)

    def test_database_payload_tampering_is_detected(self):
        self.capture()
        with sqlite3.connect(self.workspace / "store.sqlite3") as connection:
            connection.execute("UPDATE fixtures SET payload=?", (b"{}",))
        result = cli("check", "--workspace", self.workspace, success=False)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stderr)["error"], "store.corrupt")

    def test_bundle_roundtrip_and_rejected_corruption_are_atomic(self):
        self.capture()
        bundle = self.directory / "fixtures.json"
        cli("export", "--workspace", self.workspace, "--output", bundle)
        imported = self.directory / "imported"
        cli("import", "--workspace", imported, "--input", bundle)
        with Process("replay", imported, "--privacy", PRIVACY) as proxy:
            self.assertEqual(request(proxy.port)[0], 200)
        document = json.loads(bundle.read_text())
        document["sha256"] = "0" * 64
        bundle.write_text(json.dumps(document))
        untouched = self.directory / "untouched"
        result = cli("import", "--workspace", untouched, "--input", bundle, success=False)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(cli("check", "--workspace", untouched)["fixtures"], 0)

    def test_committed_capture_survives_sigkill_and_wal_recovery(self):
        proxy = Process("record", self.workspace, "--upstream", self.upstream, "--privacy", PRIVACY)
        self.assertEqual(request(proxy.port)[0], 200)
        proxy.proc.kill()
        proxy.proc.communicate(timeout=5)
        self.assertEqual(proxy.proc.returncode, -signal.SIGKILL)
        self.assertEqual(cli("check", "--workspace", self.workspace)["fixtures"], 1)
        with Process("replay", self.workspace, "--privacy", PRIVACY) as replay:
            self.assertEqual(request(replay.port)[0], 200)

    def test_chunked_upstream_and_request_entities_are_normalized(self):
        self.capture("/chunked")
        with Process("replay", self.workspace, "--privacy", PRIVACY) as proxy:
            status, body, headers = request(proxy.port, "/chunked")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["token"], "[redacted]")
        self.assertNotIn("Transfer-Encoding", headers)
        wire = (b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n"
                b"7\r\n{\"n\":1}\r\n0\r\n\r\n")
        with Process("record", self.workspace, "--upstream", self.upstream, "--privacy", PRIVACY) as proxy:
            self.assertTrue(raw_request(proxy.port, wire).startswith(b"HTTP/1.1 201"))

    def test_head_representation_metadata_survives_offline_replay(self):
        status, body, headers = self.capture("/head", method="HEAD")
        self.assertEqual((status, body), (200, b""))
        self.assertEqual(headers["Content-Length"], "123")
        with Process("replay", self.workspace, "--privacy", PRIVACY) as proxy:
            status, body, headers = request(proxy.port, "/head", method="HEAD")
        self.assertEqual((status, body), (200, b""))
        self.assertEqual(headers["Content-Length"], "123")

    def test_client_write_half_close_still_receives_response(self):
        self.capture()
        with Process("replay", self.workspace, "--privacy", PRIVACY) as proxy:
            with socket.create_connection(("127.0.0.1", proxy.port), timeout=5) as client:
                client.sendall(b"GET /catalog HTTP/1.1\r\nHost: x\r\n\r\n")
                client.shutdown(socket.SHUT_WR)
                chunks = []
                while chunk := client.recv(65536):
                    chunks.append(chunk)
        self.assertTrue(b"".join(chunks).startswith(b"HTTP/1.1 200"))

    def test_delay_longer_than_backpressure_timeout_remains_valid(self):
        self.capture()
        scenario = self.scenario({"delayMs": 16000})
        with Process("replay", self.workspace, "--privacy", PRIVACY, "--scenario", scenario) as proxy:
            started = time.monotonic()
            status, _, _ = request(proxy.port, timeout=25)
            elapsed = time.monotonic() - started
        self.assertEqual(status, 200)
        self.assertGreaterEqual(elapsed, 15.9)

    def test_recorded_state_sequence_replays_without_variant_ambiguity(self):
        with Process("record", self.workspace, "--upstream", self.upstream, "--privacy", PRIVACY) as proxy:
            session = proxy.ready["session"]
            before = json.loads(request(proxy.port, "/changing")[1])
            after = json.loads(request(proxy.port, "/changing")[1])
        tape = self.directory / "sequence.json"
        cli("tape", "--workspace", self.workspace, "--session", session, "--output", tape)
        with Process("replay", self.workspace, "--privacy", PRIVACY, "--tape", tape) as replay:
            self.assertEqual(json.loads(request(replay.port, "/changing")[1]), before)
            self.assertEqual(json.loads(request(replay.port, "/changing")[1]), after)
            status, body, _ = request(replay.port, "/changing")
            self.assertEqual(status, 409)
            self.assertEqual(json.loads(body)["error"], "tape.exhausted")

    def test_cli_misspellings_and_invalid_schema_are_errors(self):
        result = cli("replay", "--workspce", self.workspace, success=False)
        self.assertEqual(result.returncode, 2)
        result = cli("validate", "--scenario", self.scenario({"delayMS": 10}), success=False)
        self.assertEqual(json.loads(result.stderr)["error"], "schema.unknown")


if __name__ == "__main__":
    unittest.main(verbosity=2)
