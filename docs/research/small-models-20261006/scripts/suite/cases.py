"""Coding contract cases for the long-exact-work suite: three self-contained contracts (tar+gzip, ZIP, MIME).

Same shape as the frozen bundle contract (flat solution.py, JSON on stdin, JSON on stdout, tools write_file and
run_python, 12 model responses). Graded by properties of the output on hidden requests, never by byte equality
with a reference. Candidate code runs only in the WASI sandbox; the grader parses the candidate's OUTPUT bytes on
the host with the standard library (size-bounded).
"""
import base64
import binascii
import datetime
import email
import email.policy
import email.utils
import hashlib
import io
import json
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "layer", "wasi-python"))
import sandbox  # noqa: E402

NL = chr(10)
SYSTEM = "Complete the user's task using the provided tools, then answer briefly."
TOOLS = [
    {"type": "function", "function": {"name": "write_file", "description": "Write one UTF-8 candidate source or test file.",
                                      "parameters": {"type": "object", "additionalProperties": False,
                                                     "properties": {"path": {"type": "string"}, "text": {"type": "string"}},
                                                     "required": ["path", "text"]}}},
    {"type": "function", "function": {"name": "run_python", "description": "Run a workspace Python file under read-only confinement.",
                                      "parameters": {"type": "object", "additionalProperties": False,
                                                     "properties": {"path": {"type": "string"}, "stdin": {"type": "string"}},
                                                     "required": ["path", "stdin"]}}},
]
HEAD = ("Implementation task:" + NL + "Create a reusable flat file named solution.py. It must read one UTF-8 JSON object "
        "from stdin and write only the contract result JSON to stdout. You may use write_file and run_python while "
        "developing it." + NL + NL + "Contract text:" + NL)
LIMITS = """

Concrete runtime limits:
- At most 12 model responses, including the final response.
- Workspace paths are flat relative filenames; at most 16 files of 128 KiB each.
- Python 3.12, standard library only, no child processes, no network, no files outside the workspace.
- Each Python execution has an 8 second wall limit and a 128 MiB memory limit.

Disclosed public example request:
"""
TAIL = (NL + NL + "You have exactly 12 MODEL RESPONSES maximum, including your final response. Use the provided tools "
        "as needed.")


def b64(b):
    return base64.b64encode(b).decode("ascii")


ZIP_CONTRACT = """# Canonical ZIP archive

Read one JSON request from stdin. Build a ZIP archive entirely in memory and emit one JSON result. Never read or
extract host files. Member paths are input data, not host directories.

## Request

```json
{"members":[{"path":"docs/note.txt","content_b64":"aGkK","mode":420}],"timestamp":[2024,5,17,9,30,12],"comment":"release 7"}
```

The request has exactly `members`, `timestamp` and `comment`. `members` has 1 to 64 entries; each has exactly
`path`, `content_b64` and `mode`. Paths are unique relative POSIX paths: they must not start with `/`, contain a
backslash, or have empty, `.` or `..` components. Content is strict RFC 4648 base64, at most 64 KiB per member.
Mode is an integer from 0 through 511. `timestamp` is six integers `[year, month, day, hour, minute, second]`
forming a valid date and time with year 1980 through 2107 and an even second. `comment` is a string of at most 200
characters.

The archive holds one entry per member, regular files only, ordered by path in Unicode code-point order. No
directory entries. Every entry:

- is stored with the deflate method (method 8), also when the content is empty;
- has the requested timestamp as its modification time;
- is marked as created on Unix (create system 3), with external attributes whose high 16 bits are the Unix mode
  of a regular file with the requested permission bits (0o100000 | mode);
- has its path encoded as UTF-8, and exactly the requested bytes as content.

The archive comment is the UTF-8 encoding of `comment`. Two runs for the same request must emit byte-identical
archives.

## Result

```json
{"format":"zip","archive_b64":"...","sha256":"64 lowercase hex characters"}
```

`sha256` is the digest of the decoded archive bytes. The grader opens the archive and checks the entry list and
order, each entry's method, timestamp, create system, external attributes and content, the archive comment, CRC
integrity, the digest, and repeat-byte equality.

Invalid request JSON or schema emits exactly `{"error":"invalid_request"}`."""

