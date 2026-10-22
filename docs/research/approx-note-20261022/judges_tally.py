"""The blind judge replies of approx-note-20261022 (verdict letters for pairs 1-7, as each judge answered), tallied:
a cell is won or lost only when both orders agree. python judges_tally.py [OUT.jsonl]"""
import json
import sys

PROMPTS = ["p1_story", "p2_chapter", "p4_blog", "p6_save_story", "p7_save_essay", "p8_save_chapter", "p10_save_long"]
V = {
    ("A", 5): ("AAABABA", "BBBBBBB"), ("A", 6): ("ABBBBBA", "BAAAAAB"), ("A", 7): ("AABAABB", "BBAABBA"),
    ("A2", 8): ("ABABABA", "BABBBAB"), ("A2", 9): ("ABBBAAA", "BABBBAB"),
    ("A2", 10): ("AAAABAB", "BBBBBBA"), ("A2", 11): ("AAABBAB", "BBBAABB"), ("A2", 12): ("ABBABBA", "BAABAAB"),
}   # (arm_first, M_first)
rows = []
for (arm, seed), (af, mf) in V.items():
    for i, p in enumerate(PROMPTS):
        x = "arm" if af[i] == "A" else "M"      # arm_first: A is the arm
        y = "arm" if mf[i] == "B" else "M"      # M_first: B is the arm
        rows.append({"arm": arm, "seed": seed, "prompt": p, "arm_first": af[i], "M_first": mf[i],
                     "result": x if x == y else "even"})
if len(sys.argv) > 1:
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
for label, seeds in (("A, seeds 5-7", (5, 6, 7)), ("A', seeds 8-9", (8, 9)), ("A', seeds 10-12", (10, 11, 12))):
    rs = [r for r in rows if r["seed"] in seeds]
    print(label, "won", sum(r["result"] == "arm" for r in rs), "lost", sum(r["result"] == "M" for r in rs),
          "even", sum(r["result"] == "even" for r in rs))
a_share = sum(1 for r in rows for v in (r["arm_first"], r["M_first"]) if v == "A")
print("'A' answers:", a_share, "of", 2 * len(rows))
