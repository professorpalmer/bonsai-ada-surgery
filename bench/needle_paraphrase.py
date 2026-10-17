"""Facts deep in a long prompt, asked in OTHER words: one ~DEPTH-token filler (as bench/needle_depth.py) with N facts
("The beekeeper keeps a safe whose combination is 4182.") at evenly spaced positions, then one question per fact
that names the person by a description, not by the word in the text ("Which 4-digit combination opens the safe of the
person who raises honey-making insects?"). The only words a fact and its question share ("safe", "combination") are
in every fact, so word overlap cannot tell the facts apart; only the meaning does. Exact match on the 4-digit code;
a wrong code (another fact's, or any 4 digits) is reported apart from a miss.

Made to test query-dependent token selection that matches words (T4 fast read, issue #138) against the full read.

python bench/needle_paraphrase.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 245000 --n 24 --tag dense
"""
import argparse, json, os, random, re, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from quick_tps import n_tokens  # noqa: E402
from needle_depth import post, sentence  # noqa: E402

# (the word in the text, the description in the question); no content word of a description is in its fact
PEOPLE = [
    ("beekeeper", "the person who raises honey-making insects"),
    ("lighthouse keeper", "the person who tends the coastal light tower"),
    ("blacksmith", "the person who forges iron at an anvil"),
    ("cartographer", "the person who draws maps"),
    ("astronomer", "the person who studies the stars through a telescope"),
    ("baker", "the person who makes bread every morning"),
    ("fisherman", "the person who catches fish from a boat"),
    ("librarian", "the person who looks after the books of a lending collection"),
    ("carpenter", "the person who builds furniture out of wood"),
    ("surgeon", "the doctor who operates on patients"),
    ("pilot", "the person who flies airplanes"),
    ("gardener", "the person who looks after the plants and flowers"),
    ("tailor", "the person who sews clothes to measure"),
    ("shepherd", "the person who herds sheep in the hills"),
    ("locksmith", "the person who repairs door mechanisms and cuts keys"),
    ("potter", "the person who shapes clay into bowls"),
    ("jeweler", "the person who sets gems into rings"),
    ("firefighter", "the person who puts out burning buildings"),
    ("watchmaker", "the person who repairs clocks and timepieces"),
    ("sculptor", "the artist who carves statues from marble"),
    ("chemist", "the scientist who mixes substances in a laboratory"),
    ("violinist", "the musician who plays a bowed four-string instrument"),
    ("miner", "the worker who digs coal underground"),
    ("translator", "the person who renders texts from one language into another"),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--depth", type=int, default=160000)
    ap.add_argument("--n", type=int, default=24)
    ap.add_argument("--tag", default="")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    if a.n > len(PEOPLE):
        sys.exit(f"--n at most {len(PEOPLE)}")
    key = open(a.key_file).read().strip()
    rng = random.Random(11)
    codes = {v: f"{rng.randrange(1000, 10000)}" for v in range(1, a.n + 1)}
    n_sent = max(1, a.depth // 12)
    probe = " ".join(sentence(i) for i in range(n_sent))
    n_sent = max(1, int(n_sent * a.depth / max(1, n_tokens(a.base, key, probe))))
    slots = {int(n_sent * (k + 0.5) / a.n): v for k, v in enumerate(range(1, a.n + 1))}
    parts = []
    for i in range(n_sent):
        if i in slots:
            v = slots[i]
            parts.append(f"The {PEOPLE[v - 1][0]} keeps a safe whose combination is {codes[v]}.")
        parts.append(sentence(i))
    doc = "Facility notes:\n" + " ".join(parts) + "\n\n"
    all_codes = set(codes.values())
    ok = wrong = 0
    for v in range(1, a.n + 1):
        q = f"Which 4-digit combination opens the safe of {PEOPLE[v - 1][1]}? Answer with the 4 digits only."
        body = {"messages": [{"role": "user", "content": doc + q}], "max_tokens": 16, "temperature": 0,
                "chat_template_kwargs": {"enable_thinking": False}}
        r, dt = post(a.base, key, body)
        ans = r["choices"][0]["message"]["content"] or ""
        got = re.findall(r"\d{4}", ans)
        hit = bool(got) and got[0] == codes[v]
        kind = "ok" if hit else ("wrong_other_fact" if got and got[0] in all_codes else ("wrong" if got else "miss"))
        ok += hit
        wrong += kind.startswith("wrong")
        rec = {"tag": a.tag, "depth": a.depth, "fact": v, "who": PEOPLE[v - 1][0], "position_frac": round((v - 0.5) / a.n, 3),
               "want": codes[v], "answer": ans.strip()[:40], "ok": hit, "kind": kind,
               "evaluated": r.get("timings", {}).get("prompt_n"), "wall_s": round(dt, 1)}
        print(json.dumps(rec), flush=True)
        if a.out:
            with open(a.out, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec) + "\n")
    print(json.dumps({"tag": a.tag, "depth": a.depth, "correct": ok, "wrong": wrong, "miss": a.n - ok - wrong, "of": a.n}), flush=True)


if __name__ == "__main__":
    main()
