"""P155 test layer: runs the branch's layer/bonsai_layer.py (layer-slot-cache) in front of a test server, with the code
sandbox stubbed out (this rig has no wasmtime; the test requests set code_interpreter false, so the sandbox is never used).

python p155_layer.py --port 8081 --upstream http://127.0.0.1:8080 [--cache]   (--cache: SlotCache from BONSAI_SLOT_SAVE_PATH)
"""
import argparse
import http.server
import sys
import types

LAYER = r"C:\bonsai\8gb\layer_ra"   # P162: PR #159 (read ahead) on main after #157
for name in ("wasmtime", "sandbox"):
    sys.modules[name] = types.ModuleType(name)   # stubs: the layer imports them at load time only
sys.path.insert(0, LAYER)
import bonsai_layer  # noqa: E402
import slot_cache  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--port", type=int, default=8081)
ap.add_argument("--upstream", default="http://127.0.0.1:8080")
ap.add_argument("--cache", action="store_true")
a = ap.parse_args()
P = bonsai_layer.Proxy
P.upstream = a.upstream
P.slots = slot_cache.SlotCache.from_env(a.upstream) if a.cache else None
print(f"p155 layer on :{a.port} -> {a.upstream}, cache {'on: ' + P.slots.folder if P.slots else 'off'}", flush=True)
http.server.ThreadingHTTPServer(("127.0.0.1", a.port), P).serve_forever()
