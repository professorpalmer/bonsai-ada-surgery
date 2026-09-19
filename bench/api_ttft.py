"""Measure TTFT and decode TPS against a running llama-server /v1 endpoint."""
from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8080")
    parser.add_argument("--key-file", default="")
    parser.add_argument("--prompt-tokens", type=int, default=2048)
    parser.add_argument("--max-tokens", type=int, default=64)
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    key = ""
    if args.key_file:
        key = Path(args.key_file).read_text(encoding="utf-8").strip()
    word = "bandwidth "
    prompt = ("Measure TTFT on a long prefix. " + word * max(1, args.prompt_tokens // 2)).strip()
    body = {
        "model": "bonsai-2-27b",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": args.max_tokens,
        "stream": True,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(
        args.base.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", **({"Authorization": f"Bearer {key}"} if key else {})},
        method="POST",
    )
    t0 = time.perf_counter()
    ttft = None
    chunks = 0
    with urllib.request.urlopen(req, timeout=600) as resp:
        for raw in resp:
            line = raw.decode("utf-8", errors="replace").strip()
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            if ttft is None:
                ttft = time.perf_counter() - t0
            chunks += 1
    total = time.perf_counter() - t0
    decode = max(total - (ttft or total), 1e-6)
    result = {
        "base": args.base,
        "prompt_chars": len(prompt),
        "max_tokens": args.max_tokens,
        "ttft_s": ttft,
        "total_s": total,
        "stream_chunks": chunks,
        "approx_tps": (chunks / decode) if chunks else None,
    }
    text = json.dumps(result, indent=2)
    print(text)
    if args.out:
        Path(args.out).write_text(text + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