MIME_CONTRACT = """# Canonical MIME email message

Read one JSON request from stdin. Build an RFC 5322 email message with MIME attachments entirely in memory and emit
one JSON result. Never read host files or send anything.

## Request

```json
{"from":"Build Bot <bot@example.org>","to":["ana@example.org","Lee <lee@example.net>"],"subject":"Report","date":1715938212,"message_id":"<r1@example.org>","body":"See attached.","attachments":[{"filename":"a.bin","content_type":"application/octet-stream","content_b64":"AAEC"}]}
```

The request has exactly `from`, `to`, `subject`, `date`, `message_id`, `body` and `attachments`. `from` is one
ASCII mailbox, optionally with a display name. `to` has 1 to 8 ASCII mailboxes. `subject` is a non-empty
single-line string that may contain any Unicode text. `date` is an integer number of seconds since the Unix epoch
(UTC). `message_id` is an ASCII string of the form `<local@domain>`. `body` is text with `\\n` line endings that may
contain any Unicode text. `attachments` has 0 to 8 entries; each has exactly `filename` (non-empty, may contain
non-ASCII characters, no `/` or backslash), `content_type` (`type/subtype`, ASCII) and `content_b64` (strict
RFC 4648 base64, at most 64 KiB decoded).

The message, as bytes:

- is 7-bit clean: every byte is ASCII, lines end with CRLF or LF, and no line is longer than 998 characters;
- has the headers `From`, `To` (all recipients in request order), `Subject`, `Date`, `Message-ID` and
  `MIME-Version: 1.0`. A non-ASCII subject is encoded as RFC 2047 encoded words. `Date` denotes exactly the
  requested instant;
- with no attachments, is a single `text/plain` part with charset `utf-8`;
- with attachments, is `multipart/mixed`: first a `text/plain` part with charset `utf-8`, then one part per
  attachment in request order, each with the requested content type, `Content-Disposition: attachment` carrying
  the filename (RFC 2231 encoding when it is not ASCII) and base64 transfer encoding;
- decodes to exactly the requested body text (one trailing newline more or less is accepted) and exactly the
  requested attachment bytes.

Two runs for the same request must emit byte-identical messages, so the multipart boundary must not be random.

## Result

```json
{"format":"eml","message_b64":"...","sha256":"64 lowercase hex characters"}
```

`sha256` is the digest of the decoded message bytes. The grader parses the message with a standards-compliant
parser and checks every property above, the digest, and repeat-byte equality.

Invalid request JSON or schema emits exactly `{"error":"invalid_request"}`."""

ZIP_PUBLIC = {"members": [{"path": "example/item.txt", "content_b64": "ZXhhbXBsZQo=", "mode": 420}],
              "timestamp": [2024, 1, 2, 3, 4, 6], "comment": "example"}
MIME_PUBLIC = {"from": "Example <ex@example.org>", "to": ["you@example.org"], "subject": "Example", "date": 1700000000,
               "message_id": "<ex1@example.org>", "body": "Hello." + NL,
               "attachments": [{"filename": "item.txt", "content_type": "text/plain", "content_b64": "ZXhhbXBsZQo="}]}

