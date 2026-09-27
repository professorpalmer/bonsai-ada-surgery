"""Replay of Killy's plate 037P (voxel pagoda) against a running server, rendered headless.

Prompt as printed on the plate ("..." marks text the plate elides). The plate ran in a sealed headless
Chrome with three r160 vendored and no network; this replay loads three from unpkg as the prompt asks and
screenshots each page with headless Edge/Chrome after RENDER_WAIT_MS. One sample per effort setting.

  python bench/pagoda_plate.py --key-file artifacts/api_key.txt --arms medium,off
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import time
import urllib.request

PROMPT = (
    "Build a voxel-art 3D pagoda as a single self-contained HTML file using Three.js loaded from unpkg. "
    "Use only cubes (BoxGeometry) as the voxels. The pagoda has five tiers with stacked roofs, a base, and a "
    "spire on top. Add a ground plane, lighting, and a camera that slowly orbits the pagoda. Return only the HTML."
)
BROWSERS = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
]


def chat(base: str, key: str, arm: str, max_tokens: int) -> dict:
    kwargs = {"enable_thinking": arm != "off", "reasoning_effort": "medium"}
    body = {"model": "bonsai-2-27b", "messages": [{"role": "user", "content": PROMPT}], "max_tokens": max_tokens,
            "chat_template_kwargs": kwargs}
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", json.dumps(body).encode(),
                                 {"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    out = json.load(urllib.request.urlopen(req, timeout=3600))
    msg = out["choices"][0]["message"]
    return {"content": msg.get("content") or "", "finish": out["choices"][0].get("finish_reason"),
            "tokens": (out.get("usage") or {}).get("completion_tokens"), "seconds": round(time.time() - t0, 1)}


def extract_html(text: str) -> str:
    m = re.search(r"```(?:html)?\s*([\s\S]*?)```", text, flags=re.IGNORECASE)
    html = m.group(1) if m else text
    return html.strip()


def render(html_path: str, png_path: str, wait_ms: int) -> str:
    browser = next((b for b in BROWSERS if os.path.exists(b)), None)
    if not browser:
        return "no headless browser found"
    cmd = [browser, "--headless=new", "--disable-gpu-sandbox", "--use-angle=swiftshader", "--hide-scrollbars",
           "--window-size=800,800", f"--virtual-time-budget={wait_ms}", f"--screenshot={png_path}",
           "file:///" + html_path.replace("\\", "/")]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    return "ok" if os.path.exists(png_path) else (r.stderr or r.stdout)[-300:]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", default="artifacts/api_key.txt")
    ap.add_argument("--arms", default="medium,off")
    ap.add_argument("--max-tokens", type=int, default=24576)
    ap.add_argument("--wait-ms", type=int, default=6000)
    ap.add_argument("--out", default=os.path.join("artifacts", "eval", "pagoda"))
    a = ap.parse_args()
    key = open(a.key_file, encoding="utf-8").read().strip()
    os.makedirs(a.out, exist_ok=True)
    for arm in a.arms.split(","):
        g = chat(a.base, key, arm, a.max_tokens)
        html = extract_html(g["content"])
        hp = os.path.abspath(os.path.join(a.out, f"pagoda_{arm}.html"))
        open(hp, "w", encoding="utf-8").write(html)
        pp = os.path.abspath(os.path.join(a.out, f"pagoda_{arm}.png"))
        status = render(hp, pp, a.wait_ms) if html else "empty answer"
        print(f"{arm:6} finish={g['finish']} tokens={g['tokens']} {g['seconds']}s html={len(html)} chars render={status}", flush=True)


if __name__ == "__main__":
    main()
