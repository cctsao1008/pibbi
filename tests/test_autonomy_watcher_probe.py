"""Host-only G1 HTTP probe tests; local loopback only, no Watcher required."""
import http.client
import json
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools" / "autonomy"))
from watcher_http_probe import EVENT_PATH, MAX_BYTES, make_handler, require_lan_ip, shape


class WatcherProbeTests(unittest.TestCase):
    def test_field_schema_never_reveals_values(self):
        s = json.dumps(shape({"events": {"text": "Private person detected",
                                        "image": "super-secret-b64"},
                              "access_token": "SECRET"}))
        self.assertIn("events", s)
        self.assertIn("<sensitive_key>", s)
        self.assertNotIn("Private person detected", s)
        self.assertNotIn("super-secret-b64", s)
        self.assertNotIn("SECRET", s)

    def test_bind_must_be_private_lan_address(self):
        self.assertEqual(require_lan_ip("192.168.1.20"), "192.168.1.20")
        with self.assertRaises(ValueError):
            require_lan_ip("0.0.0.0")
        with self.assertRaises(ValueError):
            require_lan_ip("8.8.8.8")
        with self.assertRaises(ValueError):
            require_lan_ip("127.0.0.1")

    def test_http_post_ack_and_structure_only_logging(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "shapes.jsonl"
            server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(path))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                client = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=3)
                content = json.dumps({"events": {"text": "Very private", "image": "base64blob"}})
                client.request("POST", EVENT_PATH, body=content,
                               headers={"Content-Type": "application/json"})
                response = client.getresponse()
                self.assertEqual(response.status, 200)
                self.assertEqual(json.loads(response.read())["code"], 200)
                client.close()
                rows = path.read_text(encoding="utf-8").splitlines()
                self.assertEqual(len(rows), 1)
                self.assertEqual(json.loads(rows[0])["shape"]["type"], "object")
                self.assertNotIn("Very private", rows[0])
                self.assertNotIn("base64blob", rows[0])
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=3)

    def test_large_http_post_rejected_without_body_log(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "shapes.jsonl"
            server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(path))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                client = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=3)
                client.putrequest("POST", EVENT_PATH)
                client.putheader("Content-Length", str(MAX_BYTES + 1))
                client.endheaders()
                response = client.getresponse()
                self.assertEqual(response.status, 413)
                response.read()
                client.close()
                self.assertFalse(path.exists())
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