# hidden requests: (request, expect_error)
ZIP_HIDDEN = {
    "xfer-zip-01": [
        ({"members": [{"path": "src/main.py", "content_b64": b64(b"print('hi')" + b"\n" * 40), "mode": 0o755},
                      {"path": "README.md", "content_b64": b64("# Título — données\n".encode("utf-8") * 30), "mode": 0o644},
                      {"path": "data/empty.bin", "content_b64": "", "mode": 0o600},
                      {"path": "data/blob.bin", "content_b64": b64(bytes(range(256)) * 20), "mode": 0o400}],
          "timestamp": [2031, 12, 30, 23, 59, 58], "comment": "build 41 ✓"}, False),
        ({"members": [{"path": "ü/ñ.txt", "content_b64": b64(b"x"), "mode": 0}, {"path": "Z.txt", "content_b64": b64(b"z" * 5000), "mode": 511},
                      {"path": "a/b/c/d.txt", "content_b64": b64(b"deep"), "mode": 0o640}],
          "timestamp": [1980, 1, 1, 0, 0, 0], "comment": ""}, False),
        ({"members": [{"path": "a.txt", "content_b64": "YQ==", "mode": 420}, {"path": "../b.txt", "content_b64": "Yg==", "mode": 420}],
          "timestamp": [2024, 1, 1, 0, 0, 0], "comment": ""}, True),
        ({"members": [{"path": "a.txt", "content_b64": "YQ==", "mode": 512}], "timestamp": [2024, 1, 1, 0, 0, 0], "comment": ""}, True),
    ],
}
MIME_HIDDEN = {
    "xfer-mime-01": [
        ({"from": "Release Bot <release@example.org>", "to": ["ana@example.org", "Lee Chen <lee@example.net>", "ops@example.com"],
          "subject": "Informe semanal — número 12 ✓ (résumé)", "date": 1893456789, "message_id": "<w12.7f3a@example.org>",
          "body": "Hola equipo,\n\nAdjunto el informe. Precio: 12 €.\n— El bot\n",
          "attachments": [{"filename": "informe-año.pdf", "content_type": "application/pdf", "content_b64": b64(b"%PDF-1.4" + bytes(range(256)) * 9)},
                          {"filename": "data.csv", "content_type": "text/csv", "content_b64": b64(b"a,b\r\n1,2\r\n")},
                          {"filename": "empty.bin", "content_type": "application/octet-stream", "content_b64": ""}]}, False),
        ({"from": "solo@example.org", "to": ["you@example.org"], "subject": "Plain note", "date": 86400 * 366,
          "message_id": "<n1@example.org>", "body": "Line one\nLínea dos with a very long tail " + "word " * 300 + "\nend",
          "attachments": []}, False),
        ({"from": "solo@example.org", "to": [], "subject": "x", "date": 1, "message_id": "<n2@example.org>", "body": "b", "attachments": []}, True),
        ({"from": "solo@example.org", "to": ["you@example.org"], "subject": "x", "date": 1, "message_id": "<n3@example.org>", "body": "b",
          "attachments": [{"filename": "a.bin", "content_type": "application/octet-stream", "content_b64": "@@@"}]}, True),
    ],
}


TAR_CONTRACT = """# Canonical compressed bundle

Read one JSON request from stdin. Build a gzip-compressed POSIX ustar archive entirely in memory and emit one
JSON result. Never read or extract host files. Member paths are input data, not host directories.

## Request

```json
{"members":[{"path":"docs/note.txt","content_b64":"aGkK","mode":420}]}
```

The request has exactly `members`, with 1 to 64 entries. Each member has exactly `path`, `content_b64` and `mode`.
Paths are unique relative POSIX paths: they must not start with `/`, contain a backslash, or have empty, `.` or
`..` components; they contain no control characters, and their UTF-8 encoding is at most 100 bytes. Content is
strict RFC 4648 base64, at most 64 KiB per member and 128 KiB in total. Mode is an integer from 0 through 511.

Archive members are regular files ordered by path in Unicode code-point order. Each header carries the requested
path, size and mode, with `mtime=0`, `uid=0`, `gid=0`, empty `uname` and `gname`, regular-file type, ustar magic
`ustar\\0` and version `00`. No directory, link, PAX or GNU entries. After the last member's padded content the
stream has at least two 512-byte zero blocks and only zero bytes after that. The outer stream is valid gzip with
deflate, `mtime=0`, no filename and no extra fields; any compression level. Two runs for the same request must
emit byte-identical gzip streams.

## Result

```json
{"format":"tar+gzip","bundle_b64":"...","sha256":"64 lowercase hex characters"}
```

`sha256` is the digest of the decoded compressed bytes. The grader checks gzip framing and header flags, the
digest, every member header field, content, order, the end blocks, and repeat-byte equality.

Invalid request JSON or schema emits exactly `{"error":"invalid_request"}`."""

