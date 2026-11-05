"""R3: does an end-of-generation token end the turn inside the think block?

Thinking on, `<|im_end|>` pushed up by --bias with logit_bias, raw text (reasoning_format none), n tries.
1026 engine: the turn can end with the block open (no `</think>`, no answer). 0073: the block has to close first.
    python eog_think_test.py --base http://127.0.0.1:8080 --key-file <root>/artifacts/api_key.txt --out r3-<arm>.jsonl
Prints one line per try and a summary: open (ended inside the block) and answered (text after `</think>`).
"""
import argparse
import json
import time
import urllib.request

PROMPT = "A train leaves at 09:40 and the trip takes 2 h 55 min. When does it arrive? Check your arithmetic."


def post(base, key, path, body):
    req = urllib.request.Request(base + path, json.dumps(body).encode(),
                                 {"Content-Type": "application/json", "Authorization": "Bearer " + key})
    with urllib.request.urlopen(req, timeout=900) as r:
        return json.loads(r.read())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--n", type=int, default=5)
    ap.add_argument("--bias", type=float, default=8.0)
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    eot = post(a.base, key, "/tokenize", {"content": "<|im_end|>", "parse_special": True})["tokens"]
    assert len(eot) == 1, eot
    n_open = n_answered = 0
    with open(a.out, "a", encoding="utf-8") as out:
        for i in range(a.n):
            t0 = time.time()
            r = post(a.base, key, "/v1/chat/completions", {
                "messages": [{"role": "user", "content": PROMPT}], "max_tokens": 4096,
                "reasoning_format": "none", "logit_bias": {str(eot[0]): a.bias}})
            ch = r["choices"][0]
            text = ch["message"].get("content") or ""
            closed = "</think>" in text
            answer = text.split("</think>", 1)[1].strip() if closed else ""
            n_open += not closed
            n_answered += bool(answer)
            row = {"try": i, "bias": a.bias, "eot": eot[0], "finish": ch.get("finish_reason"), "closed": closed,
                   "answered": bool(answer), "answer": answer[-300:], "chars": len(text), "tail": text[-200:],
                   "completion_tokens": (r.get("usage") or {}).get("completion_tokens"), "s": round(time.time() - t0, 1)}
            out.write(json.dumps(row, ensure_ascii=False) + "\n")
            out.flush()
            print(json.dumps({k: row[k] for k in ("try", "bias", "finish", "closed", "answered", "completion_tokens")}),
                  flush=True)
    print(f"summary bias {a.bias}: open {n_open} / {a.n}, answered {n_answered} / {a.n}", flush=True)


if __name__ == "__main__":
    main()
