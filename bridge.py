#!/usr/bin/env python3
"""
Brain Atlas Bridge — SSE fanout + config/nodes API.
Uses only Python stdlib.
"""

import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
CONFIG_FILE = SCRIPT_DIR / "config.json"
NODES_FILE = SCRIPT_DIR / "nodes.json"
SESSIONS_FILE = SCRIPT_DIR / "sessions.json"

DEFAULT_PORT = 8766


def _load_config() -> dict:
    if CONFIG_FILE.exists():
        try:
            return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {}


def _port() -> int:
    return int(_load_config().get("bridgePort", DEFAULT_PORT))


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


def _cors(handler):
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type")


def _json_response(handler, status: int, data):
    body = json.dumps(data).encode("utf-8")
    handler.send_response(status)
    _cors(handler)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


class BridgeHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002
        pass

    def do_OPTIONS(self):
        self.send_response(200)
        _cors(self)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        routes = {
            "/stream":   self._stream,
            "/config":   self._get_config,
            "/nodes":    self._get_nodes,
            "/sessions": self._get_sessions,
            "/health":   self._health,
        }
        handler = routes.get(self.path)
        if handler:
            handler()
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/event":
            self._post_event()
        elif self.path == "/config":
            self._post_config()
        else:
            self.send_response(404)
            self.end_headers()

    # ── GET /config ────────────────────────────────────────────────────────
    def _get_config(self):
        if not CONFIG_FILE.exists():
            _json_response(self, 200, {"setup": True})
            return
        try:
            data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
            _json_response(self, 200, data)
        except Exception:
            _json_response(self, 200, {"setup": True})

    # ── POST /config ───────────────────────────────────────────────────────
    def _post_config(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            _json_response(self, 400, {"error": "invalid json"})
            return

        # Expand ~ in sourceDir
        if "sourceDir" in data:
            data["sourceDir"] = str(Path(data["sourceDir"]).expanduser())

        CONFIG_FILE.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
        _json_response(self, 200, {"ok": True})

    # ── GET /nodes ─────────────────────────────────────────────────────────
    def _get_nodes(self):
        if not NODES_FILE.exists():
            _json_response(self, 200, {"nodes": [], "links": [], "satellites": {}, "toolMap": []})
            return
        try:
            data = json.loads(NODES_FILE.read_text(encoding="utf-8"))
            _json_response(self, 200, data)
        except Exception as e:
            _json_response(self, 500, {"error": str(e)})

    # ── POST /event ────────────────────────────────────────────────────────
    def _post_event(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            _json_response(self, 400, {"error": "invalid json"})
            return

        if "ts" not in payload:
            payload["ts"] = int(time.time())

        _fanout("data: " + json.dumps(payload) + "\n\n")
        _json_response(self, 200, {"ok": True})

    # ── GET /stream ────────────────────────────────────────────────────────
    def _stream(self):
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
                    self.wfile.write(b": keep-alive\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            _remove_client(q)

    # ── GET /sessions ──────────────────────────────────────────────────────
    def _get_sessions(self):
        content = "[]"
        if SESSIONS_FILE.exists():
            try:
                text = SESSIONS_FILE.read_text(encoding="utf-8")
                json.loads(text)
                content = text
            except Exception:
                pass
        body = content.encode("utf-8")
        self.send_response(200)
        _cors(self)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # ── GET /health ────────────────────────────────────────────────────────
    def _health(self):
        with _clients_lock:
            n = len(_clients)
        _json_response(self, 200, {"ok": True, "clients": n})


if __name__ == "__main__":
    port = _port()
    server = ThreadingHTTPServer(("", port), BridgeHandler)
    print(f"Brain Atlas Bridge running on http://localhost:{port}")
    server.serve_forever()