TAR_PUBLIC = {"members": [{"path": "example/item.txt", "content_b64": "ZXhhbXBsZQo=", "mode": 420}]}
TAR_HIDDEN = {
    "suite-tar-01": [
        ({"members": [{"path": "src/main.py", "content_b64": b64(b"print('hi')" + b"\n" * 40), "mode": 0o755},
                      {"path": "README.md", "content_b64": b64("# Título — données\n".encode("utf-8") * 30), "mode": 0o644},
                      {"path": "data/empty.bin", "content_b64": "", "mode": 0o600},
                      {"path": "data/blob.bin", "content_b64": b64(bytes(range(256)) * 20), "mode": 0o400}]}, False),
        ({"members": [{"path": "ü/ñ.txt", "content_b64": b64(b"x"), "mode": 0}, {"path": "Z.txt", "content_b64": b64(b"z" * 5000), "mode": 511},
                      {"path": "a/b/c/d.txt", "content_b64": b64(b"deep"), "mode": 0o640},
                      {"path": "exactly-512.bin", "content_b64": b64(b"q" * 512), "mode": 0o644}]}, False),
        ({"members": [{"path": "a.txt", "content_b64": "YQ==", "mode": 420}, {"path": "../b.txt", "content_b64": "Yg==", "mode": 420}]}, True),
        ({"members": [{"path": "a.txt", "content_b64": "YQ", "mode": 420}]}, True),
    ],
}


def check_tar(req, text):
    import gzip
    import tarfile
    raw, why = _result(text, "bundle_b64")
    if why:
        return why
    if len(raw) < 18 or raw[:2] != b"\x1f\x8b" or raw[2] != 8:
        return "invalid_gzip"
    if raw[3] & 0b11110 or raw[4:8] != b"\x00\x00\x00\x00":   # FEXTRA/FNAME/FCOMMENT/FHCRC must be off; mtime 0
        return "gzip_header_fields"
    try:
        tar = gzip.decompress(raw)
    except Exception:
        return "invalid_gzip"
    if len(tar) > (4 << 20):
        return "oversize"
    try:
        tf = tarfile.open(fileobj=io.BytesIO(tar), mode="r:")
        members = tf.getmembers()
    except Exception:
        return "invalid_tar"
    want = sorted(req["members"], key=lambda m: m["path"])
    if [m.name for m in members] != [m["path"] for m in want]:
        return "member_set_or_order"
    for m, w in zip(members, want):
        if not m.isreg() or m.mtime != 0 or m.uid != 0 or m.gid != 0 or m.uname != "" or m.gname != "" or m.mode != w["mode"]:
            return "member_header"
        if tar[m.offset + 257:m.offset + 265] != b"ustar\x0000":
            return "not_ustar"
        if tf.extractfile(m).read() != base64.b64decode(w["content_b64"]):
            return "content"
    last = members[-1]
    end = last.offset_data + (last.size + 511) // 512 * 512
    if len(tar) < end + 1024 or any(tar[end:]):
        return "end_blocks"
    return None


CASES = {"suite-tar-01": ("tar", TAR_CONTRACT, TAR_PUBLIC), "xfer-zip-01": ("zip", ZIP_CONTRACT, ZIP_PUBLIC), "xfer-mime-01": ("mime", MIME_CONTRACT, MIME_PUBLIC)}
HIDDEN = dict(TAR_HIDDEN, **ZIP_HIDDEN, **MIME_HIDDEN)


def prompts(case_id):
    _, contract, public = CASES[case_id]
    user = HEAD + contract + LIMITS + json.dumps(public, ensure_ascii=False) + TAIL
    return SYSTEM, user, TOOLS


def _result(text, key):
    """Parse the candidate's stdout into (archive bytes, reason)."""
    try:
        o = json.loads(text)
    except ValueError:
        return None, "unrecoverable_json"
    if not isinstance(o, dict) or set(o) != {"format", key, "sha256"}:
        return None, "result_schema"
    if not isinstance(o[key], str) or len(o[key]) > (2 << 20):
        return None, "invalid_or_oversize_base64"
    try:
        raw = base64.b64decode(o[key], validate=True)
    except (binascii.Error, ValueError):
        return None, "invalid_or_oversize_base64"
    if hashlib.sha256(raw).hexdigest() != o["sha256"]:
        return None, "digest_mismatch"
    return raw, None


