#!/usr/bin/env bash
# P153 (#138 T1, the 2060 side of the 4070's T1-b): save a conversation to disk, restore it on a fresh server, continue it.
# bundle-20261016 zip bins (release_1016) + launcher branch launcher-slot-save-path (BONSAI_SLOT_SAVE_PATH -> --slot-save-path)
# as a test copy; defaults (q3_0, auto sparse, line ~80.4k). Script: the 4070's t1b_slot.py (copy in benchx/, plus a
# T1B_THINK switch). Slot files on the 970 EVO Plus NVMe (C:\bonsai\8gb\slots).
# Per depth 65,536 / 131,072 / 245,000: server 1 request 1 (A) + save + request 2 (D2, in memory); server 2 fresh: restore +
# request 2 (B2). At 64k also server 3 fresh: request 2 with no restore (C2). Then the THINKING-ON case at 64k (T1B_THINK=1,
# max_tokens 1024): the template drops the reasoning from the history, so request 2 may not extend the saved tokens.
# Gates (declared before the run, as T1-b): G1 save / restore no error, server healthy. G2 B2 == D2 byte for byte.
# G3 prompt_n of request 2 after restore <= 1,024. G4 restore + request-2 prompt time <= 30 s at 245k.
# Thinking-on arm: reported, not gated (expected: G3 fails if the reasoning is dropped from the history).
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p153; mkdir -p $R slots
BIN=$(cd "$(dirname "$(find release_1016/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-slottest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
SW='C:\bonsai\8gb\slots'; V="BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p153_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p153_$1*.out.log 2>/dev/null | head -1); [ -n "$O" ] && grep -hE "^(kv|window|slots) " "$O" > $R/$1.launcher.txt
  echo "$(date +%T) $1 health $(curl -s localhost:8080/health)" >> $R/run.txt; }
run() { PYTHONUTF8=1 BONSAI_REPO=C:/bonsai/bonsai-ada-surgery python benchx/t1b_slot.py --key-file $KEY --slot-dir "$SW" --out $R/t1b.jsonl --state "$SW\t1b_state.json" "$@" 2>&1 | tail -1 | cut -c1-600 >> $R/run.txt; }
for D in 65536 131072 245000; do F="p153_${D}.bin"
  serve p$D "$V" && run --depth $D --phase prime --file $F
  serve r$D "$V" && run --depth $D --phase restore --file $F
  [ $D = 65536 ] && { serve c$D "$V" && run --depth $D --phase fresh --file $F; }
  ls -l slots/$F >> $R/run.txt 2>&1; rm -f slots/$F
done
export T1B_THINK=1 T1B_MAX_TOKENS=1024; F=p153_think_65536.bin
serve tp65536 "$V" && run --depth 65536 --phase prime --file $F
serve tr65536 "$V" && run --depth 65536 --phase restore --file $F
rm -f slots/$F; unset T1B_THINK T1B_MAX_TOKENS
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
python - "$(cygpath -w $R/t1b.jsonl)" > $R/summary.txt <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding='utf-8')]
by = {}
for r in rows: by.setdefault((r['depth'], r['phase'], 'think' in r['file']), r)
for (d, ph, th), r in sorted(by.items()):
    keep = {k: r.get(k) for k in ('a_prompt_n', 'a_prompt_ms', 'save_wall_s', 'file_mib', 'restore_wall_s', 'restore_error', 'save_error', 'prompt_n', 'prompt_ms', 'request_wall_s')}
    print(d, ph, 'THINK' if th else '', keep)
for th in (False, True):
    for d in (65536, 131072, 245000):
        p, rs = by.get((d, 'prime', th)), by.get((d, 'restore', th))
        if p and rs:
            print(f"{'THINK ' if th else ''}{d}: B2 == D2: {rs.get('answer') == p.get('answer')}; prompt_n after restore {rs.get('prompt_n')}; restore + prompt {((rs.get('restore_wall_s') or 0) + (rs.get('prompt_ms') or 0) / 1000):.2f} s")
PY
cat $R/run.txt >> $R/summary.txt
