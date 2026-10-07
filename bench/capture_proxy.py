"""Request-capturing proxy for issue triage: listens on --port, forwards every request to --upstream unchanged, and
writes each request body (and the response status, or the error body) as one JSON line to --out. Streaming responses
are relayed as they arrive. Use it between a client (Hermes, Cline, ...) and the serve to see exactly what the client
sends on the request that fails.

    python bench/capture_proxy.py --port 8070 --upstream http://127.0.0.1:8080 --out logs/captured_requests.jsonl
"""
import argparse, http.server, json, socketserver, time, urllib.error, urllib.request

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def _relay(self, method):
        n = int(self.headers.get("Content-Length") or 0); raw = self.rfile.read(n) if n else b""
        hdrs = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "content-length", "accept-encoding")}
        rec = {"t": time.strftime("%H:%M:%S"), "method": method, "path": self.path}
        try: rec["body"] = json.loads(raw) if raw else None
        except Exception: rec["body_raw"] = raw[:2000].decode("utf-8", "replace")
        req = urllib.request.Request(ARGS.upstream + self.path, data=raw if raw else None, headers=hdrs, method=method)
        try:
            with urllib.request.urlopen(req, timeout=3600) as r:
                rec["status"] = r.status
                self.send_response(r.status)
                for k, v in r.getheaders():
                    if k.lower() not in ("transfer-encoding", "content-length", "connection"): self.send_header(k, v)
                chunks = []
                body = None
                if "text/event-stream" in (r.headers.get("Content-Type") or ""):
                    self.send_header("Transfer-Encoding", "chunked"); self.end_headers()
                    while True:
                        c = r.read(4096)
                        if not c: break
                        self.wfile.write(("%x\r\n" % len(c)).encode() + c + b"\r\n"); self.wfile.flush(); chunks.append(c)
                    self.wfile.write(b"0\r\n\r\n")
                    rec["stream_bytes"] = sum(len(c) for c in chunks)
                else:
                    body = r.read(); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
                    rec["response_head"] = body[:300].decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            eb = e.read(); rec["status"] = e.code; rec["error"] = eb[:2000].decode("utf-8", "replace")
            self.send_response(e.code); self.send_header("Content-Type", e.headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(eb))); self.end_headers(); self.wfile.write(eb)
        except Exception as e:
            rec["status"] = "proxy-error"; rec["error"] = repr(e)
            try:
                self.send_response(502); self.send_header("Content-Length", "0"); self.end_headers()
            except Exception: pass
        with open(ARGS.out, "a", encoding="utf-8") as f: f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    def do_POST(self): self._relay("POST")
    def do_GET(self): self._relay("GET")

class TS(socketserver.ThreadingMixIn, http.server.HTTPServer): daemon_threads = True

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--port", type=int, default=8070); ap.add_argument("--upstream", default="http://127.0.0.1:8080"); ap.add_argument("--out", default="logs/captured_requests.jsonl")
    ARGS = ap.parse_args(); print(f"capture proxy :{ARGS.port} -> {ARGS.upstream}, log {ARGS.out}", flush=True)
    TS(("0.0.0.0", ARGS.port), H).serve_forever()
