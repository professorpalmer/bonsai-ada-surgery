"""Bundle 20261018f (save after every answer, eviction guard; layer only): the layout and every bin/ file of bundle-20261018e,
every other file from git archive of the release commit cd2f4f0 (#198)."""
import hashlib, os, shutil, zipfile

REPO = r"C:\Users\pwall\Projects\bonsai-2-27b-serve"
SRC = os.path.join(os.environ["TEMP"], "rel-1018f-src")
OLD = os.path.join(REPO, r"artifacts\release\bonsai-bundle-win-x64-20261018e.zip")
NEW = os.path.join(REPO, r"artifacts\release\bonsai-bundle-win-x64-" + os.environ["BUNDLE_DATE"] + ".zip")
BUILD = os.path.join(REPO, r"tooling\build-release-20261007\bin")
STAGE = os.path.join(os.environ["TEMP"], "bundle-1018f")
assert os.path.abspath(NEW) != os.path.abspath(OLD), "NEW must not be OLD"
ENGINE = {"ggml-base.dll", "ggml-cpu.dll", "ggml-cuda.dll", "ggml.dll", "llama-common.dll", "llama-server-impl.dll",
          "llama-server.exe", "llama.dll", "mtmd.dll", "test-backend-ops.exe"}
EXTRA = []
STAMP = (2026, 10, 19, 6, 0, 0)

shutil.rmtree(STAGE, ignore_errors=True)
os.makedirs(STAGE)
src = zipfile.ZipFile(OLD)
out = zipfile.ZipFile(NEW, "w", zipfile.ZIP_DEFLATED, compresslevel=6)
changed = []


def put(name, data):
    out.writestr(zipfile.ZipInfo(name, date_time=STAMP), data, zipfile.ZIP_DEFLATED)
    dst = os.path.join(STAGE, *name.split("/"))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, "wb").write(data)


for info in src.infolist():
    n = info.filename
    if n.endswith("/"):
        out.writestr(info, b"")
        os.makedirs(os.path.join(STAGE, n), exist_ok=True)
        continue
    parts = n.split("/")
    if parts[0] == "bin":
        data = src.read(n)
    else:
        p = os.path.join(SRC, *parts)
        assert os.path.exists(p), n
        data = open(p, "rb").read()
        # the worktree checkout writes CRLF; keep the line ends the previous bundle had (LF breaks no script, CRLF does)
        if b"\r\n" not in src.read(n):
            data = data.replace(b"\r\n", b"\n")
        elif b"\r\n" not in data:
            data = data.replace(b"\n", b"\r\n")
    if data != src.read(n):
        changed.append(n)
    put(n, data)
for n in EXTRA:
    put(n, open(os.path.join(SRC, *n.split("/")), "rb").read().replace(b"\r\n", b"\n"))
    changed.append(n + " (new)")
out.close()
print(len(src.infolist()) + len(EXTRA), "entries;", len(changed), "changed:")
for c in changed:
    print("  ", c)
print("size", os.path.getsize(NEW), "sha256", hashlib.sha256(open(NEW, "rb").read()).hexdigest())
