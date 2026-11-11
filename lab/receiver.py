#!/usr/bin/env python3
# Lab only (keepalive-lab, never merged). Answers Ammy's pushes at
# https://localhost:8443/now-playing with 204, as Issun does, and appends each
# one with its arrival time to a JSON-lines file, so the lab sees every push,
# not only the changes Issun logs. Listens on IPv4 and IPv6, since iOS may try
# ::1 for localhost first.
#   python3 -I lab/receiver.py out/pushes.jsonl tls/srv.pem tls/srv.key
import json
import socket
import ssl
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OUT, CERT, KEY = sys.argv[1], sys.argv[2], sys.argv[3]


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(size)
        try:
            body = json.loads(raw)
        except ValueError:
            body = {"unparsed": raw[:200].decode("latin-1")}
        with open(OUT, "a", encoding="utf-8") as f:
            f.write(json.dumps({"t": time.time(), "path": self.path, "body": body}) + "\n")
        self.send_response(204 if self.path == "/now-playing" else 404)
        self.send_header("X-Ammy-Relay", "keepalive-lab")
        self.end_headers()

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, fmt, *args):
        sys.stderr.write("%.3f %s\n" % (time.time(), fmt % args))


class DualStack(ThreadingHTTPServer):
    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


server = DualStack(("::", 8443), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(CERT, KEY)
server.socket = context.wrap_socket(server.socket, server_side=True)
sys.stderr.write("%.3f listening on [::]:8443 and 0.0.0.0:8443\n" % time.time())
sys.stderr.flush()
server.serve_forever()
