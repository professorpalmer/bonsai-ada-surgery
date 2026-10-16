#!/usr/bin/env bash
# P146 (#105: the 4070's "P144" ask, the last check before #125 / #126 merge for "sparse is automatic"): D26h on the 2060.
# Engine product-0059 ab9481005 (= sparse-d26h 79332dbbb tree; 75-real build in tooling/bin-d26h). Launcher launcher-late-reserve
# 7f16808 (q3_0 FRAC 0.25 in the table; the budget is in the calib key) as a test copy with only the BONSAI_BIN line added.
# Arms (one server each, extend sweep 64k / 80k / 96k / 112k / 128k / 160k / 245k, q3_0 launcher default):
#   auto_r1 (launcher defaults, a FRESH calib file), off_r1 (BONSAI_SPARSE=0), auto_r2 (defaults, uses the r1 calib file), off_r2.
#   det_a / det_b: two fresh servers, launcher defaults, the same calib file, one 128k code prompt each; answer bytes saved.
# Gates (declared here, before the run):
#   G1 round 2 (calib used): at every depth <= 128k, auto mean decode >= off x 0.98.
#   G2 160k / 245k: auto vs off reported per round; expected near P143's 1.34x / 1.44x (at 1/8), lower is allowed at 1/4 since auto
#      keeps dense when sparse is not > 3 % faster; auto below off x 0.98 at 160k or 245k in round 2 = FAIL.
#   G3 det_a and det_b answers byte-identical (sha256).
#   G4 0 one-token answers in all arms; trace min free >= 60 MiB; launcher prints "sparse host-tail reads: auto" and the calib note.
#   Round 1 is reported too (it includes the one-time band timing).
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p146; mkdir -p $R
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
CAL="$LOCALAPPDATA/bonsai/sparse-calib.txt"; CALU=$(cygpath -u "$CAL")
[ -f "$CALU" ] && mv "$CALU" "$CALU.before-p146-$(date +%H%M%S)" && echo "old calib moved aside" >> $R/setup.txt
BIN='C:/bonsai/bonsai-ada-surgery/bin-d26h'   # build + CUDA runtime DLLs; try 1 at 19:02 had none and did not start
L='C:/bonsai/bonsai-ada-surgery/start-server-d26htest.ps1'
echo "engine ab9481005 bin $BIN; launcher 7f16808 test copy $L; calib $CAL" >> $R/setup.txt
python -c "
import sys; b=open(sys.argv[1],'rb').read(); print('launcher control bytes', sum(1 for c in b if c<32 and c not in (9,10,13)))" "$(cygpath -w ${L})" >> $R/setup.txt
for op in FLASH_ATTN_EXT GET_ROWS SET_ROWS; do echo "$op: $(PATH="/c/Users/<user>/AppData/Local/Programs/Python/Python312/Lib/site-packages/nvidia/cu13/bin:$PATH" "$BIN/test-backend-ops.exe" -o $op -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed' | tr -d '\r')"; done >> $R/setup.txt
D="64000 80000 96000 112000 128000 160000 245000"
memarm() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/$1.mem.txt & MP=$!; bash run_arm.sh $R "$@"; kill $MP
  awk '{v=$2+0; if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/$1.mem.txt >> $R/$1.txt
  O=$(ls -t logs/*-$1.out.log | head -1); grep -hE "^(window|kv|8gb) |^       " "$O" > $R/$1.launcher.txt
  E="${O%.out.log}.err.log"; grep -iE "sparse|demot|calib|late reserve" "$E" | head -60 > $R/$1.engine.txt; }
memarm auto_r1 "BONSAI_BIN=$BIN;BONSAI_LAYER=0" "$L" "$D"; cp "$CALU" $R/calib_after_r1.txt 2>/dev/null
memarm off_r1 "BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SPARSE=0" "$L" "$D"
memarm auto_r2 "BONSAI_BIN=$BIN;BONSAI_LAYER=0" "$L" "$D"; cp "$CALU" $R/calib_after_r2.txt 2>/dev/null
memarm off_r2 "BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SPARSE=0" "$L" "$D"
# G3: run_arm with det_answer.py in place of quick_tps (same serve path)
sed -e 's#python $B/bench/quick_tps.py --base $BASE $KEYARG --depth $d#python C:/bonsai/8gb/det_answer.py --base $BASE $KEYARG --depth $d --out C:/bonsai/8gb/'$R'/$TAG.answer.txt#' run_arm.sh > $R/run_det.sh
for t in det_a det_b; do bash $R/run_det.sh $R $t "BONSAI_BIN=$BIN;BONSAI_LAYER=0" "$L" "128000"; O=$(ls -t logs/*-$t.out.log | head -1); grep -hE "^kv " "$O" > $R/$t.launcher.txt; done
cp "$CALU" $R/calib_after_det.txt 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
python - "$(cygpath -w $R)" > $R/summary.txt <<'EOF'
import os, re, sys, hashlib
R = sys.argv[1]
def means(tag):
    p = os.path.join(R, tag + '.txt'); out = {}; d = None
    if not os.path.exists(p): return out
    for line in open(p, encoding='utf-8', errors='replace'):
        m = re.match(r'code\s+depth\s+(\d+)', line)
        if m: d = int(m.group(1))
        m = re.match(r'mean decode ([\d.]+)', line)
        if m and d: out[d] = float(m.group(1))
    return out
for rnd in ('r1', 'r2'):
    a, o = means('auto_' + rnd), means('off_' + rnd)
    print(f'== round {rnd[1]} (auto vs off, mean decode tok/s)')
    for d in sorted(set(a) | set(o)):
        x, y = a.get(d), o.get(d)
        r = f'{(x / y - 1) * 100:+.1f} %  ({x / y:.2f}x)' if x and y else 'n/a'
        flag = ''
        if x and y and x < y * 0.98: flag = '  <-- below off x 0.98'
        print(f'{d:>7}  auto {x}  off {y}  {r}{flag}')
for t in ('auto_r1', 'off_r1', 'auto_r2', 'off_r2', 'det_a', 'det_b'):
    p = os.path.join(R, t + '.txt')
    if not os.path.exists(p): print(t, 'MISSING'); continue
    s = open(p, encoding='utf-8', errors='replace').read()
    print(f'{t}: one-token {s.count("(1 tok)")}; ' + '; '.join(l for l in s.splitlines() if l.startswith(('trace min', 'did not', 'det depth', 'min free'))))
h = []
for t in ('det_a', 'det_b'):
    p = os.path.join(R, t + '.answer.txt')
    h.append(hashlib.sha256(open(p, 'rb').read()).hexdigest() if os.path.exists(p) else None)
print('G3 determinism:', 'IDENTICAL' if h[0] and h[0] == h[1] else 'DIFFERENT', h)
for c in ('calib_after_r1.txt', 'calib_after_r2.txt', 'calib_after_det.txt'):
    p = os.path.join(R, c)
    print('==', c); print(open(p, encoding='utf-8', errors='replace').read() if os.path.exists(p) else '(none)')
EOF
cat $R/setup.txt >> $R/summary.txt; for t in auto_r1 auto_r2 off_r1; do echo "== $t launcher"; cat $R/$t.launcher.txt; done >> $R/summary.txt
