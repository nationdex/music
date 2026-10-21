#!/usr/bin/env python3
"""Adi Music -> Discord Rich Presence bridge.

A browser cannot talk to Discord: the desktop client only listens on a local IPC socket.
This script is the small piece that runs on the same computer as Discord. The Adi Music
web page posts what is playing to http://127.0.0.1:6480, and this script forwards it to
Discord as a "Listening to" activity.

Python 3.8+, standard library only. No install step:

    python3 tools/discord-rpc/adi-discord-rpc.py
    python3 tools/discord-rpc/adi-discord-rpc.py --origin http://music.example.com

Only loopback and private-network pages (127.0.0.1, localhost, 10.x, 172.16-31.x, 192.168.x)
may send activity, plus any --origin you add. It never listens on anything but 127.0.0.1.
"""

import argparse
import ipaddress
import json
import os
import socket
import struct
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

OP_HANDSHAKE, OP_FRAME, OP_CLOSE, OP_PING, OP_PONG = 0, 1, 2, 3, 4
MAX_BODY = 8 * 1024


# --------------------------------------------------------------------- Discord IPC


def ipc_paths():
    """Every place Discord (stable, canary, flatpak, snap) puts its IPC endpoint."""
    if sys.platform == "win32":
        return ["\\\\?\\pipe\\discord-ipc-%d" % i for i in range(10)]
    bases = []
    for var in ("XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"):
        if os.environ.get(var):
            bases.append(os.environ[var])
    bases.append("/tmp")
    paths = []
    for base in dict.fromkeys(bases):
        for sub in ("", "app/com.discordapp.Discord/", "snap.discord/", "snap.discord-canary/"):
            for i in range(10):
                paths.append(os.path.join(base, sub, "discord-ipc-%d" % i))
    return paths


class DiscordError(Exception):
    pass


class DiscordIPC:
    """One connection to the Discord client for one application id."""

    def __init__(self, client_id, paths=None):
        self.client_id = client_id
        self.paths = paths if paths is not None else ipc_paths()
        self.sock = None  # unix socket
        self.pipe = None  # windows named pipe

    @property
    def connected(self):
        return self.sock is not None or self.pipe is not None

    def connect(self):
        last = None
        for path in self.paths:
            try:
                if sys.platform == "win32":
                    self.pipe = open(path, "r+b", buffering=0)
                else:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.settimeout(3)
                    s.connect(path)
                    self.sock = s
                break
            except OSError as e:
                last = e
        else:
            raise DiscordError("Discord is not running (%s)" % (last or "no IPC endpoint found"))
        try:
            self._send(OP_HANDSHAKE, {"v": 1, "client_id": self.client_id})
            _, reply = self._recv()
            if reply.get("evt") != "READY":
                raise DiscordError("handshake refused: %s" % reply)
        except Exception:
            self.close()
            raise

    def _write(self, data):
        if self.sock is not None:
            self.sock.sendall(data)
        else:
            self.pipe.write(data)

    def _read(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf)) if self.sock is not None else self.pipe.read(n - len(buf))
            if not chunk:
                raise DiscordError("Discord closed the connection")
            buf += chunk
        return buf

    def _send(self, op, payload):
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self._write(struct.pack("<II", op, len(data)) + data)

    def _recv(self):
        op, length = struct.unpack("<II", self._read(8))
        return op, json.loads(self._read(length).decode("utf-8"))

    def set_activity(self, activity):
        """activity=None clears it. Returns Discord's reply."""
        nonce = str(uuid.uuid4())
        self._send(OP_FRAME, {"cmd": "SET_ACTIVITY", "args": {"pid": os.getpid(), "activity": activity}, "nonce": nonce})
        while True:
            op, reply = self._recv()
            if op == OP_PING:
                self._send(OP_PONG, reply)
                continue
            if op == OP_CLOSE:
                raise DiscordError("Discord closed the connection: %s" % reply)
            if reply.get("nonce") == nonce:
                if reply.get("evt") == "ERROR":
                    raise DiscordError(reply.get("data", {}).get("message", "SET_ACTIVITY failed"))
                return reply

    def close(self):
        for h in (self.sock, self.pipe):
            try:
                if h is not None:
                    h.close()
            except OSError:
                pass
        self.sock = self.pipe = None


# ------------------------------------------------------------------- activity mapping


def clip(text, limit=128):
    text = str(text or "").strip()
    return text[:limit] if len(text) >= 2 else (text + "  ")[:2] if text else ""


def to_activity(p):
    """Web payload -> Discord activity. Returns None when there is nothing to show."""
    details = clip(p.get("details"))
    if not details:
        return None
    activity = {"type": 2, "details": details, "instance": False}  # 2 = "Listening to"
    state = clip(p.get("state"))
    if state:
        activity["state"] = state
    ts = {}
    if isinstance(p.get("startTimestamp"), (int, float)):
        ts["start"] = int(p["startTimestamp"])
    if isinstance(p.get("endTimestamp"), (int, float)):
        ts["end"] = int(p["endTimestamp"])
    if ts:
        activity["timestamps"] = ts
    assets = {}
    for src, dst in (("largeImage", "large_image"), ("largeText", "large_text"), ("smallImage", "small_image"), ("smallText", "small_text")):
        if p.get(src):
            assets[dst] = clip(p[src], 256)
    if assets:
        activity["assets"] = assets
    return activity


