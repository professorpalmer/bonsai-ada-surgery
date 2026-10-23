"""Print the chat template length, SHA-256 and the operating_rules check of GGUF files (header only, no gguf-py).
python gguf_template.py FILE..."""
import hashlib
import struct
import sys

SIZES = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}


def rd(f, fmt):
    return struct.unpack("<" + fmt, f.read(struct.calcsize("<" + fmt)))


def rstr(f):
    (n,) = rd(f, "Q")
    return f.read(n)


def skip(f, t):
    if t == 8:
        rstr(f)
    elif t == 9:
        et, n = rd(f, "IQ")
        for _ in range(n):
            skip(f, et)
    else:
        f.seek(SIZES[t], 1)


for path in sys.argv[1:]:
    with open(path, "rb") as f:
        assert f.read(4) == b"GGUF", path
        ver, nt, nkv = rd(f, "IQQ")
        tpl = None
        for _ in range(nkv):
            key = rstr(f).decode()
            (t,) = rd(f, "I")
            if key == "tokenizer.chat_template" and t == 8:
                tpl = rstr(f)
            else:
                skip(f, t)
    name = path.replace("\\", "/").split("/")[-1]
    if tpl is None:
        print(name, "no chat_template")
        continue
    s = tpl.decode("utf-8")
    print(f"{name}: template {len(s)} chars, sha256 {hashlib.sha256(tpl).hexdigest()[:12]}..., "
          f"operating_rules {'YES' if 'operating_rules' in s else 'no'}, "
          f"'only after you have opened the evidence' {'YES' if 'only after you have opened the evidence' in s else 'no'}")
