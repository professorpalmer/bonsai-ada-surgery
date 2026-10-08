"""Requantize the MTP draft block (blk.64.*) of a grafted Bonsai 2 GGUF from Q8_0 to Q4_0, copying every other tensor
byte for byte (the file is rewritten by hand so PrismML's ternary tensor types never pass through gguf-py).

    python build/requant_mtp.py models/Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf models/Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations-q4head.gguf

Why: the draft block lives in VRAM. On an RTX 2060 SUPER the Q4_0 head saved 212 MB in the file and 214 MiB of server
VRAM (~12k q4_0 K/V positions); draft acceptance went 0.875 -> 0.848 and decode -1% at 4k. Only the head changes:
stripping blk.64 from the output gives the official PTQ1_0 file's sha256. Drafting itself is not bit-identical to not
drafting on any card (docs/Q8_FULL_CONTEXT.md); a different head changes which drafts are accepted, not the target model.
Norm and small tensors in the block are left as they are. Output alignment follows the file's general.alignment.
Ported from professorpalmer/mirai-s-ada tooling/requant_mtp.py.
"""
import argparse, os, struct, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "vendor", "prism-llama", "gguf-py"))
from gguf import GGMLQuantizationType as T  # noqa: E402
from gguf import quants  # noqa: E402

Q8_0 = 8
TARGETS = {"q4_0": T.Q4_0, "q5_0": T.Q5_0, "q8_0": T.Q8_0}
TYPE_SIZE = {T.Q4_0: (32, 18), T.Q5_0: (32, 22), T.Q8_0: (32, 34)}  # block size, bytes per block

def read_str(f):
    (n,) = struct.unpack("<Q", f.read(8)); return f.read(n)

def raw_value(f, t):
    """Return the raw bytes of one KV value of GGUF type t (so the KV section can be copied verbatim)."""
    sizes = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}
    if t == 8:
        s = read_str(f); return struct.pack("<Q", len(s)) + s
    if t == 9:
        et = f.read(4); (n,) = struct.unpack("<Q", f.read(8)); out = et + struct.pack("<Q", n)
        (et_i,) = struct.unpack("<I", et)
        for _ in range(n): out += raw_value(f, et_i)
        return out
    return f.read(sizes[t])

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst"); ap.add_argument("--type", default="q4_0", choices=sorted(TARGETS))
    ap.add_argument("--prefix", default="blk.64.", help="tensor name prefix to requantize (default: the MTP block)")
    a = ap.parse_args(); target = TARGETS[a.type]; blk, bpb = TYPE_SIZE[target]
    with open(a.src, "rb") as f:
        magic, version, n_tensors, n_kv = struct.unpack("<IIQQ", f.read(24)); assert magic == 0x46554747 and version == 3
        kv_raw = b""; alignment = 32
        for _ in range(n_kv):
            k = read_str(f); (t,) = struct.unpack("<I", f.read(4)); v = raw_value(f, t)
            if k == b"general.alignment": alignment = struct.unpack("<I", v)[0]
            kv_raw += struct.pack("<Q", len(k)) + k + struct.pack("<I", t) + v
        infos = []
        for _ in range(n_tensors):
            name = read_str(f); (nd,) = struct.unpack("<I", f.read(4)); dims = struct.unpack("<" + "Q" * nd, f.read(8 * nd))
            t, off = struct.unpack("<IQ", f.read(12)); infos.append([name, dims, t, off])
        data_start = (f.tell() + alignment - 1) // alignment * alignment
        # byte size of each tensor = distance to the next offset (last one: to EOF)
        f.seek(0, 2); end = f.tell() - data_start
        offs = sorted([(i[3], k) for k, i in enumerate(infos)]) + [(end, -1)]
        sizes = {}
        for (o, k), (o2, _) in zip(offs, offs[1:]): sizes[k] = o2 - o
        # plan the new layout
        new = []; cur = 0; changed = 0; saved = 0
        for k, (name, dims, t, off) in enumerate(infos):
            size = sizes[k]; nt = t
            if name.startswith(a.prefix.encode()) and t == Q8_0 and len(dims) >= 1 and dims[0] % blk == 0:
                nt = int(target); n = 1
                for d in dims: n *= d
                size_new = n // blk * bpb; saved += size - size_new; size = size_new; changed += 1
            new.append((name, dims, t, nt, off, sizes[k], cur, size)); cur = (cur + size + alignment - 1) // alignment * alignment
        print(f"{n_tensors} tensors, {changed} in {a.prefix}* requantized {GGMLQuantizationName(Q8_0)} -> {a.type}, saving {saved/1e6:.0f} MB", flush=True)
        with open(a.dst, "wb") as g:
            g.write(struct.pack("<IIQQ", magic, version, n_tensors, n_kv)); g.write(kv_raw)
            for name, dims, t, nt, off, size, noff, nsize in new:
                g.write(struct.pack("<Q", len(name)) + name + struct.pack("<I", len(dims)) + struct.pack("<" + "Q" * len(dims), *dims) + struct.pack("<IQ", nt, noff))
            g.write(b"\0" * (((g.tell() + alignment - 1) // alignment * alignment) - g.tell()))
            base = g.tell()
            for name, dims, t, nt, off, size, noff, nsize in new:
                f.seek(data_start + off); raw = f.read(size)
                if nt != t:
                    rows = int(np.prod(dims[1:])) if len(dims) > 1 else 1
                    q8 = np.frombuffer(raw, dtype=np.uint8).reshape(rows, -1)
                    f32 = quants.dequantize(q8, T.Q8_0).reshape(rows, dims[0])
                    raw = quants.quantize(f32, target).tobytes(); assert len(raw) == nsize, (name, len(raw), nsize)
                g.seek(base + noff); g.write(raw)
            g.seek(0, 2); print(f"wrote {a.dst}: {g.tell()/1e9:.3f} GB", flush=True)

def GGMLQuantizationName(t): return {8: "Q8_0"}.get(t, str(t))

if __name__ == "__main__":
    main()
