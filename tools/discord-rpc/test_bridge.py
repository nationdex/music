"""Tests for the Discord bridge, against a fake Discord IPC server. Run: python3 -m unittest -v tools/discord-rpc/test_bridge.py"""

import importlib.util
import json
import os
import socket
import struct
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("bridge", os.path.join(HERE, "adi-discord-rpc.py"))
bridge_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge_mod)


class FakeDiscord:
    """Speaks just enough of Discord's IPC protocol: READY on handshake, ack on SET_ACTIVITY."""

    def __init__(self, path):
        self.path = path
        self.handshakes = []
        self.activities = []
        self.connections = 0
        self.srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.srv.bind(path)
        self.srv.listen(4)
        self.alive = True
        threading.Thread(target=self._accept, daemon=True).start()

    def _read(self, c, n):
        buf = b""
        while len(buf) < n:
            chunk = c.recv(n - len(buf))
            if not chunk:
                raise EOFError
            buf += chunk
        return buf

    def _accept(self):
        while self.alive:
            try:
                c, _ = self.srv.accept()
            except OSError:
                return
            self.connections += 1
            threading.Thread(target=self._serve, args=(c,), daemon=True).start()

    def _serve(self, c):
        self.current = c
        try:
            while True:
                op, length = struct.unpack("<II", self._read(c, 8))
                msg = json.loads(self._read(c, length))
                if op == 0:
                    self.handshakes.append(msg)
                    out = {"cmd": "DISPATCH", "evt": "READY", "data": {"v": 1}}
                    c.sendall(struct.pack("<II", 1, len(json.dumps(out))) + json.dumps(out).encode())
                elif msg.get("cmd") == "SET_ACTIVITY":
                    self.activities.append(msg["args"]["activity"])
                    out = {"cmd": "SET_ACTIVITY", "evt": None, "nonce": msg["nonce"], "data": {}}
                    c.sendall(struct.pack("<II", 1, len(json.dumps(out))) + json.dumps(out).encode())
        except (EOFError, OSError):
            pass

    def drop_connection(self):
        self.current.close()

    def stop(self):
        self.alive = False
        self.srv.close()


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="adi-ipc-")
        self.sock_path = os.path.join(self.dir, "discord-ipc-0")
        self.discord = FakeDiscord(self.sock_path)
        self.bridge = bridge_mod.Bridge(extra_origins=["https://music.example.com"], paths=[self.sock_path])
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), bridge_mod.make_handler(self.bridge))
        self.base = "http://127.0.0.1:%d" % self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.discord.stop()

    def call(self, path, body=None, origin=None, method=None):
        req = urllib.request.Request(self.base + path, data=json.dumps(body).encode() if body is not None else None, method=method)
        if body is not None:
            req.add_header("Content-Type", "application/json")
        if origin:
            req.add_header("Origin", origin)
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read() or b"{}"), r.headers
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read() or b"{}"), e.headers

    PLAY = {"clientId": "123456789012345678", "details": "Bad", "state": "by Michael Jackson", "startTimestamp": 1000, "endTimestamp": 251000, "largeImage": "https://i.ytimg.com/vi/x/hqdefault.jpg", "largeText": "Bad"}

    def test_handshake_and_listening_activity(self):
        status, body, _ = self.call("/presence", self.PLAY, origin="http://127.0.0.1:3030")
        self.assertEqual(status, 200)
        self.assertEqual(self.discord.handshakes, [{"v": 1, "client_id": "123456789012345678"}])
        a = self.discord.activities[-1]
        self.assertEqual(a["type"], 2, "Listening to")
        self.assertEqual(a["details"], "Bad")
        self.assertEqual(a["state"], "by Michael Jackson")
        self.assertEqual(a["timestamps"], {"start": 1000, "end": 251000})
        self.assertEqual(a["assets"]["large_image"], "https://i.ytimg.com/vi/x/hqdefault.jpg")

    def test_reuses_the_connection(self):
        self.call("/presence", self.PLAY)
        self.call("/presence", dict(self.PLAY, details="Smooth Criminal"))
        self.assertEqual(self.discord.connections, 1)
        self.assertEqual(len(self.discord.activities), 2)

    def test_clear_sends_null_activity(self):
        self.call("/presence", self.PLAY)
        status, _, _ = self.call("/clear", {})
        self.assertEqual(status, 200)
        self.assertIsNone(self.discord.activities[-1])

    def test_reconnects_after_discord_restarts(self):
        self.call("/presence", self.PLAY)
        self.discord.drop_connection()
        status, _, _ = self.call("/presence", dict(self.PLAY, details="Dirty Diana"))
        self.assertEqual(status, 200)
        self.assertEqual(self.discord.connections, 2)
        self.assertEqual(self.discord.activities[-1]["details"], "Dirty Diana")

    def test_new_application_id_reconnects(self):
        self.call("/presence", self.PLAY)
        self.call("/presence", dict(self.PLAY, clientId="999999999999999999"))
        self.assertEqual([h["client_id"] for h in self.discord.handshakes], ["123456789012345678", "999999999999999999"])

    def test_discord_not_running_is_a_clear_502(self):
        self.discord.stop()
        os.unlink(self.sock_path)
        status, body, _ = self.call("/presence", self.PLAY)
        self.assertEqual(status, 502)
        self.assertIn("not running", body["error"])

    def test_rejects_bad_client_id_and_bad_json(self):
        self.assertEqual(self.call("/presence", dict(self.PLAY, clientId="abc"))[0], 400)
        req = urllib.request.Request(self.base + "/presence", data=b"{nope", method="POST")
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req, timeout=5)
        self.assertEqual(ctx.exception.code, 400)

    def test_origin_rules(self):
        for ok in ("http://localhost:3030", "http://127.0.0.1:3030", "http://192.168.1.119:3030", "http://10.0.0.5", "https://music.example.com"):
            self.assertEqual(self.call("/ping", origin=ok)[0], 200, ok)
        for bad in ("https://evil.example", "http://8.8.8.8", "http://192.168.1.1.evil.example"):
            self.assertEqual(self.call("/ping", origin=bad)[0], 403, bad)
        self.assertEqual(len(self.discord.activities), 0)

    def test_blocked_origin_cannot_set_presence(self):
        status, _, _ = self.call("/presence", self.PLAY, origin="https://evil.example")
        self.assertEqual(status, 403)
        self.assertEqual(self.discord.activities, [])

    def test_cors_preflight_includes_private_network_header(self):
        req = urllib.request.Request(self.base + "/presence", method="OPTIONS")
        req.add_header("Origin", "http://192.168.1.119:3030")
        req.add_header("Access-Control-Request-Method", "POST")
        with urllib.request.urlopen(req, timeout=5) as r:
            self.assertEqual(r.status, 204)
            self.assertEqual(r.headers["Access-Control-Allow-Origin"], "http://192.168.1.119:3030")
            self.assertEqual(r.headers["Access-Control-Allow-Private-Network"], "true")

    def test_ping_reports_discord_connection(self):
        self.assertFalse(self.call("/ping")[1]["discord"])
        self.call("/presence", self.PLAY)
        self.assertTrue(self.call("/ping")[1]["discord"])

    def test_activity_mapping_edges(self):
        self.assertIsNone(bridge_mod.to_activity({"details": ""}))
        self.assertEqual(bridge_mod.to_activity({"details": "A"})["details"], "A ", "Discord needs at least two characters")
        long = bridge_mod.to_activity({"details": "x" * 500})
        self.assertEqual(len(long["details"]), 128)
        self.assertNotIn("timestamps", bridge_mod.to_activity({"details": "Paused song"}), "paused: no progress bar")

    def test_oversized_body_rejected(self):
        status, _, _ = self.call("/presence", {"clientId": "1", "details": "x" * 20000})
        self.assertEqual(status, 413)


if __name__ == "__main__":
    unittest.main()
