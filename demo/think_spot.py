"""Probe think-then-act budgets against the live llama-server.

Does not start a browser. One completion per arm: can the model think a little
and still emit the browser-use JSON action?
"""
from __future__ import annotations

import json
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KEY = (ROOT / "artifacts" / "api_key.txt").read_text(encoding="utf-8").strip()
BASE = "http://127.0.0.1:8080/v1/chat/completions"

PROMPT = """You are a browser agent. Browser state:
[3]<button>Add Harbor Mug to cart</button>
[4]<a>Go to checkout</a>
The cart is empty. Task: buy the Harbor Mug.
Reply with ONLY this JSON:
{"memory":"short plan","action":[{"click":{"index":3}}]}
"""

ARMS = [
    {"name": "off", "think": False, "effort": "medium", "budget": None, "max_tokens": 1024},
    {"name": "low-256", "think": True, "effort": "low", "budget": 256, "max_tokens": 1280},
    {"name": "low-512", "think": True, "effort": "low", "budget": 512, "max_tokens": 1536},
    {"name": "medium-512", "think": True, "effort": "medium", "budget": 512, "max_tokens": 1536},
    {"name": "medium-1024", "think": True, "effort": "medium", "budget": 1024, "max_tokens": 2048},
]


def run_arm(arm: dict) -> dict:
    kwargs = {"enable_thinking": arm["think"], "reasoning_effort": arm["effort"]}
    body: dict = {
        "model": "bonsai-2-27b",
        "temperature": 0.2,
        "top_p": 0.95,
        "max_tokens": arm["max_tokens"],
        "chat_template_kwargs": kwargs,
        "messages": [{"role": "user", "content": PROMPT}],
    }
    if arm["think"] and arm["budget"] is not None:
        body["reasoning_budget_tokens"] = arm["budget"]
        body["reasoning_budget_message"] = "Now take the next browser action as JSON."
    req = urllib.request.Request(
        BASE,
        data=json.dumps(body).encode("utf-8"),
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    elapsed = time.time() - t0
    msg = (data.get("choices") or [{}])[0].get("message") or {}
    content = msg.get("content") or ""
    think = msg.get("reasoning_content") or msg.get("reasoning") or ""
    usage = data.get("usage") or {}
    has_click = '"click"' in content and "3" in content
    has_json = "{" in content and "action" in content
    return {
        "arm": arm["name"],
        "elapsed_s": round(elapsed, 2),
        "finish": (data.get("choices") or [{}])[0].get("finish_reason"),
        "content_n": len(content),
        "think_n": len(think),
        "completion_tokens": usage.get("completion_tokens"),
        "reasoning_tokens": usage.get("reasoning_tokens") or usage.get("reasoning_content_tokens"),
        "has_json": has_json,
        "has_click": has_click,
        "content_head": content.strip().replace("\n", " ")[:180],
        "think_head": think.strip().replace("\n", " ")[:120],
    }


def main() -> None:
    out = []
    for arm in ARMS:
        rec = run_arm(arm)
        out.append(rec)
        print(json.dumps(rec), flush=True)
    dest = ROOT / "artifacts" / "demo" / "browser-use" / "think_spot.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {dest}", flush=True)


if __name__ == "__main__":
    main()
