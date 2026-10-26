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
