#!/usr/bin/env bash
# P151 (depth-usability research, Cary 2026-10-16: "28 min at max context is unusable"): where does a cold 245k prefill go?
# bundle-20261016 zip bins (release_1016, from P150) + the P150 launcher test copy, defaults (q3_0, auto sparse), with
# GGML_CUDA_OP_TIMING=1 + LLAMA_ARG_LOG_VERBOSITY=5 (graphs off inside the timer: absolute ms is inflated, the shares are the data).
# One fresh server, one cold 245k code prompt (quick_tps --depth 245000). The engine prints an op table every 100 graphs
# (~512-token ubatches), so the tables show the op shares at ~50k, ~100k, ... ~245k of depth.
# Reading (declared before the run): FLASH_ATTN_EXT share per table vs depth; MUL_MAT ptq1_0 + GATED_DELTA_NET + rest. This sizes
# the levers: block-sparse prefill / FA kernel (attention part) vs prefill matmul (fixed part). Also the wall ttft vs P143 (1,695 s).
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p151; mkdir -p $R
[ -d release_1016/x ] || { echo "no release_1016/x (P150 extracts it)" > $R/summary.txt; exit 1; }
BIN=$(cd "$(dirname "$(find release_1016/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-1016test.ps1'
bash run_arm.sh $R prof245 "BONSAI_BIN=$BIN;BONSAI_LAYER=0;GGML_CUDA_OP_TIMING=1;LLAMA_ARG_LOG_VERBOSITY=5" "$L" "245000"
O=$(ls -t logs/*-prof245.out.log | head -1); E="${O%.out.log}.err.log"
grep -E "op timing over|ms/graph" "$E" > $R/optables.txt
{ grep -E "^code|mean decode|did not" $R/prof245.txt
  python - "$(cygpath -w $R/optables.txt)" <<'PY'
import re, sys
tabs, cur = [], None
for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
    if 'op timing over' in line:
        cur = {'total': float(re.search(r'([\d.]+) ms per graph', line).group(1)), 'ops': {}}; tabs.append(cur); continue
    m = re.search(r'([\d.]+) ms/graph\s+([\d.]+)%\s+x(\d+)\s+(\S+)\s+(\S+)', line)
    if m and cur is not None:
        op = m.group(4) + (' ' + m.group(5) if m.group(4) == 'MUL_MAT' else '')
        key = 'FA' if op.startswith('FLASH_ATTN') else 'MATMUL' if op.startswith('MUL_MAT') else 'GDN' if op.startswith('GATED_DELTA') else 'other'
        cur['ops'][key] = cur['ops'].get(key, 0) + float(m.group(1))
print('table  ms/graph   FA%   MATMUL%   GDN%   other%')
for i, t in enumerate(tabs):
    o = t['ops']; s = sum(o.values()) or 1
    print(f"{i:>5} {t['total']:9.1f} " + ' '.join(f"{100 * o.get(k, 0) / s:6.1f}" for k in ('FA', 'MATMUL', 'GDN', 'other')))
PY
} > $R/summary.txt
