"""Wrong answers where dense is right (the T5 R2 clause), from P170-driver receipts. Written for the records of
P183-P188 to check the offline table of #138 (comment 6243287633); the table at the time was scored inline.

Classes per item: ok = the driver's grade; else code: "wrong" if the answer has a number (the driver grades the first
number), else "miss"; prose: "miss" if the answer says the text has no such fact (MISS below), else "wrong".
Reference: code = the items right in P170 dense; prose = the items right in both P170 and P183 dense (--ref183 adds the
count against P183 dense alone, the run with the T5 settings bin-t5r3 + BONSAI_SPARSE=0).

python scripts/wrong_scan.py --receipts C:/bonsai/8gb/receipts [--ref183]
"""
import argparse, json, os, re

ap = argparse.ArgumentParser()
ap.add_argument("--receipts", default="C:/bonsai/8gb/receipts")
ap.add_argument("--ref183", action="store_true")
a = ap.parse_args()

MISS = re.compile(r"does not (contain|state|mention|provide|include|specify|appear|have)|not (found|mentioned|stated|"
                  r"specified|provided|present|contain)|no (mention|information|such)|cannot (find|determine|be "
                  r"determined)|is not (in|mentioned|stated|specified)|there is no|unable to|I (cannot|can't|could "
                  r"not|couldn't)|not explicitly", re.I)


def load(rel):
    rows = [json.loads(l) for l in open(os.path.join(a.receipts, rel), encoding="utf-8")]
    return {r["item"]: r for r in rows if r.get("arm") == "dense"}  # p170/*.jsonl also holds the lex arm


def cls(r, s):
    if r.get("ok"):
        return "ok"
    ans = r.get("answer", "")
    if s == "code":
        return "wrong" if re.findall(r"-?\d+(?:\.\d+)?", ans) else "miss"
    return "miss" if MISS.search(ans) else "wrong"


CODE = {"window 16k (P174b)": "p174b/code.jsonl", "window 32k (P182)": "p182/code.jsonl",
        "32k + 8 dense (P187)": "p187/code.jsonl", "dense again (P188)": "p188/code.jsonl"}
PROSE = {"window 16k (P174b)": "p174b/prose.jsonl", "window 32k (P178 R-4)": "p178/prose_w32.jsonl",
         "window 32k (P183)": "p183/wprose.jsonl", "16k + dense 15:31:47:63 (P181 e4)": "p181/prose_e4.jsonl",
         "32k + dense 15:31:47:63 (P181 w32e4)": "p181/prose_w32e4.jsonl",
         "16k + dense 3:7:11:15 (P182 f4)": "p182/f4.jsonl", "16k + dense 51:55:59:63 (P181 l4)": "p181/prose_l4.jsonl",
         "32k + 8 dense (P187)": "p187/prose.jsonl", "dense again (P188)": "p188/prose.jsonl"}

c170, p170, p183 = load("p170/code.jsonl"), load("p170/prose.jsonl"), load("p183/dprose.jsonl")
ref_code = [k for k in sorted(c170) if c170[k]["ok"]]
ref_prose = [k for k in sorted(p170) if p170[k]["ok"] and p183[k]["ok"]]
ref_183 = [k for k in sorted(p183) if p183[k]["ok"]]
print("reference code (P170 right):", ref_code)
print("reference prose (right in P170 and P183):", ref_prose)
for name, rel in CODE.items():
    d = load(rel)
    print("code ", f"{name:38}", "ok", sum(d[k]["ok"] for k in d), "wrong where dense is right",
          [k for k in ref_code if cls(d[k], "code") == "wrong"])
for name, rel in PROSE.items():
    d = load(rel)
    line = ["prose", f"{name:38}", "ok", sum(d[k]["ok"] for k in d), "wrong where dense is right",
            [k for k in ref_prose if cls(d[k], "prose") == "wrong"]]
    if a.ref183:
        line += ["| vs P183 alone", [k for k in ref_183 if cls(d[k], "prose") == "wrong"]]
    print(*line)
for name, d, s in (("code P188", load("p188/code.jsonl"), "code"), ("prose P183", p183, "prose")):
    print("dense wrong,", name, [k for k in sorted(d) if cls(d[k], s) == "wrong"])
print("P170 vs P183 dense prose flips (item, P170, P183):",
      [(k, cls(p170[k], "prose"), cls(p183[k], "prose")) for k in sorted(p170) if p170[k]["ok"] != p183[k]["ok"]])