def check_zip(req, text):
    raw, why = _result(text, "archive_b64")
    if why:
        return why
    try:
        zf = zipfile.ZipFile(io.BytesIO(raw))
        infos = zf.infolist()
    except Exception:
        return "invalid_zip"
    want = sorted(req["members"], key=lambda m: m["path"])
    if [i.filename for i in infos] != [m["path"] for m in want]:
        return "member_set_or_order"
    if sum(i.file_size for i in infos) > (4 << 20):
        return "oversize"
    for i, m in zip(infos, want):
        if i.compress_type != zipfile.ZIP_DEFLATED:
            return "method_not_deflate"
        if tuple(i.date_time) != tuple(req["timestamp"]):
            return "timestamp"
        if i.create_system != 3:
            return "create_system"
        if (i.external_attr >> 16) != (0o100000 | m["mode"]):
            return "external_attr_mode"
        try:
            if zf.read(i) != base64.b64decode(m["content_b64"]):
                return "content"
        except Exception:
            return "invalid_zip"
    if zf.comment != req["comment"].encode("utf-8"):
        return "comment"
    return None


def check_mime(req, text):
    raw, why = _result(text, "message_b64")
    if why:
        return why
    if any(b > 127 for b in raw):
        return "not_7bit"
    if any(len(line.rstrip(b"\r")) > 998 for line in raw.split(b"\n")):
        return "line_too_long"
    try:
        msg = email.message_from_bytes(raw, policy=email.policy.default)
        if msg.defects:
            return "parse_defects"
        addr = lambda vals: [a for _, a in email.utils.getaddresses(vals)]
        if addr([str(msg["From"])]) != addr([req["from"]]) or addr(msg.get_all("To", [])) != addr(req["to"]):
            return "addresses"
        if str(msg["Subject"]) != req["subject"]:
            return "subject"
        if int(email.utils.parsedate_to_datetime(str(msg["Date"])).timestamp()) != req["date"]:
            return "date"
        if str(msg["Message-ID"]).strip() != req["message_id"]:
            return "message_id"
        if str(msg["MIME-Version"]).strip() != "1.0":
            return "mime_version"
        atts = req["attachments"]
        if atts:
            if msg.get_content_type() != "multipart/mixed":
                return "not_multipart_mixed"
            parts = list(msg.iter_parts())
            if len(parts) != 1 + len(atts):
                return "part_count"
            textpart, rest = parts[0], parts[1:]
        else:
            textpart, rest = msg, []
        if textpart.get_content_type() != "text/plain" or (textpart.get_content_charset() or "").lower() != "utf-8":
            return "text_part_type"
        if textpart.get_content().replace("\r\n", "\n").rstrip("\n") != req["body"].rstrip("\n"):
            return "body_text"
        for p, a in zip(rest, atts):
            if p.get_content_type() != a["content_type"].lower():
                return "attachment_type"
            if p.get_content_disposition() != "attachment" or p.get_filename() != a["filename"]:
                return "attachment_disposition_or_filename"
            if (p.get("Content-Transfer-Encoding") or "").lower() != "base64":
                return "attachment_not_base64"
            if p.get_payload(decode=True) != base64.b64decode(a["content_b64"]):
                return "attachment_content"
    except Exception as e:
        return "invalid_message:" + type(e).__name__
    return None


CHECK = {"tar": check_tar, "zip": check_zip, "mime": check_mime}


