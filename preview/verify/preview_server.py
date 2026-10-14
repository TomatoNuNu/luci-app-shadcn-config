#!/usr/bin/env python3
"""Serve a locally rendered shadcn login page with the theme's real assets.

Maps the asset URLs the rendered page asks for onto the theme source tree, so
the page can be screenshotted over http:// exactly as a router would serve it.
"""

import http.server
import pathlib
import sys

THEME = pathlib.Path(sys.argv[1]).resolve()      # luci-theme-shadcn source tree
LUCI = pathlib.Path(sys.argv[2]).resolve()       # luci-base source tree
PAGE = pathlib.Path(sys.argv[3]).resolve()       # rendered html
WALLPAPERS = pathlib.Path(sys.argv[4]).resolve()  # /www/.../wallpapers stand-in
PORT = int(sys.argv[5]) if len(sys.argv) > 5 else 8811

MIME = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css",
    ".js": "application/javascript",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpeg": "image/jpeg",
    ".jpg": "image/jpeg",
    ".woff2": "font/woff2",
    ".ico": "image/x-icon",
}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_GET(self):
        path = self.path.split("?")[0]
        target = None

        if path in ("/", "/index.html"):
            target = PAGE
        elif path.startswith("/luci-static/shadcn/wallpapers/"):
            target = WALLPAPERS / path.split("/")[-1]
        elif path.startswith("/luci-static/shadcn/"):
            target = THEME / "htdocs/luci-static/shadcn" / path[len("/luci-static/shadcn/"):]
        elif path.startswith("/luci-static/resources/"):
            target = LUCI / "htdocs/luci-static/resources" / path[len("/luci-static/resources/"):]

        if target is None or not target.is_file():
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        body = target.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", MIME.get(target.suffix, "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
