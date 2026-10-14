#!/usr/bin/env python3
"""G1 factory-Watcher HTTP event shape receiver (no device writes, no raw payload retention).

The Seeed Node-RED reference uses POST /v1/notification/event and HTTP 200.
This receives *untrusted* network events and NEVER feeds the Autonomous Core.
"""
from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
from urllib.parse import urlsplit


EVENT_PATH = "/v1/notification/event"
MAX_BYTES = 4 * 1024 * 1024
LAN_NETWORKS = tuple(ipaddress.ip_network(x) for x in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"
))


def require_lan_ip(text: str) -> str:
    """Never bind the experimental unauthenticated receiver to a public/wildcard IP."""
    ip = ipaddress.IPv4Address(text)
    if not any(ip in network for network in LAN_NETWORKS):
        raise ValueError("Use the Windows PC's private LAN IPv4, not 0.0.0.0/localhost/public IP")
    return str(ip)


def shape(value, depth: int = 0):
    """Return field names and types ONLY; deliberately omit all content/values."""
    if depth >= 6:
        return {"type": "depth_limit"}
    if isinstance(value, dict):
        result = {}
        for key, child in list(value.items())[:50]:
            name = str(key)
            if any(secret in name.lower() for secret in (
                "password", "token", "secret", "api_key", "authorization", "credential"
            )):
                name = "<sensitive_key>"
            result[name] = shape(child, depth + 1)
        if len(value) > 50:
            result["<additional_keys>"] = len(value) - 50
        return {"type": "object", "fields": result}
    if isinstance(value, list):
        return {"type": "array", "length": len(value),
                "sample": shape(value[0], depth + 1) if value else None}
    if isinstance(value, str):
        return {"type": "string", "length": len(value)}
    if isinstance(value, bool):
        return {"type": "boolean"}
    if value is None:
        return {"type": "null"}
    if isinstance(value, (int, float)):
        return {"type": "number"}
    return {"type": "other"}


def make_handler(output_path: Path):
    lock = Lock()

    class WatcherHandler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass  # Never print raw request headers/paths, which might contain secrets.

        def reply(self, code: int, message: dict):
            payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self):
            if urlsplit(self.path).path == "/health":
                self.reply(200, {"status": "ready"})
            else:
                self.reply(404, {"error": "not_found"})

        def do_POST(self):
            if urlsplit(self.path).path != EVENT_PATH:
                self.reply(404, {"error": "not_found"})
                return
            raw_length = self.headers.get("Content-Length")
            try:
                n = int(raw_length) if raw_length is not None else -1
            except ValueError:
                n = -1
            if n < 0:
                self.reply(411, {"error": "content_length_required"})
                return
            if n > MAX_BYTES:
                self.reply(413, {"error": "payload_too_large"})
                return

            body = self.rfile.read(n)
            try:
                decoded = json.loads(body)
                body_shape = shape(decoded)
            except (ValueError, UnicodeDecodeError):
                body_shape = {"type": "non_json_or_invalid_json"}

            record = {
                "received_utc": datetime.now(timezone.utc).isoformat(),
                "sender_ip": self.client_address[0],
                "bytes": len(body),
                "content_type": self.headers.get("Content-Type", "")[:100],
                "payload_sha256_16": hashlib.sha256(body).hexdigest()[:16],
                "shape": body_shape,
            }
            line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
            with lock:
                with output_path.open("a", encoding="utf-8") as f:
                    f.write(line + "\n")
                print(line, flush=True)
            self.reply(200, {"code": 200, "msg": "ok", "data": {}})

    return WatcherHandler


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--bind", required=True, type=require_lan_ip,
                   help="The Windows PC's RFC1918 LAN IPv4 address (from ipconfig)")
    p.add_argument("--port", type=int, default=1880)
    p.add_argument("--output", required=True, type=Path,
                   help="Local JSONL file containing SCHEMA ONLY, not images or values")
    args = p.parse_args()
    if not 1024 <= args.port <= 65535:
        p.error("Port must be in the range 1024..65535")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((args.bind, args.port), make_handler(args.output))
    print("G1 schema-only HTTP listener: http://{}:{}{}".format(
        args.bind, args.port, EVENT_PATH), flush=True)
    print("No raw body/image is saved. This is unauthenticated LAN input; do not expose to the Internet.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
