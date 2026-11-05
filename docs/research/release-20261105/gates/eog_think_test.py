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
    ap.add_argument("--zero", action="store_true", help="first one try at bias 0 (try -1)")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    eot = post(a.base, key, "/tokenize", {"content": "<|im_end|>", "parse_special": True})["tokens"]
    assert len(eot) == 1, eot
    # "open" = the turn stopped (finish "stop") with no `</think>`: an end-of-generation token inside the block.
    # A length cut or an error is "other", never "open". Try -1 (bias 0) must close the block and answer.
    n_open = n_closed = n_answered = n_other = 0
    zero = None
    with open(a.out, "a", encoding="utf-8") as out:
        for i in range(-1 if a.zero else 0, a.n):
            bias = 0.0 if i < 0 else a.bias
            t0 = time.time()
            # the launcher's floor raises max_tokens to the think budget + 4096 (24,576 by default)
            r = post(a.base, key, "/v1/chat/completions", {
                "messages": [{"role": "user", "content": PROMPT}], "max_tokens": 4096,
                "reasoning_format": "none", "logit_bias": {str(eot[0]): bias}})
            ch = r["choices"][0]
            text = ch["message"].get("content") or ""
            finish = ch.get("finish_reason")
            closed = "</think>" in text
            answer = text.split("</think>", 1)[1].strip() if closed else ""
            kind = "closed" if closed else "open" if finish == "stop" else "other"
            row = {"try": i, "bias": bias, "eot": eot[0], "finish": finish, "kind": kind, "closed": closed,
                   "answered": bool(answer), "answer": answer[-300:], "chars": len(text), "tail": text[-200:],
                   "completion_tokens": (r.get("usage") or {}).get("completion_tokens"), "s": round(time.time() - t0, 1)}
            out.write(json.dumps(row, ensure_ascii=False) + "\n")
            out.flush()
            print(json.dumps({k: row[k] for k in ("try", "bias", "finish", "kind", "answered", "completion_tokens")}),
                  flush=True)
            if i < 0:
                zero = row
                continue
            n_open += kind == "open"
            n_closed += kind == "closed"
            n_other += kind == "other"
            n_answered += bool(answer)
    z = "" if zero is None else f"bias 0: {zero['kind']}, answered {zero['answered']}; "
    print(f"summary {z}bias {a.bias}: open {n_open} closed {n_closed} other {n_other} / {a.n}, "
          f"answered {n_answered} / {a.n}", flush=True)


if __name__ == "__main__":
    main()
