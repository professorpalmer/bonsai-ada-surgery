#!/usr/bin/env bash
# P158c (after P158b, 14:55): P158b's error text: "CUDA error: device not ready | ggml_cuda_pool_vmm::alloc
# (ggml-cuda.cu:654) | cuMemSetAccess(start_ptr, reserve_size, &access, 1)" in all 3 arms (sidecar restored / absent,
# blocking on). So the first big batch after a restore cannot grow the VMM pool: VRAM pressure on an 8 GB card, not draft logic.
# Arms (bin-t3dbg, MTP on, prime 65,536 + save, fresh restore + ~4k new tokens, 10 s nvidia-smi trace per arm):
#   y_def (defaults again, with the trace), y_nopool (BONSAI_SHARED_POOL=0), y_lowline (BONSAI_KV_VRAM_CELLS=72704: ~8k cells,
#   ~110 MiB more margin). Reading (declared before the run): which arms crash; free VRAM before / after the restore and at the
#   crash; the prompt eval speed of the arms that do not crash.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p158c; mkdir -p $R slots158c
BIN='C:/bonsai/bonsai-ada-surgery/bin-t3dbg'
L='C:/bonsai/bonsai-ada-surgery/start-server-slottest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
SW='C:\bonsai\8gb\slots158c'; V="BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p158c_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done; }
grab() { E=$(ls -t logs/*p158c_$1*.err.log | head -1); O="${E%.err.log}.out.log"; { echo "== $1"; grep -hE "P158DBG|CUDA error|draft context|prompt eval" "$E" "$O" | tail -8; } >> $R/dbg.txt; }
run() { PYTHONUTF8=1 python p157_restore.py --key-file $KEY --depth 65536 --file x.bin --state $R/state.json --out $R/p158b.jsonl "$@" >> $R/run.txt 2>&1; }
serve prime "$V"; run --phase prime --tag prime; grab prime
trace() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 2; done ) > $R/$1.mem.txt & MP=$!; }
for a in "y_def|" "y_nopool|;BONSAI_SHARED_POOL=0" "y_lowline|;BONSAI_KV_VRAM_CELLS=72704"; do t=${a%%|*}; x=${a#*|}
  serve $t "$V$x"; trace $t; run --phase cont --new 4000 --tag $t; kill $MP; grab $t
  awk '{v=$2+0; if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "'$t' trace min free", m, "MiB over", NR, "samples"}' $R/$t.mem.txt >> $R/dbg.txt; done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -f slots158c/x.bin*
{ cut -c1-300 $R/p158b.jsonl; echo; cat $R/dbg.txt; } > $R/summary.txt
