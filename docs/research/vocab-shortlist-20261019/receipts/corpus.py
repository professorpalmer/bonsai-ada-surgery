"""Collect the shortlist corpus: build set and held-out set, one text file per category.
python corpus.py OUTDIR
Held out (never counted): the answers of artifacts/humaneval-r0059 and every fifth Markdown doc of the repo."""
import glob, json, os, sys

OUT = sys.argv[1]
SERVE = r"<checkout>"
SAA = r"<checkout>"
ENGINE = r"<checkout>"
HELD_HE = "humaneval-r0059"
os.makedirs(OUT, exist_ok=True)


def write(name, texts):
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        n = 0
        for t in texts:
            f.write(t)
            f.write("\n\n")
            n += len(t)
    print(f"{name}: {n:,} chars")


def he(held):
    for p in sorted(glob.glob(SERVE + "/artifacts/humaneval-*/samples.jsonl")):
        if (os.path.basename(os.path.dirname(p)) == HELD_HE) != held:
            continue
        for line in open(p, encoding="utf-8"):
            try:
                c = json.loads(line).get("content") or ""
            except ValueError:
                continue
            if c:
                yield c


def files(patterns, skip=lambda p: False, limit=None):
    seen = 0
    for pat in patterns:
        for p in sorted(glob.glob(pat, recursive=True)):
            if skip(p) or not os.path.isfile(p) or os.path.getsize(p) > 2_000_000:
                continue
            try:
                t = open(p, encoding="utf-8").read()
            except (UnicodeDecodeError, OSError):
                continue
            seen += len(t)
            yield t
            if limit and seen >= limit:
                return


DOCS = sorted(glob.glob(SAA + "/docs/**/*.md", recursive=True))
held_doc = lambda p: p in DOCS[::5]   # every fifth doc is held out
write("model_answers.txt", he(False))
write("code_python.txt", files([SAA + "/layer/**/*.py", SAA + "/suite/**/*.py", SAA + "/bench/**/*.py", SAA + "/tests/**/*.py",
                                SERVE + "/bench/**/*.py"]))
write("code_cpp.txt", files([ENGINE + "/src/**/*.cpp", ENGINE + "/src/**/*.h", ENGINE + "/common/**/*.cpp",
                             ENGINE + "/ggml/src/ggml-cuda/*.cu", ENGINE + "/tools/server/*.cpp"], limit=12_000_000))
write("prose_docs.txt", files([SAA + "/docs/**/*.md", SAA + "/README.md"], skip=held_doc))
write("prose_engine_docs.txt", files([ENGINE + "/docs/**/*.md", ENGINE + "/tools/**/README.md", ENGINE + "/README.md"]))
write("heldout_answers.txt", he(True))
write("heldout_docs.txt", files(DOCS[::5]))
