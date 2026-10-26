# Turing code on the RTX 4070 (turing-proxy-20261026)

Plan written before the runs (2026-10-26, about 15:30).

## Question

The 8 GB cards (RTX 2060 SUPER, Turing, sm_75) run other attention code than the RTX 4070: 64 cells per tile in the
tensor-core flash-attention kernel, and no `cp.async`, so f16 tiles also load synchronously. The 8 GB prefill reads
an f16 copy of the cache (patches 0038 and 0051). Prefill ideas for 8 GB cards can only be tested on the rig, and the
rig is busy (P229 now).

Can the RTX 4070 run the Turing code? A build with only `compute_75` PTX (`CMAKE_CUDA_ARCHITECTURES=75-virtual`) is
compiled by the driver for the 4070 at the first run. In the device code `__CUDA_ARCH__` is 750, so the kernel uses the
Turing configs and no `cp.async`. The host picks the kernel configs with `ggml_cuda_highest_compiled_arch(cc)`, and
for that build this is 750 too, so host and device agree. No source change is necessary.

The proxy has the 4070's SM count, clocks, cache and memory, so its speeds are not Turing speeds. It can show (1) that
the Turing code gives the correct numbers, and (2) the direction of an A/B for the Turing code. A rig run must confirm
every result before a release.

## Builds

- `tp-null`: engine `810d93e5aa` (bundle-20261025), `75-virtual` only.
- `tp-p4`: engine `a38714c63d` (bundle-20261026 candidate, patch 0072), `75-virtual` only.
- The CUDA JIT cache: its own folder and 4 GiB (`CUDA_CACHE_PATH`, `CUDA_CACHE_MAXSIZE`), so the first JIT is done one time.

## Runs and gates (declared before the runs)

