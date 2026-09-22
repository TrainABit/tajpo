#!/usr/bin/env python3
"""A minimal OpenAI-compatible Chat Completions server for end-to-end tests.

It "corrects" the text inside the <text> tags by replacing "teh" with "the",
streams the result as server-sent events, and logs each request to
requests.log so the test can check what Tajpo sent.
"""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = sys.argv[2] if len(sys.argv) > 2 else "requests.log"


def edited(user_message: str) -> str:
    match = re.search(r"<(text\d*)>\n(.*)\n</\1>", user_message, re.S)
    text = match.group(2) if match else user_message
    return text.replace("teh", "the")


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        with open(LOG, "a") as log:
            log.write(json.dumps(body) + "\n")
        user = next((m["content"] for m in body["messages"] if m["role"] == "user"), "")
        result = edited(user)
        if not body.get("stream"):
            payload = {"choices": [{"message": {"role": "assistant", "content": "OK"}, "finish_reason": "stop"}]}
            data = json.dumps(payload).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        third = max(1, len(result) // 3)
        for piece in (result[:third], result[third:2 * third], result[2 * third:]):
            chunk = {"choices": [{"delta": {"content": piece}, "finish_reason": None}]}
            self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
            self.wfile.flush()
        done = {"choices": [{"delta": {}, "finish_reason": "stop"}]}
        self.wfile.write(f"data: {json.dumps(done)}\n\ndata: [DONE]\n\n".encode())
        self.wfile.flush()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
