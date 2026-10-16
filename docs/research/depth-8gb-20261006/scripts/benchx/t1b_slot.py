"""T1-b: slot save / restore, then a request that CONTINUES the saved conversation (no rollback needed).
phase prime:   request 1 on a cold server (answer A), save the slot, then request 2 on the same server (D2, the
               in-memory continuation that users get today). Writes A to --state.
phase restore: fresh server, restore, request 2 (B2). phase fresh: fresh server, no restore, request 2 (C2).
(T1-a header follows.)
phase prime:   one request on a cold server (answer A, prefill time), then POST /slots/0?action=save.
phase restore: on a fresh server, POST /slots/0?action=restore, then the same request (answer B, prompt_n, TTFT).
phase fresh:   on a fresh server, the same request with no restore (answer C: the determinism control).
Prints one JSON line per phase; --out appends it."""
import argparse, json, os, random, sys, time, urllib.request

sys.path.insert(0, os.path.join(os.environ.get("BONSAI_REPO", "."), "bench"))
from quick_tps import n_tokens  # noqa: E402

SUBJ = ["the archive", "a survey", "the committee", "one report", "the ledger", "a memo", "the register", "field notes"]
VERB = ["records", "lists", "mentions", "summarizes", "notes", "confirms", "tracks", "describes"]
OBJ = ["shipments", "rainfall totals", "meeting dates", "inventory counts", "repair logs", "visitor numbers",
       "budget lines", "soil samples", "route changes", "maintenance windows"]


def call(base, key, path, body, timeout=7200):
    req = urllib.request.Request(base.rstrip("/") + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    r = json.loads(urllib.request.urlopen(req, timeout=timeout).read())
    return r, time.time() - t0


def document(base, key, depth):
    rng = random.Random(11)
    codes = {v: f"{rng.randrange(1000, 10000)}" for v in range(1, 9)}
    sent = lambda i: f"{SUBJ[i % 8].capitalize()} {VERB[(i // 8) % 8]} {OBJ[(i // 64) % 10]} for entry {i}."
    n = max(1, depth // 12)
    n = max(1, int(n * depth / max(1, n_tokens(base, key, " ".join(sent(i) for i in range(n))))))
    slots = {int(n * (k + 0.5) / 8): v for k, v in enumerate(range(1, 9))}
    parts = []
    for i in range(n):
        if i in slots:
            parts.append(f"The access code for vault {slots[i]} is {codes[slots[i]]}.")
        parts.append(sent(i))
    return "Facility notes:\n" + " ".join(parts) + "\n\n"


Q1 = "List the access codes of vaults 1 to 8, one per line, as 'vault N: CODE'. Then stop."
Q2 = "Which of these vaults has the largest code? Answer with the vault number and the code only."


def ask(base, key, doc, answer_a=None):
    msgs = [{"role": "user", "content": doc + Q1}]
    if answer_a is not None:
        msgs += [{"role": "assistant", "content": answer_a}, {"role": "user", "content": Q2}]
    body = {"messages": msgs,
            "max_tokens": int(os.environ.get("T1B_MAX_TOKENS", "96")), "temperature": 0, "cache_prompt": True,
            "chat_template_kwargs": {"enable_thinking": os.environ.get("T1B_THINK") == "1"}}   # P153 copy: T1B_THINK=1 tests thinking on
    r, dt = call(base, key, "/v1/chat/completions", body)
    t = r.get("timings", {})
    return r["choices"][0]["message"]["content"], t, dt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--depth", type=int, required=True)
    ap.add_argument("--phase", choices=["prime", "restore", "fresh"], required=True)
    ap.add_argument("--file", required=True, help="slot file name (inside --slot-save-path)")
    ap.add_argument("--slot-dir", required=True, help="the server's --slot-save-path, to read the file size")
    ap.add_argument("--out", default="")
    ap.add_argument("--state", required=True, help="json file that keeps answer A between phases")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    doc = document(a.base, key, a.depth)
    rec = {"depth": a.depth, "phase": a.phase, "file": a.file}
    if a.phase == "restore":
        try:
            r, dt = call(a.base, key, "/slots/0?action=restore", {"filename": a.file})
            rec.update(restore_wall_s=round(dt, 2), restore=r)
        except Exception as e:  # noqa: BLE001
            rec.update(restore_error=str(e)[:300])
    if a.phase == "prime":
        ans, t, dt = ask(a.base, key, doc)
        rec.update(answer_a=ans, a_prompt_n=t.get("prompt_n"), a_prompt_ms=t.get("prompt_ms"))
        json.dump({"answer_a": ans}, open(a.state, "w", encoding="utf-8"))
        try:
            r, dts = call(a.base, key, "/slots/0?action=save", {"filename": a.file})
            p = os.path.join(a.slot_dir, a.file)
            rec.update(save_wall_s=round(dts, 2), save=r, file_mib=round(os.path.getsize(p) / 2**20) if os.path.exists(p) else None)
        except Exception as e:  # noqa: BLE001
            rec.update(save_error=str(e)[:300])
    answer_a = json.load(open(a.state, encoding="utf-8"))["answer_a"]
    ans, t, dt = ask(a.base, key, doc, answer_a)
    rec.update(answer=ans, prompt_n=t.get("prompt_n"), prompt_ms=t.get("prompt_ms"), request_wall_s=round(dt, 2))
    print(json.dumps(rec), flush=True)
    if a.out:
        with open(a.out, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec) + "\n")


if __name__ == "__main__":
    main()
