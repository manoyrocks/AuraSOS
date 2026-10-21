"""Serves build/web for browser / phone / tablet testing.

Usage: python3 tool/serve_web.py [port]    (default 8080; run tool/build_web.sh first)
Set AURA_WEB_ROOT to serve a different folder.
Binds to all interfaces so a phone or tablet on the same Wi-Fi can open http://<this-computer>:<port>.
"""
import functools
import http.server
import os
import socket
import sys

root = os.environ.get("AURA_WEB_ROOT") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")
port = int(os.environ.get("PORT") or (sys.argv[1] if len(sys.argv) > 1 else 8080))


def load_headers():
    """Reads the `/*` block of web/_headers so local testing uses the production policy."""
    path = os.path.join(root, "_headers")
    headers, in_all = [], False
    if os.path.isfile(path):
        for line in open(path, encoding="utf-8"):
            if line.startswith("#") or not line.strip():
                continue
            if not line.startswith(" "):
                in_all = line.strip() == "/*"
            elif in_all and ":" in line:
                name, value = line.strip().split(":", 1)
                headers.append((name.strip(), value.strip()))
    return headers


HEADERS = load_headers()


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # The same security + caching headers production uses (CSP, nosniff, no-cache, ...).
        for name, value in HEADERS:
            self.send_header(name, value)
        super().end_headers()


def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))  # no packet is sent; only picks the outgoing interface
        return s.getsockname()[0]
    except OSError:
        return None


if not os.path.isdir(root):
    sys.exit("build/web not found - run tool/build_web.sh first")

with http.server.ThreadingHTTPServer(("0.0.0.0", port), functools.partial(Handler, directory=root)) as srv:
    print(f"Applying {len(HEADERS)} production headers from _headers (including the CSP)")
    print(f"AuraSOS on this computer:  http://localhost:{port}")
    ip = lan_ip()
    if ip:
        print(f"AuraSOS on your phone/tablet (same Wi-Fi):  http://{ip}:{port}")
    srv.serve_forever()
