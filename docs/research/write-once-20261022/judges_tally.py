"""The 12 blind judge replies of write-once-20261022 (verbatim verdict letters), tallied: a cell is won or lost only when
both orders agree. Writes judges.jsonl and prints the tally."""
import json, sys
OUT = sys.argv[1]
V = {  # (arm, seed, order): verdicts for pairs 1..10, as the judge answered (A / B / TIE)
    ("P", 5, "arm_first"): "BBBABBBBBB", ("P", 5, "M_first"): "AAABAAAAAA",
    ("P", 6, "arm_first"): "BBBBBBBBAA", ("P", 6, "M_first"): "AAAAAAAABB",
    ("P", 7, "arm_first"): "BBBBBBABBB", ("P", 7, "M_first"): "AAABAAAAAA",
    ("C", 5, "arm_first"): "BABABBBBBB", ("C", 5, "M_first"): "AAABAABAAA",
    ("C", 6, "arm_first"): "ABAAABBBAA", ("C", 6, "M_first"): "BABBAAAAAB",
    ("C", 7, "arm_first"): "AAABABABBA", ("C", 7, "M_first"): "BBBABABBAB",
}
PROMPTS = ["p1_story", "p2_chapter", "p3_poem", "p4_blog", "p5_long", "p6_save_story", "p7_save_essay",
           "p8_save_chapter", "p9_huge", "p10_save_long"]
rows, tally = [], {}
for (arm, seed, order), s in V.items():
    for i, v in enumerate(s):
        winner = "tie" if v == "T" else ("arm" if (v == "A") == (order == "arm_first") else "M")
        rows.append({"arm": arm, "seed": seed, "order": order, "prompt": PROMPTS[i], "verdict": v, "winner": winner})
with open(OUT, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
for arm in ("P", "C"):
    won = lost = even = 0
    for seed in (5, 6, 7):
        for p in PROMPTS:
            w = {r["order"]: r["winner"] for r in rows if r["arm"] == arm and r["seed"] == seed and r["prompt"] == p}
            if w["arm_first"] == w["M_first"] == "arm":
                won += 1
            elif w["arm_first"] == w["M_first"] == "M":
                lost += 1
            else:
                even += 1
    a_share = sum(1 for r in rows if r["arm"] == arm and r["verdict"] == "A")
    print(arm, "won", won, "lost", lost, "even", even, "| 'A' answers", a_share, "of 60")