# ---------------------------------------------------------------------------- state


class Bridge:
    def __init__(self, extra_origins=(), paths=None):
        self.extra_origins = {o.rstrip("/") for o in extra_origins}
        self.paths = paths
        self.lock = threading.Lock()
        self.ipc = None
        self.last_error = ""

    def origin_allowed(self, origin):
        if not origin:
            return True  # not a browser (curl): loopback-only listener, so fine
        if origin.rstrip("/") in self.extra_origins:
            return True
        host = urlparse(origin).hostname or ""
        if host in ("localhost", "127.0.0.1", "::1"):
            return True
        try:
            ip = ipaddress.ip_address(host)
            return ip.is_private or ip.is_loopback
        except ValueError:
            return False

    def _connection(self, client_id):
        if self.ipc is not None and (self.ipc.client_id != client_id or not self.ipc.connected):
            self.ipc.close()
            self.ipc = None
        if self.ipc is None:
            ipc = DiscordIPC(client_id, self.paths)
            ipc.connect()
            self.ipc = ipc
        return self.ipc

    def apply(self, client_id, activity):
        """Sets or clears the activity. One reconnect attempt if the connection went stale."""
        with self.lock:
            for attempt in (1, 2):
                try:
                    self._connection(client_id).set_activity(activity)
                    self.last_error = ""
                    return
                except (DiscordError, OSError, ValueError) as e:
                    if self.ipc is not None:
                        self.ipc.close()
                        self.ipc = None
                    self.last_error = str(e)
                    if attempt == 2:
                        raise DiscordError(str(e))

    def clear(self):
        with self.lock:
            if self.ipc is not None and self.ipc.connected:
                try:
                    self.ipc.set_activity(None)
                except (DiscordError, OSError, ValueError):
                    self.ipc.close()
                    self.ipc = None

    def status(self):
        with self.lock:
            return {"ok": True, "discord": bool(self.ipc and self.ipc.connected), "error": self.last_error}


# ----------------------------------------------------------------------------- HTTP


def make_handler(bridge):
    class Handler(BaseHTTPRequestHandler):
        server_version = "AdiDiscordRPC/1.0"

        def log_message(self, fmt, *args):
            pass

        def _cors(self):
            origin = self.headers.get("Origin", "")
            if origin and bridge.origin_allowed(origin):
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Vary", "Origin")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header("Access-Control-Allow-Headers", "Content-Type")
                # Chrome's Local Network Access check for pages on another network.
                self.send_header("Access-Control-Allow-Private-Network", "true")

        def _reply(self, code, body=None):
            data = json.dumps(body if body is not None else {"ok": code < 400}).encode("utf-8")
            self.send_response(code)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _allowed(self):
            if bridge.origin_allowed(self.headers.get("Origin", "")):
                return True
            self._reply(403, {"ok": False, "error": "origin not allowed; start the bridge with --origin"})
            return False

        def do_OPTIONS(self):
            if not self._allowed():
                return
            self.send_response(204)
            self._cors()
            self.send_header("Content-Length", "0")
            self.end_headers()

        def do_GET(self):
            if not self._allowed():
                return
            if urlparse(self.path).path == "/ping":
                return self._reply(200, bridge.status())
            self._reply(404, {"ok": False})

        def do_POST(self):
            if not self._allowed():
                return
            path = urlparse(self.path).path
            length = int(self.headers.get("Content-Length") or 0)
            if length > MAX_BODY:
                return self._reply(413, {"ok": False, "error": "body too large"})
            raw = self.rfile.read(length) if length else b""
            if path == "/clear":
                bridge.clear()
                return self._reply(200)
            if path != "/presence":
                return self._reply(404, {"ok": False})
            try:
                payload = json.loads(raw.decode("utf-8"))
                client_id = str(payload.get("clientId", "")).strip()
            except (ValueError, AttributeError):
                return self._reply(400, {"ok": False, "error": "invalid JSON"})
            if not client_id.isdigit():
                return self._reply(400, {"ok": False, "error": "clientId must be a Discord application id (digits)"})
            try:
                bridge.apply(client_id, to_activity(payload))
            except DiscordError as e:
                return self._reply(502, {"ok": False, "error": str(e)})
            self._reply(200)

    return Handler


def main(argv=None):
    ap = argparse.ArgumentParser(description="Adi Music to Discord Rich Presence bridge")
    ap.add_argument("--port", type=int, default=6480)
    ap.add_argument("--origin", action="append", default=[], help="extra allowed page origin, e.g. https://music.example.com")
    args = ap.parse_args(argv)

    bridge = Bridge(args.origin)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(bridge))
    print("Adi Music Discord bridge on http://127.0.0.1:%d (Ctrl+C to stop)" % args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        bridge.clear()
        server.server_close()


if __name__ == "__main__":
    main()
