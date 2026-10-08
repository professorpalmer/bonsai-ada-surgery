#!/usr/bin/env bash
# int8 score step evaluation: operator tests, kernel timing on the served prefill shape, KL against today's kernel.
#   bash bench/int8_eval.sh <int8-build-bin> [after-pattern-file]   -> receipts/int8_eval.log
cd "$(dirname "$0")/.." || exit 1
BIN="$1"; LOG=receipts/int8_eval.log
WBIN=$(cygpath -w "$BIN")
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
say "=== int8 eval, build $WBIN"
powershell -NoProfile -Command "\$cu='C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13'; \$env:PATH='$WBIN;'+\$cu+'\bin;'+\$cu+'\bin\x86_64;'+\$env:PATH; Set-Location '$WBIN'; \$o = & .\test-backend-ops.exe -o FLASH_ATTN_EXT 2>&1 | Out-String; (\$o -split \"\`n\" | Where-Object { \$_ -match 'tests passed|FAIL' } | Select-Object -Last 6) -join \"\`n\"" 2>&1 | tee -a "$LOG"
say "kernel timing (served prefill shape):"
powershell -NoProfile -Command "\$cu='C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13'; \$env:PATH='$WBIN;'+\$cu+'\bin;'+\$cu+'\bin\x86_64;'+\$env:PATH; Set-Location '$WBIN'; \$o = & .\test-backend-ops.exe perf -o FLASH_ATTN_EXT -b CUDA0 2>&1 | Out-String; (\$o -split \"\`n\" | Where-Object { \$_ -match 'hsk=256' -and \$_ -match 'nb=512' -and \$_ -match 'nh=4' } | ForEach-Object { (\$_ -replace '.*kv=(\d+).*?(\d+\.\d+) us/run.*?(\d+\.\d+) TFLOPS.*', 'kv=\$1  \$2 us/run  \$3 TFLOPS') }) -join \"\`n\"" 2>&1 | tee -a "$LOG"
say "KL against today's kernel (q8_0 K/V, ctx 32768, 2 chunks):"
powershell -NoProfile -ExecutionPolicy Bypass -File bench/int8_kl.ps1 -Int8Bin "$WBIN" -Ctx 32768 -Chunks 2 2>&1 | tee -a "$LOG"
say "=== done"
