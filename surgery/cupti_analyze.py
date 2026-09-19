"""Summarise a cupti_trace.csv: per (kernel, grid) timing, effective GB/s for PTQ1 GEMVs, gap stats.

usage: python cupti_analyze.py artifacts/cupti_tg64.csv [n_graphs]
"""
from __future__ import annotations

import csv
import re
import statistics
import sys
from collections import defaultdict

PTQ1_BLOCK_BYTES = 28  # 128 weights
PTQ1_QK = 128

# gridX -> (K, N) for the PTQ1 GEMVs in Bonsai 2 27B decode, by MMVQ geometry:
#   small_k (K <= 128 blocks): rows_per_block = 4 -> grid = N/4
#   otherwise               : rows_per_block = 1 -> grid = N
SHAPES = {
    2560: (5120, 10240, "qkv"),
    1536: (5120, 6144, "z"),
    1280: (6144, 5120, "ssm_out/attn_out"),
    4352: (5120, 17408, "gate|up"),
    5120: (17408, 5120, "down"),
    3072: (5120, 12288, "wq"),
    256: (5120, 1024, "wk/wv"),
    62080: (5120, 248320, "lm_head"),
}


def short(name: str) -> str:
    m = re.match(r"\d+(\w+?)I", name)
    base = m.group(1) if m else name[:24]
    if base.startswith("mul_mat_vec_q"):
        # template flags after the type: ncols, fusion, ids, small_k, halve
        flags = re.findall(r"Lb([01])E", name)
        return "mmvq<" + ",".join(flags) + ">"
    return base


def main() -> None:
    path = sys.argv[1]
    rows = list(csv.DictReader(open(path, encoding="utf-8")))
    n_graphs = int(sys.argv[2]) if len(sys.argv) > 2 else None
    by = defaultdict(list)
    gaps = defaultdict(list)
    for r in rows:
        key = (short(r["name"]), int(r["gridX"]), int(r["blockX"]))
        by[key].append(float(r["dur_us"]))
        gaps[key].append(float(r["gap_us"]))
    total = sum(sum(v) for v in by.values())
    if n_graphs is None:
        # infer: lm_head kernel runs once per token
        n_graphs = max(1, sum(len(v) for k, v in by.items() if k[1] == 62080))
    print(f"kernels={len(rows)} graphs~{n_graphs} sum={total/1000:.1f} ms  per-graph={total/1000/n_graphs:.2f} ms")
    print(f"{'kernel':<18}{'grid':>7}{'blk':>5}{'n/tok':>6}{'mean':>9}{'p10':>8}{'p50':>8}{'p90':>8}{'max':>8}{'gap':>7}  {'GB/s':>6}  shape")
    items = sorted(by.items(), key=lambda kv: -sum(kv[1]))
    for (name, grid, blk), d in items[:28]:
        d_sorted = sorted(d)
        n = len(d)
        p = lambda q: d_sorted[min(n - 1, int(q * n))]
        mean = statistics.fmean(d)
        g = statistics.fmean(gaps[(name, grid, blk)])
        shape = SHAPES.get(grid)
        gbs = ""
        label = ""
        if name.startswith("mmvq") and shape:
            K, N, label = shape
            byts = K // PTQ1_QK * PTQ1_BLOCK_BYTES * N
            if "gate|up" in label and name == "mmvq<1,1,1,0>":
                byts *= 2
                label = "gate+up fused"
            gbs = f"{byts / (mean * 1e-6) / 1e9:6.0f}"
        print(f"{name:<18}{grid:>7}{blk:>5}{n / n_graphs:>6.0f}{mean:>9.2f}{p(0.1):>8.2f}{p(0.5):>8.2f}{p(0.9):>8.2f}{d_sorted[-1]:>8.1f}{g:>7.2f}  {gbs:>6}  {label}")
    allgaps = [float(r["gap_us"]) for r in rows]
    pos = [g for g in allgaps if g > 0]
    print(f"\ngaps: n={len(allgaps)} sum={sum(pos)/1000:.1f} ms  per-graph={sum(pos)/1000/n_graphs:.2f} ms  "
          f"median={statistics.median(pos):.2f} us  >10us: {sum(1 for g in pos if g > 10)}  >100us: {sum(1 for g in pos if g > 100)}")


if __name__ == "__main__":
    main()
