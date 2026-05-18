#!/usr/bin/env python3
"""
Cerebro Bridge — SSE fanout server for Cerebro.html visualization.
Runs on port 8766. Uses only Python stdlib.
"""

import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = 8766
SESSIONS_FILE = Path.home() / ".claude" / "cerebro" / "sessions.json"

# Thread-safe list of SSE client queues
_clients: list = []
_clients_lock = threading.Lock()


def _add_client(q):
    with _clients_lock:
        _clients.append(q)


def _remove_client(q):
    with _clients_lock:
        try:
            _clients.remove(q)
        except ValueError:
            pass


def _fanout(data: str):
    """Send SSE data line to all connected clients; drop disconnected ones."""
    with _clients_lock:
        snapshot = list(_clients)

    dead = []
    for q in snapshot:
        try:
            q.put_nowait(data)
        except Exception:
            dead.append(q)

    for q in dead:
        _remove_client(q)


def _cors_headers(handler):
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type")


class CerebroHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002
        # Suppress default access log noise
        pass

    # ------------------------------------------------------------------
    # OPTIONS — CORS preflight
    # ------------------------------------------------------------------
    def do_OPTIONS(self):
        self.send_response(200)
        _cors_headers(self)
        self.send_header("Content-Length", "0")
        self.end_headers()

    # ------------------------------------------------------------------
    # POST /event
    # ------------------------------------------------------------------
    def do_POST(self):
        if self.path != "/event":
            self.send_response(404)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            self.send_response(400)
            _cors_headers(self)
            self.end_headers()
            self.wfile.write(b'{"error":"invalid json"}')
            return

        # Ensure ts field exists
        if "ts" not in payload:
            payload["ts"] = int(time.time())

        sse_line = "data: " + json.dumps(payload) + "\n\n"
        _fanout(sse_line)

        self.send_response(200)
        _cors_headers(self)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    # ------------------------------------------------------------------
    # GET
    # ------------------------------------------------------------------
    def do_GET(self):
        if self.path == "/stream":
            self._handle_stream()
        elif self.path == "/sessions":
            self._handle_sessions()
        elif self.path == "/health":
            self._handle_health()
        else:
            self.send_response(404)
            self.end_headers()

    # ------------------------------------------------------------------
    # GET /stream — SSE
    # ------------------------------------------------------------------
    def _handle_stream(self):
        import queue as _queue

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        q = _queue.Queue()
        _add_client(q)

        try:
            while True:
                try:
                    data = q.get(timeout=15)
                    self.wfile.write(data.encode("utf-8"))
                    self.wfile.flush()
                except _queue.Empty:
                    # Send a keep-alive comment
                    self.wfile.write(b": keep-alive\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            _remove_client(q)

    # ------------------------------------------------------------------
    # GET /sessions
    # ------------------------------------------------------------------
    def _handle_sessions(self):
        if SESSIONS_FILE.exists():
            try:
                content = SESSIONS_FILE.read_text(encoding="utf-8")
                json.loads(content)  # validate
            except Exception:
                content = "[]"
        else:
            content = "[]"

        body = content.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # ------------------------------------------------------------------
    # GET /health
    # ------------------------------------------------------------------
    def _handle_health(self):
        with _clients_lock:
            n = len(_clients)

        body = json.dumps({"ok": True, "clients": n}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("", PORT), CerebroHandler)
    print(f"Cerebro Bridge running on http://localhost:{PORT}")
    server.serve_forever()
