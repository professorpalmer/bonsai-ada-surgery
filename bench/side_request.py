"""A side request in the middle of a deep conversation: does the next turn read the whole prompt again?
Turn 1: a ~DEPTH-token conversation. Then a short unrelated request (a title request, as agent clients send).
Turn 2: the same conversation plus the assistant's answer and a new question. Prints the tokens each request
evaluated and its wall time. One slot: the side request takes the slot, and a big state that is over the prompt
cache limit is dropped. Two slots on a unified KV cache: the conversation's cells stay.

python bench/side_request.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 120000
"""
import argparse, json, os, sys, time, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from quick_tps import filler  # noqa: E402


def post(base, key, body):
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    r = json.loads(urllib.request.urlopen(req, timeout=3600).read())
    return r, time.time() - t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--depth", type=int, default=120000)
    ap.add_argument("--tag", default="")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    kw = {"temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}
    msgs = [{"role": "user", "content": filler(a.base, key, a.depth) + "Which report is mentioned first? Answer in one sentence."}]
    steps = [("turn1", {"messages": msgs, "max_tokens": 60, **kw})]
    for name, body in steps + [("side", None), ("turn2", None)]:
        if name == "side":
            body = {"messages": [{"role": "user", "content": "Write a 5-word title for a chat about log files."}], "max_tokens": 20, **kw}
        if name == "turn2":
            msgs = msgs + [{"role": "assistant", "content": ans}, {"role": "user", "content": "And which one is mentioned last?"}]
            body = {"messages": msgs, "max_tokens": 60, **kw}
        r, dt = post(a.base, key, body)
        t = r.get("timings", {})
        if name == "turn1":
            ans = r["choices"][0]["message"]["content"]
        print(json.dumps({"tag": a.tag, "step": name, "evaluated": t.get("prompt_n"), "cached": t.get("cache_n"),
                          "wall_s": round(dt, 1)}), flush=True)


if __name__ == "__main__":
    main()
