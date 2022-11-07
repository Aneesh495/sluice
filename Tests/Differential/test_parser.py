"""Compare positive HTTP response semantics against Python's independent parser."""
import base64
import hashlib
import http.client
import io
import json
from pathlib import Path
import random
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class FakeSocket:
    def __init__(self, data):
        self.data = data

    def makefile(self, *_):
        return io.BytesIO(self.data)


class DifferentialTests(unittest.TestCase):
    def test_generated_response_semantics(self):
        randomizer = random.Random(41501)
        cases, expected = [], []
        for index in range(1200):
            body = randomizer.randbytes(randomizer.randrange(0, 1024))
            status = randomizer.choice([200, 201, 400, 404, 429, 500, 503])
            framing = index % 3
            head = f"HTTP/1.1 {status} Test\r\nX-Case: {index}\r\n".encode()
            if framing == 0:
                wire = head + f"Content-Length: {len(body)}\r\n\r\n".encode() + body
            elif framing == 1:
                chunks = [body[i:i+17] for i in range(0, len(body), 17)]
                wire = head + b"Transfer-Encoding: chunked\r\n\r\n" + b"".join(f"{len(chunk):X}\r\n".encode() + chunk + b"\r\n" for chunk in chunks) + b"0\r\n\r\n"
            else:
                wire = head + b"Connection: close\r\n\r\n" + body
            reference = http.client.HTTPResponse(FakeSocket(wire))
            reference.begin()
            decoded = reference.read()
            expected.append((reference.status, len(decoded), hashlib.sha256(decoded).hexdigest()))
            cases.append({"wire": base64.b64encode(wire).decode(), "request": False, "head": False, "stride": randomizer.randrange(1, 65)})
        output = subprocess.check_output([str(ROOT / "build/parser-driver")], input=json.dumps(cases).encode(), timeout=30)
        results = json.loads(output)
        self.assertEqual(len(results), len(expected))
        for index, (result, reference) in enumerate(zip(results, expected)):
            self.assertTrue(result["accepted"], (index, result))
            self.assertEqual((result["status"], result["bodyBytes"], result["bodySHA256"]), reference, index)


if __name__ == "__main__":
    unittest.main(verbosity=2)
