"""Bundle 20261123 (engine serve/tier-fix: the tier write-back fix, F1 switch off, MMID row bound, host-memory fallback;
launcher window guard). Was: bundle 20261105.
Outside docs/: the entries of bundle-20261105. bin/: EVERY engine file from the neutral-path release build (the kernels
changed, and the old files held local source paths); the CUDA runtime files and cloudflared.exe from 1105. Other files:
from git archive of the release branch head in <SRC>. New: licenses/web-ui-THIRD-PARTY.txt.
    set BONSAI_REPO=<serve checkout> & set BONSAI_BUILD=<release build folder> & set BONSAI_SRC=<git archive folder> & python make_bundle_1123.py
docs/: every .md / .png / card .html of the docs, except research/, receipts/ and cards/legacy/.
Then: every relative link in the zip's .md files must resolve inside the zip, and no entry holds the local user name."""
import getpass, hashlib, os, posixpath, re, zipfile

REPO = os.environ["BONSAI_REPO"]
SRC = os.environ["BONSAI_SRC"]
OLD = os.path.join(REPO, "artifacts", "release", "bonsai-bundle-win-x64-20261105.zip")
NEW = os.path.join(REPO, "artifacts", "release", "bonsai-bundle-win-x64-20261123.zip")
BUILD = os.path.join(os.environ["BONSAI_BUILD"], "bin")
assert os.path.abspath(NEW) != os.path.abspath(OLD), "NEW must not be OLD"
ENGINE = {"ggml-base.dll", "ggml-cpu.dll", "ggml-cuda.dll", "ggml.dll", "llama.dll", "llama-common.dll", "mtmd.dll",
          "llama-server-impl.dll", "llama-server.exe", "test-backend-ops.exe"}
STAMP = (2026, 11, 23, 12, 0, 0)
ADD = ["licenses/web-ui-THIRD-PARTY.txt"]

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
assert ENGINE <= {n.split("/")[1] for n in entries if n.startswith("bin/")}, "an engine file is not in the 1105 bin/"
for n in ADD:
    entries[n] = open(os.path.join(SRC, *n.split("/")), "rb").read().replace(b"\r\n", b"\n")
skip = ("docs/research/", "docs/receipts/", "docs/cards/legacy/")
for root, _, files in os.walk(os.path.join(SRC, "docs")):
    for f in files:
        rel = os.path.relpath(os.path.join(root, f), SRC).replace(os.sep, "/")
        if rel.startswith(skip) or not (f.endswith((".md", ".png")) or (rel.startswith("docs/cards/") and f.endswith((".html", ".css", ".js")))):
            continue
        entries[rel] = open(os.path.join(root, f), "rb").read().replace(b"\r\n", b"\n") if f.endswith(".md") else open(os.path.join(root, f), "rb").read()

# relative links in .md files resolve inside the zip (links into research/receipts are allowed to go to GitHub)
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
        if p.split("/")[0] in ("patches", "surgery", ".github"):   # repo-only folders (release-20261019b exemptions)
            continue
        if p not in entries and not any(e.startswith(p.rstrip("/") + "/") for e in entries):
            bad.append(f"{n} -> {t}")
user = getpass.getuser().encode().lower()
leak = sorted(n for n, d in entries.items() if user in d.lower())
out = zipfile.ZipFile(NEW, "w", zipfile.ZIP_DEFLATED, compresslevel=6)
for n in sorted(entries):
    out.writestr(zipfile.ZipInfo(n, date_time=STAMP), entries[n], zipfile.ZIP_DEFLATED)
out.close()
old_names = set(x for x in src.namelist() if not x.endswith("/"))
print(len(entries), "entries; new:", sorted(set(entries) - old_names - {e for e in entries if e.startswith("docs/")}),
      "removed:", sorted(old_names - set(entries)))
print("broken relative links:", len(bad))
for b in bad[:30]:
    print("  ", b)
print("entries with the local user name:", len(leak), leak[:10])
print("size", os.path.getsize(NEW), "sha256", hashlib.sha256(open(NEW, "rb").read()).hexdigest())
