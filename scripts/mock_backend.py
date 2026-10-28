#!/usr/bin/env python3
"""Local, deterministic transport fixture. This is not a language model.

Run: python3 scripts/mock_backend.py
Base URL: http://127.0.0.1:8765/v1 ; model: mock-editor ; key: local-test
Error fixtures: /auth/v1, /rate/v1, /model/v1, /server/v1, /timeout/v1,
/malformed/v1, /truncated/v1, /redirect/v1. No requests or credentials are logged.
"""

import argparse
import json
from pathlib import Path
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def edit_sample(text, instruction):
    # A handful of deterministic examples for exercising previews and replacement.
    # Every unmatched passage is returned unchanged; this is deliberately not a model.
    result = text
    corrections = {
        r"\bThis are\b": "This is",
        r"\ba example\b": "an example",
        r"\bI has\b": "I have",
        r"\bWe was\b": "We were",
        r"\bteh\b": "the",
        r"\brecieve\b": "receive",
        r"\brecieved\b": "received",
        r"\bpleese\b": "please",
        r"\btommorow\b": "tomorrow",
        r"\bHelo\b": "Hello",
    }
    for pattern, replacement in corrections.items():
        result = re.sub(pattern, replacement, result)
    if "more concisely" in instruction:
        result = result.replace("at this point in time", "now").replace("in order to", "to")
    if "improve clarity" in instruction:
        result = result.replace("due to the fact that", "because")
    if "professional tone" in instruction:
        result = result.replace("Hey team", "Hello team").replace("ASAP", "as soon as possible")
    if "conversational tone" in instruction:
        result = result.replace("Dear team", "Hi team").replace("I would like to", "I'd like to")
    return result


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, value, extra=None):
        body = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if self.path == "/health":
            self.reply(200, {"fixture": "WriteDock mock", "real_inference": False})
        else:
            self.reply(404, {"error": {"code": "not_found"}})

    def do_POST(self):
        if not self.path.endswith("/chat/completions"):
            self.reply(404, {"error": {"code": "not_found"}})
            return
        mode = self.path.strip("/").split("/")[0]
        error_modes = {"auth": 401, "rate": 429, "model": 404, "server": 503}
        if mode in error_modes:
            self.reply(error_modes[mode], {"error": {"code": "model_not_found" if mode == "model" else mode}}, {"Retry-After": "5"} if mode == "rate" else None)
            return
        if mode == "redirect":
            self.reply(307, {}, {"Location": "http://127.0.0.1:9/never-forward"})
            return
        if mode == "timeout":
            time.sleep(65)
            self.reply(504, {"error": {"code": "timeout"}})
            return
        if mode == "malformed":
            self.reply(200, {"unexpected": True})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 100_000:
                raise ValueError("invalid length")
            payload = json.loads(self.rfile.read(length))
            messages = payload["messages"]
            original = next(message["content"] for message in messages if message["role"] == "user")
            instruction = next(message["content"] for message in messages if message["role"] == "system")
            if not isinstance(original, str) or not isinstance(instruction, str):
                raise ValueError("invalid messages")
        except (ValueError, KeyError, TypeError, StopIteration):
            self.reply(400, {"error": {"code": "bad_request"}})
            return
        if self.headers.get("Authorization") != "Bearer local-test":
            self.reply(401, {"error": {"code": "invalid_key"}})
            return
        if payload.get("model") != "mock-editor":
            self.reply(404, {"error": {"code": "model_not_found"}})
            return
        if ((mode == "openrouter" and self.headers.get("X-Title") != "WriteDock")
                or (mode == "litellm" and self.headers.get("X-Title") is not None)):
            self.reply(400, {"error": {"code": "wrong_provider_headers"}})
            return
        self.reply(200, {"choices": [{"message": {"role": "assistant", "content": edit_sample(original, instruction)}, "finish_reason": "length" if mode == "truncated" else "stop"}]})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--port-file", help="Write the bound port to this caller-selected file (useful with --port 0).")
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    port = server.server_address[1]
    if args.port_file:
        Path(args.port_file).write_text(str(port), encoding="ascii")
    print(f"WriteDock deterministic mock listening at http://127.0.0.1:{port}/v1", flush=True)
    print("Model: mock-editor; test key: local-test. No real inference; no request logging.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
