#!/usr/bin/env bash
# P134: new NVIDIA driver baseline. Windows Update installed "NVIDIA Display Driver Update (32.0.16.1088)" = 610.88 at
# 2026-10-14 02:29-02:30 and restarted the PC (planned, TrustedInstaller / MoUsoCoreWorker). All runs before: 591.86.
# Same binary, launcher and arms as P126b (bundle-20261013 vs bundle-20261011, alternated, 64k -> 96k -> 128k) + op tests.
# Reading (declared before the run): the driver effect = these numbers vs P126b (591.86: 1013 means 35.65 / 25.95 / 17.1;
# 1011 36.0 / 26.0 / 16.85). Gate for continuing the queue: op tests pass and 0 one-token; report the driver delta.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p134; mkdir -p $R
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
nvidia-smi --query-gpu=driver_version,name --format=csv,noheader > $R/driver.txt
L='C:/bonsai/bonsai-ada-surgery/start-server-1010test.ps1'
B11=$(cd /c/bonsai/8gb/release_1011/x/bin && pwd -W); B13=$(cd /c/bonsai/8gb/release_1013/x/bin && pwd -W)
for o in ADD RMS_NORM FLASH_ATTN_EXT GATED_DELTA_NET; do echo "$o: $(/c/bonsai/8gb/release_1013/x/bin/test-backend-ops.exe -o $o -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed' | tr -d '\r')" >> $R/tests.txt; done
for r in 1 2; do
  bash run_arm.sh $R b1011_r$r "BONSAI_BIN=$B11;BONSAI_LAYER=0" "$L" "64000 96000 128000"
  bash run_arm.sh $R b1013_r$r "BONSAI_BIN=$B13;BONSAI_LAYER=0" "$L" "64000 96000 128000"
done
{ cat $R/driver.txt $R/tests.txt; for a in b1011_r1 b1013_r1 b1011_r2 b1013_r2; do f=$R/$a.txt; O=$(ls -t logs/*-$a.out.log | head -1)
    echo "== $a: $(grep -c '(1 tok)' $f) one-token; $(grep -hE '^kv +tiered' "$O" | cut -c1-60)"; grep -E "loaded|mean decode|did not" $f; done
  echo "P126b (591.86) means: 1011 36.0 / 26.0 / 16.85; 1013 35.65 / 25.95 / 17.1"; } > $R/summary.txt