| Run | What | Gate |
|---|---|---|
| T0a | `test-backend-ops -o FLASH_ATTN_EXT` with `tp-p4` | all pass |
| T0b | `llama-perplexity` PPL with `tp-null` and `tp-p4`, the R7a cells (q3_0 and q4_0; `-ub 512` at 8,192, 2 chunks; `-ub 1 / 4 / 8` at 2,048, 1 chunk) | `tp-null` and `tp-p4` logit files byte-identical (as R7a). Proxy validity: when the rig's P229 log arrives, its PPL values equal the proxy's to 4 decimals in all 8 cells. A PPL that is not the same as the RTX 4070's native value (R3) shows that the proxy runs other code than the native build |
| T0c | `llama-bench` q3_0, batch-invariant on: pp512 at depth 32,768 with `GGML_CUDA_FA_PREFILL_F16` = 0 and = 32768, `tp-null` | proxy realism: the f16 copy is faster than the in-place read, as on the rig (P25: +18 % at 32k). If not, the proxy speeds say nothing about Turing prefill and T1/T2 speed results are not used |
| T1 | `tp-null` against `tp-p4`, q3_0 and q4_0: tg128 at 32k and 64k, pp512 at 32k with the f16 copy off (in-place) and on | prediction for R7b (decode); the in-place read with 0072 against the f16 copy (if in-place is now as fast as the copy, the 8 GB cards could save the copy's pool memory) |
| T2 | only if T0c passes: a register prefetch for f16 tiles when there are no pipeline stages (Turing), V only or half a tile (a full K+V prefetch is 128 registers per thread) | identity: logits byte-identical to `tp-p4`; speed: pp512 at 32k with the f16 copy at least 1.03x in the proxy, then a rig run |

Each run gets a line in `runs.jsonl` and its raw output in `data/`.

Amendment (15:35, before any result): the PTX build cannot run. The driver (610.88, CUDA 13.3) does not JIT the PTX of
nvcc 13.4 ("the provided PTX was compiled with an unsupported toolchain"). A newer driver is a system change, so the
builds now use `-DCMAKE_CUDA_ARCHITECTURES=OFF -DCMAKE_CUDA_FLAGS=-gencode=arch=compute_75,code=sm_89`: the front end
compiles the Turing code (`__CUDA_ARCH__` 750), and ptxas makes sm_89 machine code for it. No JIT is necessary. A
test kernel built this way prints `__CUDA_ARCH__` 750 on the 4070, and the host sees `__CUDA_ARCH_LIST__` 750. The
JIT cache settings are now not necessary. Everything else is as planned.

## Results (15:36-16:39)

Log: [`data/tp.log`](data/tp.log). Every row: [`runs.jsonl`](runs.jsonl). Scripts: `data/*.sh`, `data/*.cmd`.

| Run | Result | Verdict |
|---|---|---|
| T0a | `tp-p4` FLASH_ATTN_EXT 3115 / 3115 | PASS |
| T0b | 8 / 8 cells byte-identical (`tp-null` against `tp-p4`). PPL q3_0 6.6695 / 6.7441 / 6.7514 / 6.7377, q4_0 6.6458 / 6.7203 / 6.7179 / 6.7281 (cells as R7a). Native RTX 4070 (release-20261026 R3): q3_0 6.6592 / 6.7511 / 6.7502 / 6.7403, q4_0 6.6371 / 6.7217 / 6.7259 / 6.7212: other values, so the proxy runs other code than the native build | identity PASS; rig comparison open (P229) |
| T0c, first run | not valid: at depth 32,768 + 512 the KV length (33,280) is more than `GGML_CUDA_FA_PREFILL_F16=32768`, and `GGML_CUDA_FA_CHUNK` was not set, so the f16 copy did not run. All rows of that run are in-place reads (they are kept as T1 data) | INVALID |
| T0c, rerun | the 8 GB launcher's settings (`GGML_CUDA_FA_PREFILL_F16=32768`, `GGML_CUDA_FA_CHUNK=32768`), q3_0, pp512, 2 repeats: in-place 1093.8 / 873.4 tok/s (8k / 32k), f16 copy 1086.8 / 846.2. In the proxy the copy is 0.6 % / 3.1 % slower. On the rig it was 18 % faster at 32k (P25) | realism FAIL |
| T1 decode | tg128, `tp-null` -> `tp-p4`: q3_0 61.00 -> 61.92 (1.015x, 32k), 56.28 -> 57.72 (1.026x, 64k); q4_0 60.85 -> 61.49 (1.011x), 56.07 -> 57.30 (1.022x) | prediction for R7b decode: faster, not slower |
| T1 prefill, in-place | pp512 at 32k: q3_0 873.4 -> 892.7 (1.022x), q4_0 872.7 -> 899.2 (1.030x) (the T0c rerun means) | as on the native 4070 |
| T1 prefill, f16 copy | 0072 does not change the f16 path: q3_0 846.2 -> 846.0, q4_0 846.4 -> 845.9 | as expected |
| T2 identity | `GGML_CUDA_FA_F16_V_ROWS` 16 / 32 / 64: FLASH_ATTN_EXT 3115 / 3115 each; logits byte-identical to `tp-p4` for an f16 cache (`-ub 512` at 8,192, `-ub 8` at 2,048) and for q3_0 with the f16 copy | PASS |
| T2 speed | pp512 with the f16 copy, 2 repeats, `tp-p4` -> V_ROWS 16 / 32 / 64: 8k 1087.3 -> 1090.1 / 1089.8 / 1092.6; 32k 846.6 -> 860.0 / 861.4 / 861.8 (1.016x / 1.017x / 1.018x) | under 1.03x, and T0c failed, so not decided here: rig run |

### What this shows

- The method works for correctness: Turing kernel code (64-cell tiles, no `cp.async`) runs on the 4070 with the
  Turing host configs, passes the kernel tests, and gives the identity results of R7a without the rig.
- The method does not work for Turing prefill speed. The 4070 has 36 MB of L2 cache and more memory bandwidth than
  the 2060 SUPER (4 MB), so the loads wait less, and work that hides load time gains less. In the proxy the 8 GB
  launcher's f16 copy is slower than the in-place read; on the rig it was faster. Speed results from the proxy are
  only a direction for the rig, not evidence.
- Two questions for the rig (P230, after P229): (1) with 0072, is the in-place read now as fast as the f16 copy on the
  2060? Then the 8 GB preset could drop the copy and its pool memory (about 240 MiB at 60k). (2) Does
  `GGML_CUDA_FA_F16_V_ROWS` help there, where the loads wait longer?
