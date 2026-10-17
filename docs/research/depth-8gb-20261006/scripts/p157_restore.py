"""P157 repro: after a slot restore at depth, continue with N new tokens.

phase prime: cold request (the t1b document + Q1) then save to --file.
phase cont:  restore --file, then request 1's messages + answer A + a user turn of ~--new tokens of tool output + Q2.
"""
import argparse, json, os, sys, time, urllib.request
sys.path.insert(0, r"C:\bonsai\8gb\benchx")
os.environ.setdefault("BONSAI_REPO", r"C:\bonsai\bonsai-ada-surgery")
import t1b_slot  # noqa: E402
sys.path.insert(0, r"C:\bonsai\8gb")
import p155_turn  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--key-file", required=True)
ap.add_argument("--depth", type=int, required=True)
ap.add_argument("--phase", choices=["prime", "cont"], required=True)
ap.add_argument("--file", required=True)
ap.add_argument("--new", type=int, default=4000)
ap.add_argument("--state", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--tag", default="")
a = ap.parse_args()
base = "http://127.0.0.1:8080"
key = open(a.key_file).read().strip()
doc = t1b_slot.document(base, key, a.depth)
rec = {"tag": a.tag, "phase": a.phase, "depth": a.depth, "new": a.new}
try:
    if a.phase == "prime":
        ans, t, dt = t1b_slot.ask(base, key, doc)
        json.dump({"answer_a": ans}, open(a.state, "w", encoding="utf-8"))
        r, ds = t1b_slot.call(base, key, "/slots/0?action=save", {"filename": a.file})
        rec.update(prompt_n=t.get("prompt_n"), wall=round(dt, 1), save=r)
    else:
        r, dr = t1b_slot.call(base, key, "/slots/0?action=restore", {"filename": a.file})
        rec.update(restore=r, restore_s=round(dr, 2))
        A = json.load(open(a.state, encoding="utf-8"))["answer_a"]
        block = p155_turn.tool_block(1)
        reps = max(1, a.new // 3900)
        tool = (block * reps) if a.new >= 3900 else block[: max(40, a.new * 4)]
        msgs = [{"role": "user", "content": doc + t1b_slot.Q1}, {"role": "assistant", "content": A},
                {"role": "user", "content": tool + t1b_slot.Q2}]
        body = {"messages": msgs, "max_tokens": 64, "temperature": 0, "cache_prompt": True,
                "chat_template_kwargs": {"enable_thinking": False}}
        r, dt = t1b_slot.call(base, key, "/v1/chat/completions", body)
        t = r.get("timings", {})
        rec.update(prompt_n=t.get("prompt_n"), wall=round(dt, 1), answer=r["choices"][0]["message"]["content"])
except Exception as e:  # noqa: BLE001
    rec["error"] = repr(e)[:300]
print(json.dumps(rec), flush=True)
with open(a.out, "a", encoding="utf-8") as f:
    f.write(json.dumps(rec) + "\n")
