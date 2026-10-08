"""H1 (HyperQwen idea): drafting from the context. One arm per server start; this script runs the workloads.

Workloads, thinking off, greedy:
  quote  4 items: a ~150-line CPython stdlib file, "output the complete file again with one comment line added"
         (the answer quotes the prompt; agent file rewrites look like this)
  edit   4 items: the same files, one edit tool call whose oldText quotes 3-6 lines of the file
  plain  the 3 quick_tps prompts (code, prose, bash; nothing to quote)
Per request: decode tok/s, completion tokens, draft tokens proposed / accepted, and a hash of the text (a draft only
changes speed; arms must give the same text, up to the rounding-level differences MTP itself has).

  python bench/lookup_ab.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag mtp --out receipts/lookup_ab.jsonl
"""
import argparse, ast, hashlib, json, os, time, urllib.request

LIB = os.path.dirname(os.__file__)
FILES = ["textwrap.py", "shlex.py", "fnmatch.py", "csv.py"]
PLAIN = [("code", "Write a 300-line Python module implementing an LRU cache with tests. Code only.", 400),
         ("prose", "Write a detailed 800 word essay on the history of the transistor.", 400),
         ("bash", "Write a bash script that rotates logs in /var/log with size and age limits, with comments.", 400)]
EDIT_TOOL = [{"type": "function", "function": {"name": "edit", "description":
              "Replace text in a file. oldText must match the file exactly and occur once.",
              "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "oldText": {"type": "string"},
                             "newText": {"type": "string"}}, "required": ["path", "oldText", "newText"]}}}]


def windows():
    out = []
    for rel in FILES:
        src = open(os.path.join(LIB, rel), encoding="utf-8").read()
        lines = src.splitlines(keepends=True)
        fns = sorted((n for n in ast.walk(ast.parse(src)) if isinstance(n, ast.FunctionDef) and 8 <= n.end_lineno - n.lineno <= 30),
                     key=lambda n: n.lineno)
        fn = fns[len(fns) // 2]
        a = max(1, fn.lineno - 60)
        out.append({"path": rel, "fn": fn.name, "text": "".join(lines[a - 1:a + 149])})
    return out


def post(base, key, body):
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    r = json.loads(urllib.request.urlopen(req, timeout=1800).read())
    return r, time.time() - t0


def run(base, key, tag, out, depth=0):
    pre = ""
    if depth:
        import sys
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from quick_tps import filler
        pre = filler(base, key, depth)
    jobs = []
    for w in windows():
        jobs.append(("quote", w["path"], {"messages": [{"role": "user", "content": pre +
            f"Here is the file `{w['path']}`:\n\n```python\n{w['text']}```\n\nOutput the complete file again with exactly one "
            f"change: add the comment line `# reviewed` as the first line of the body of `{w['fn']}`. Output only the "
            "file, in one python code block."}], "max_tokens": 4096}))
        jobs.append(("edit", w["path"], {"messages": [
            {"role": "user", "content": pre + f"In `{w['path']}`, add the comment line `# reviewed` as the first line of the body "
             f"of `{w['fn']}`. Use one edit call. Include the def line and the next four lines in oldText."},
            {"role": "assistant", "content": "", "tool_calls": [{"id": "r1", "type": "function", "function":
             {"name": "read", "arguments": json.dumps({"path": w["path"]})}}]},
            {"role": "tool", "tool_call_id": "r1", "name": "read", "content": w["text"]}],
            "tools": EDIT_TOOL + [{"type": "function", "function": {"name": "read", "description": "Read a file.",
             "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}}],
            "max_tokens": 2048}))
    for name, p, n in PLAIN:
        jobs.append(("plain", name, {"messages": [{"role": "user", "content": pre + p}], "max_tokens": n}))
    # requests with tools last: a tool list changes the start of the prompt, and each switch re-reads the whole context
    jobs.sort(key=lambda j: {"quote": 0, "plain": 1, "edit": 2}[j[0]])
    kinds = os.environ.get("LOOKUP_KINDS")   # e.g. "quote,plain": skip the tool-call jobs (one prefill per arm)
    if kinds:
        jobs = [j for j in jobs if j[0] in kinds.split(",")]
    for kind, item, body in jobs:
        body.update(temperature=0, top_p=1, chat_template_kwargs={"enable_thinking": False})
        r, dt = post(base, key, body)
        t, m = r.get("timings") or {}, r["choices"][0]["message"]
        text = (m.get("content") or "") + json.dumps(m.get("tool_calls") or [], sort_keys=True)
        rec = {"tag": tag, "depth": depth, "kind": kind, "item": item, "tps": round(t.get("predicted_per_second") or 0, 1),
               "n": t.get("predicted_n"), "draft_n": t.get("draft_n"), "draft_acc": t.get("draft_n_accepted"),
               "sha": hashlib.sha256(text.encode()).hexdigest()[:12], "wall": round(dt, 1)}
        print(json.dumps(rec), flush=True)
        with open(out, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec) + "\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--depth", type=int, default=0)
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    post(a.base, key, {"messages": [{"role": "user", "content": "Say hi."}], "max_tokens": 8})   # warm-up
    run(a.base, key, a.tag, a.out, a.depth)
