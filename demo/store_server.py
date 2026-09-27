"""Loopback Sandbox Market. Fake checkout only. No payment network."""
from __future__ import annotations

import argparse
import json
import secrets
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs

STORE_DIR = Path(__file__).resolve().parent / "store"
TEST_CARD = "4242424242424242"
PRODUCT = {"sku": "harbor-mug", "item": "Harbor Mug", "total": "$36.00"}


class StoreState:
    def __init__(self, orders_path: Path) -> None:
        self.orders_path = orders_path
        self.lock = threading.Lock()
        self.orders_path.parent.mkdir(parents=True, exist_ok=True)
        if not self.orders_path.is_file():
            self.orders_path.write_text("[]\n", encoding="utf-8")

    def load(self) -> list[dict[str, Any]]:
        with self.lock:
            return json.loads(self.orders_path.read_text(encoding="utf-8"))

    def append(self, order: dict[str, Any]) -> dict[str, Any]:
        with self.lock:
            orders = json.loads(self.orders_path.read_text(encoding="utf-8"))
            orders.append(order)
            self.orders_path.write_text(json.dumps(orders, indent=2) + "\n", encoding="utf-8")
            return order


class StoreHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, state: StoreState, **kwargs):
        self.state = state
        super().__init__(*args, directory=str(STORE_DIR), **kwargs)

    def log_message(self, format: str, *args) -> None:
        return

    def _json(self, code: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path.split("?", 1)[0] == "/api/orders":
            self._json(200, {"orders": self.state.load()})
            return
        if self.path.split("?", 1)[0] == "/api/last":
            orders = self.state.load()
            self._json(200, {"order": orders[-1] if orders else None})
            return
        super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        if self.path.split("?", 1)[0] != "/api/checkout":
            self._json(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode("utf-8") if length else ""
        ctype = (self.headers.get("Content-Type") or "").split(";", 1)[0].strip()
        if ctype == "application/json":
            data = json.loads(raw or "{}")
        else:
            parsed = parse_qs(raw)
            data = {key: values[-1] for key, values in parsed.items()}
        order, error = place_order(data)
        if error:
            self._json(400, {"error": error})
            return
        saved = self.state.append(order)
        self._json(200, saved)


def place_order(data: dict[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
    name = str(data.get("full_name") or "").strip()
    email = str(data.get("email") or "").strip()
    address = str(data.get("address") or "").strip()
    card = "".join(ch for ch in str(data.get("card_number") or "") if ch.isdigit())
    expiry = str(data.get("expiry") or "").strip()
    cvc = str(data.get("cvc") or "").strip()
    sku = str(data.get("sku") or PRODUCT["sku"]).strip()
    if sku != PRODUCT["sku"]:
        return None, "unknown sku"
    if not name or not email or not address:
        return None, "missing buyer fields"
    if card != TEST_CARD:
        return None, "sandbox only accepts test card 4242424242424242"
    if not expiry or not cvc:
        return None, "missing card extras"
    order = {
        "order_id": "SBX-" + secrets.token_hex(3).upper(),
        "sku": PRODUCT["sku"],
        "item": PRODUCT["item"],
        "total": PRODUCT["total"],
        "full_name": name,
        "email": email,
        "address": address,
        "last4": card[-4:],
        "expiry": expiry,
    }
    return order, None


def start_store(host: str, port: int, orders_path: Path) -> tuple[ThreadingHTTPServer, str]:
    if not STORE_DIR.is_dir():
        raise SystemExit(f"store assets missing: {STORE_DIR}")
    state = StoreState(orders_path)
    handler = partial(StoreHandler, state=state)
    server = ThreadingHTTPServer((host, port), handler)
    thread = threading.Thread(target=server.serve_forever, name="sandbox-market", daemon=True)
    thread.start()
    url = f"http://{host}:{server.server_port}"
    return server, url


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--orders", default=str(Path("artifacts/demo/browser-use/orders.json")))
    args = parser.parse_args()
    server, url = start_store(args.host, args.port, Path(args.orders))
    print(f"sandbox market {url} orders={args.orders}", flush=True)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
