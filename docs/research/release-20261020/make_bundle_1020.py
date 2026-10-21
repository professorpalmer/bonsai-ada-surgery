"""Bundle 20261020 (layer + launcher only; every bin/ file from 1019c). Was: bundle 20261019b (8 GB: replay + draft 2 / 2 by default; engine 810d93e5aa = 0070 + 0071).
Outside docs/: the entries of bundle-20261019a (engine bin/ files from the release build, the CUDA runtime and other
bin/ files from 1019a, the rest from git archive of the launcher branch head in %TEMP%\\rel-1019c-src).
docs/: every .md / .png / card .html of the restructured docs, except research/, receipts/ and cards/legacy/.
Then: every relative link in the zip's .md files must resolve inside the zip."""
import hashlib, os, posixpath, re, zipfile

REPO = r"<checkout>"
SRC = os.path.join(os.environ["TEMP"], "rel-1020-src")
OLD = os.path.join(REPO, r"artifacts\release\bonsai-bundle-win-x64-20261019c.zip")
NEW = os.path.join(REPO, r"artifacts\release\bonsai-bundle-win-x64-20261020.zip")
BUILD = r"<checkout>\bin"
assert os.path.abspath(NEW) != os.path.abspath(OLD), "NEW must not be OLD"
ENGINE = set()   # no engine change: every bin/ file from 1019b
_UNUSED = {"ggml-base.dll", "ggml-cpu.dll", "ggml-cuda.dll", "ggml.dll", "llama-common.dll", "llama-server-impl.dll",
          "llama-server.exe", "llama.dll", "mtmd.dll", "test-backend-ops.exe"}
STAMP = (2026, 10, 20, 21, 0, 0)

src = zipfile.ZipFile(OLD)
entries = {}
for n in src.namelist():
    if n.endswith("/") or n.startswith("docs/"):
        continue
    parts = n.split("/")
    if parts[0] == "bin":
        entries[n] = open(os.path.join(BUILD, parts[1]), "rb").read() if parts[1] in ENGINE else src.read(n)
    else:
        p = os.path.join(SRC, *parts)
        assert os.path.exists(p), n
        data = open(p, "rb").read()
        if b"\r\n" not in src.read(n):
            data = data.replace(b"\r\n", b"\n")
        elif b"\r\n" not in data:
            data = data.replace(b"\n", b"\r\n")
        entries[n] = data
skip = ("docs/research/", "docs/receipts/", "docs/cards/legacy/")
for root, _, files in os.walk(os.path.join(SRC, "docs")):
    for f in files:
        rel = os.path.relpath(os.path.join(root, f), SRC).replace(os.sep, "/")
        if rel.startswith(skip) or not (f.endswith((".md", ".png")) or (rel.startswith("docs/cards/") and f.endswith((".html", ".css", ".js")))):
            continue
        entries[rel] = open(os.path.join(root, f), "rb").read().replace(b"\r\n", b"\n") if f.endswith(".md") else open(os.path.join(root, f), "rb").read()

# R1 part: relative links in .md files resolve inside the zip (links into research/receipts are allowed to go to GitHub)
bad = []
for n, data in entries.items():
    if not n.endswith(".md"):
        continue
    for m in re.finditer(rb"\]\(([^)\s#]+)(?:#[^)]*)?\)", data):
        t = m.group(1).decode("utf-8", "replace")
        if re.match(r"^[a-z]+:", t) or t.startswith("/"):
            continue
        p = posixpath.normpath(posixpath.join(posixpath.dirname(n), t))
        if p.startswith(skip) or p.rstrip("/") in ("docs/research", "docs/receipts"):
            continue
        if p.split("/")[0] in ("patches", "surgery", ".github"):   # repo-only folders (amendment 17:50)
            continue
        if p not in entries and not any(e.startswith(p.rstrip("/") + "/") for e in entries):
            bad.append(f"{n} -> {t}")
out = zipfile.ZipFile(NEW, "w", zipfile.ZIP_DEFLATED, compresslevel=6)
for n in sorted(entries):
    out.writestr(zipfile.ZipInfo(n, date_time=STAMP), entries[n], zipfile.ZIP_DEFLATED)
out.close()
old_names = set(x for x in src.namelist() if not x.endswith("/"))
print(len(entries), "entries; new:", len(set(entries) - old_names), "removed:", len(old_names - set(entries)))
print("broken relative links:", len(bad))
for b in bad[:30]:
    print("  ", b)
print("size", os.path.getsize(NEW), "sha256", hashlib.sha256(open(NEW, "rb").read()).hexdigest())