def grade(case_id, files, normal_completion=True, timeout=8.0, mem_mb=128):
    """Same record shape as contract_grade.grade. functional_result_correct: every hidden request passes."""
    if "solution.py" not in files:
        return {"task_success": False, "functional_result_correct": None, "reasons": ["candidate_unavailable"]}
    kind = CASES[case_id][0]
    reasons, execs = [], []
    for k, (req, expect_error) in enumerate(HIDDEN[case_id]):
        stdin = json.dumps(req, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        runs = [sandbox.run(dict(files), ["/work/solution.py"], stdin=stdin, timeout=timeout, mem_mb=mem_mb) for _ in range(2)]
        execs.append([{"exit": r["exit_code"], "timed_out": r["timed_out"], "stderr_tail": r["stderr"][-200:].decode("utf-8", "replace")} for r in runs])
        out = [r["stdout"].decode("utf-8", "replace") for r in runs]
        if expect_error:
            try:
                ok = json.loads(out[0]) == {"error": "invalid_request"}
            except ValueError:
                ok = False
            why = None if ok else "invalid_request_not_rejected"
        else:
            why = CHECK[kind](req, out[0])
            if why is None and out[0] != out[1]:
                why = "not_reproducible"
        if why:
            reasons.append(f"hidden{k + 1}:{why}")
    valid_ok = not any(r.startswith(("hidden1:", "hidden2:")) for r in reasons)
    return {"functional_result_correct": not reasons, "valid_requests_correct": valid_ok, "protocol_valid": not reasons,
            "normal_completion": normal_completion, "task_success": (not reasons) and normal_completion,
            "reasons": reasons, "exec": execs}


REF_TAR = '''import base64, gzip, hashlib, io, json, sys, tarfile
def bad():
    print('{"error":"invalid_request"}'); sys.exit(0)
try:
    r = json.loads(sys.stdin.read())
    assert isinstance(r, dict) and set(r) == {"members"} and isinstance(r["members"], list) and 1 <= len(r["members"]) <= 64
    seen, items, total = set(), [], 0
    for m in r["members"]:
        assert isinstance(m, dict) and set(m) == {"path", "content_b64", "mode"}
        p = m["path"]
        assert isinstance(p, str) and p and not p.startswith("/") and chr(92) not in p and all(x not in ("", ".", "..") for x in p.split("/"))
        assert all(ord(c) >= 32 and ord(c) != 127 for c in p) and len(p.encode("utf-8")) <= 100 and p not in seen
        seen.add(p)
        assert type(m["mode"]) is int and 0 <= m["mode"] <= 511 and isinstance(m["content_b64"], str)
        d = base64.b64decode(m["content_b64"], validate=True)
        assert len(d) <= 65536
        total += len(d)
        items.append((p, d, m["mode"]))
    assert total <= 131072
except Exception:
    bad()
tbuf = io.BytesIO()
with tarfile.open(fileobj=tbuf, mode="w", format=tarfile.USTAR_FORMAT) as tf:
    for p, d, mode in sorted(items):
        ti = tarfile.TarInfo(p); ti.size = len(d); ti.mode = mode; ti.mtime = 0; ti.uid = 0; ti.gid = 0; ti.uname = ""; ti.gname = ""
        tf.addfile(ti, io.BytesIO(d))
raw = gzip.compress(tbuf.getvalue(), compresslevel=9, mtime=0)
print(json.dumps({"format": "tar+gzip", "bundle_b64": base64.b64encode(raw).decode(), "sha256": hashlib.sha256(raw).hexdigest()}))
'''

REF_ZIP = '''import base64, hashlib, io, json, sys, zipfile, datetime
def bad():
    print('{"error":"invalid_request"}'); sys.exit(0)
try:
    r = json.loads(sys.stdin.read())
    assert isinstance(r, dict) and set(r) == {"members", "timestamp", "comment"}
    ms, ts, c = r["members"], r["timestamp"], r["comment"]
    assert isinstance(ms, list) and 1 <= len(ms) <= 64 and isinstance(c, str) and len(c) <= 200
    assert isinstance(ts, list) and len(ts) == 6 and all(type(x) is int for x in ts) and 1980 <= ts[0] <= 2107 and ts[5] % 2 == 0
    datetime.datetime(*ts)
    seen, items = set(), []
    for m in ms:
        assert isinstance(m, dict) and set(m) == {"path", "content_b64", "mode"}
        p = m["path"]
        assert isinstance(p, str) and p and not p.startswith("/") and chr(92) not in p and all(x not in ("", ".", "..") for x in p.split("/"))
        assert p not in seen; seen.add(p)
        assert type(m["mode"]) is int and 0 <= m["mode"] <= 511 and isinstance(m["content_b64"], str)
        d = base64.b64decode(m["content_b64"], validate=True)
        assert len(d) <= 65536
        items.append((p, d, m["mode"]))
except Exception:
    bad()
buf = io.BytesIO()
with zipfile.ZipFile(buf, "w") as zf:
    for p, d, mode in sorted(items):
        zi = zipfile.ZipInfo(p, date_time=tuple(ts))
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.create_system = 3
        zi.external_attr = (0o100000 | mode) << 16
        zf.writestr(zi, d)
    zf.comment = c.encode("utf-8")
raw = buf.getvalue()
print(json.dumps({"format": "zip", "archive_b64": base64.b64encode(raw).decode(), "sha256": hashlib.sha256(raw).hexdigest()}))
'''

REF_MIME = '''import base64, hashlib, json, sys, datetime
from email.message import EmailMessage
from email.utils import format_datetime
def bad():
    print('{"error":"invalid_request"}'); sys.exit(0)
try:
    r = json.loads(sys.stdin.read())
    assert isinstance(r, dict) and set(r) == {"from", "to", "subject", "date", "message_id", "body", "attachments"}
    assert isinstance(r["to"], list) and 1 <= len(r["to"]) <= 8 and all(isinstance(x, str) for x in r["to"])
    assert isinstance(r["subject"], str) and r["subject"] and type(r["date"]) is int and isinstance(r["body"], str)
    assert isinstance(r["attachments"], list) and len(r["attachments"]) <= 8
    atts = []
    for a in r["attachments"]:
        assert isinstance(a, dict) and set(a) == {"filename", "content_type", "content_b64"}
        mt, st = a["content_type"].split("/")
        atts.append((a["filename"], mt, st, base64.b64decode(a["content_b64"], validate=True)))
except Exception:
    bad()
m = EmailMessage()
m["From"] = r["from"]; m["To"] = ", ".join(r["to"]); m["Subject"] = r["subject"]
m["Date"] = format_datetime(datetime.datetime.fromtimestamp(r["date"], datetime.timezone.utc))
m["Message-ID"] = r["message_id"]
m.set_content(r["body"], cte="base64")
for fn, mt, st, data in atts:
    m.add_attachment(data, maintype=mt, subtype=st, filename=fn)
if atts:
    m.set_boundary("=_fixed_boundary_0123456789")
raw = m.as_bytes()
print(json.dumps({"format": "eml", "message_b64": base64.b64encode(raw).decode(), "sha256": hashlib.sha256(raw).hexdigest()}))
'''

if __name__ == "__main__":
    for cid, ref in (("suite-tar-01", REF_TAR), ("xfer-zip-01", REF_ZIP), ("xfer-mime-01", REF_MIME)):
        g = grade(cid, {"solution.py": ref.encode("utf-8")})
        print(cid, "reference:", g["functional_result_correct"], g["reasons"], [e[0]["exit"] for e in g["exec"]])
        s, u, t = prompts(cid)
        print("   prompt chars", len(u))
    # negative controls: plausible wrong solutions must fail
    g = grade("suite-tar-01", {"solution.py": REF_TAR.replace("mtime=0)", "mtime=1)").encode()})
    print("tar gzip mtime set:", g["functional_result_correct"], g["reasons"])
    g = grade("suite-tar-01", {"solution.py": REF_TAR.replace("ti.mtime = 0; ", "ti.mtime = 5; ").encode()})
    print("tar member mtime set:", g["functional_result_correct"], g["reasons"])
    g = grade("suite-tar-01", {"solution.py": REF_TAR.replace("format=tarfile.USTAR_FORMAT", "format=tarfile.GNU_FORMAT").encode()})
    print("tar GNU format:", g["functional_result_correct"], g["reasons"])
    g = grade("xfer-zip-01", {"solution.py": REF_ZIP.replace("zi.create_system = 3\n", "").encode()})
    print("zip without create_system:", g["functional_result_correct"], g["reasons"])
    g = grade("xfer-zip-01", {"solution.py": REF_ZIP.replace("sorted(items)", "items").encode()})
    print("zip unsorted:", g["functional_result_correct"], g["reasons"])
    g = grade("xfer-mime-01", {"solution.py": REF_MIME.replace('    m.set_boundary("=_fixed_boundary_0123456789")\n', "    pass\n").encode()})
    print("mime random boundary:", g["functional_result_correct"], g["reasons"])
    g = grade("xfer-mime-01", {"solution.py": REF_MIME.replace("filename=fn", "filename='x.bin'").encode()})
    print("mime wrong filename:", g["functional_result_correct"], g["reasons"])
