#!/usr/bin/env python3
# Serves MediaFusion on :8001 but rewrites the manifest's "configurable":true
# -> false so Stremio installs it without opening the (unbuilt) configure page.
# Everything else is forwarded unchanged to the API on :8000.
import http.server, socketserver, urllib.request

TARGET = "http://127.0.0.1:8000"
LISTEN = ("0.0.0.0", 8001)

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            req = urllib.request.Request(TARGET + self.path, method="GET")
            for k, v in self.headers.items():
                if k.lower() not in ("host", "connection", "content-length"):
                    req.add_header(k, v)
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
                if self.path.split("?")[0].endswith("/manifest.json"):
                    data = data.replace(b'"configurable":true', b'"configurable":false')
                self.send_response(r.status)
                for k, v in r.headers.items():
                    if k.lower() not in ("transfer-encoding", "connection", "content-length"):
                        self.send_header(k, v)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        except Exception as e:
            m = str(e).encode()
            try:
                self.send_response(502)
                self.send_header("Content-Length", str(len(m)))
                self.end_headers()
                self.wfile.write(m)
            except Exception:
                pass
    def log_message(self, *a):
        pass

class T(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

print("mfmproxy on 0.0.0.0:8001 -> 8000 (manifest configurable->false)", flush=True)
T(LISTEN, H).serve_forever()
