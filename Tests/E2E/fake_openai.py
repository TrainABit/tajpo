#!/usr/bin/env python3
"""Small OpenAI-compatible server used only by the local E2E test.

The server binds to loopback, can write its actual port for a dynamic-port
runner, and fails requests that carry an unexpected credential or endpoint.
It never handles real API keys.
"""
from __future__ import annotations

import json
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN_HOST = "127.0.0.1"
LOG = sys.argv[2] if len(sys.argv) > 2 else "requests.log"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 0
PORT_FILE = sys.argv[3] if len(sys.argv) > 3 else ""


def edited(user_message: str) -> str:
    match = re.search(r"<(text[0-9A-Za-z_]*)>\n(.*)\n</\1>", user_message, re.S)
    text = match.group(2) if match else user_message
    return text.replace("teh", "the")


class Handler(BaseHTTPRequestHandler):
    server_version = "TajpoE2E/1"

    def _json(self, payload: dict) -> bytes:
        return json.dumps(payload).encode("utf-8")

    def _send(self, status: int, payload: bytes, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send(200, b'{"ok":true}')
        else:
            self._send(404, b'{"error":"not found"}')

    def do_POST(self) -> None:
        if self.path != "/v1/chat/completions":
            self._send(404, b'{"error":"unexpected endpoint"}')
            return
        if self.headers.get("Authorization"):
            self._send(400, b'{"error":"credential was forwarded to the test server"}')
            return

        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 1_000_000:
            self._send(413, b'{"error":"invalid request size"}')
            return
        try:
            body = json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            self._send(400, b'{"error":"invalid json"}')
            return
        with open(LOG, "a", encoding="utf-8") as log:
            log.write(json.dumps(body, ensure_ascii=False) + "\n")

        user = next((m["content"] for m in body.get("messages", []) if m.get("role") == "user"), "")
        result = edited(user)
        if not body.get("stream"):
            payload = {
                "choices": [{"message": {"role": "assistant", "content": "OK"}, "finish_reason": "stop"}]
            }
            self._send(200, self._json(payload))
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        third = max(1, len(result) // 3)
        for piece in (result[:third], result[third:2 * third], result[2 * third:]):
            chunk = {"choices": [{"delta": {"content": piece}, "finish_reason": None}]}
            self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode("utf-8"))
            self.wfile.flush()
        done = {"choices": [{"delta": {}, "finish_reason": "stop"}]}
        self.wfile.write(f"data: {json.dumps(done)}\n\ndata: [DONE]\n\n".encode("utf-8"))
        self.wfile.flush()

    def log_message(self, *_args: object) -> None:
        pass


if __name__ == "__main__":
    server = ThreadingHTTPServer((LISTEN_HOST, PORT), Handler)
    if PORT_FILE:
        with open(PORT_FILE, "w", encoding="utf-8") as port_file:
            port_file.write(str(server.server_port))
    print(server.server_port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
