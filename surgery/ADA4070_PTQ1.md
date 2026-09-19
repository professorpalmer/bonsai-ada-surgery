# 4070 surgery: invent, measure, keep the cut that actually moves Ada

RTX 4070 12 GB (sm_89, 504 GB/s, 200 W). Official Prism PTQ1_0 27B decode sits at ~50 tok/s
(~55% of the 90 tok/s weight-bandwidth ceiling). Launch tables stop at 4090. This file is
the Ada-12GB patch set, including the experiments that lost.

## Dead end: constant-memory PTQ1 LUT

Metal's `ptq1_0_lut` is the right move on Apple. Ported to CUDA `__constant__` it is a
**regression** on Ada.

`surgery/ptq1_lut_kernel.cu` compiled with wheel nvcc, ran on this 4070:

```
lut_vs_mul3_mismatches=0
rows=81920 mul3_ms=0.007 lut_ms=0.023 mul3_GBps=298.2 lut_GBps=86.3 speedup=0.29x
```

The table is bitwise-correct vs the `*3` peel (also `surgery/verify_ptq1_lut.py`, 256/256).
Random 256-entry constant-memory hits serialize. Ada integer `*3` is already cheap; the
microbench `*3` path already sits near 300 GB/s. LUT was reverted out of `vecdotq.cuh`.

## Cut 1: steal GB10's GDN 4-wide warp (the real leftover)

`gated_delta_net.cu` processes **4 columns per warp only when `__CUDA_ARCH__ == DGX_SPARK`
(sm_121)**. Ada compiled the 1-col path. That is not a hardware limit — it is a
register-tile width they never turned on for 8.9.

Patched both the device `constexpr` and the host launch:

- `cols_per_warp = 4` when `S_v == 128 && !KDA && arch/cc >= Ampere (800)`
- Spark keeps the same 4-wide path (1210 >= 800)

Bonsai 2's GDN heads are 128-wide. Decode spends a large fraction of the non-weight time
here. This is the publishable kernel change.

## Cut 2: Ada L2 prefetch on PTQ1 MMVQ

`mmvq.cu` prefetched the next quant block only for Q1/Q2/PQ2 on GB10. PTQ1 on Ada took
the `else` path with no prefetch. `prefetch.global.L2` is now issued one K-iteration
ahead on `GGML_TYPE_PTQ1_0`.

## Build (no official toolkit)

MSVC 14.44 is installed. CUDA 13.4 comes from NVIDIA's Windows pip wheels
(`nvidia-cuda-nvcc` + runtime + cublas), with `cublas.lib` / `cublasLt.lib` generated
from the DLLs (`surgery/make_import_libs.ps1`).

```
surgery/build_ada_server.ps1
```

sm_89-real only, CUDA graphs on, writes `vendor/prism-llama/build-ada`. Live
`bin/llama-server.exe` stays up until the new binary is benched.

## Bench gate

```
llama-bench -m Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa on -p 512 -n 128 -r 3
```

Baseline: TG128 ~50 tok/s (PQ2 fa-on was 50.22; PTQ1 live short chat ~54). Publish if the
GDN 4-wide + prefetch binary beats that by a repeatable delta on this 4070.

## Measured dead ends (this 4070, official PTQ1_0, -fa on, TG128 depth 0)

| Cut | TG128 |
| --- | ---: |
| Stock MMVQ 4-warp + GDN 4-wide + L2 prefetch | 50.9 |
| Constant-memory PTQ1 LUT | 0.29x microbench, not shipped |
| MMVQ nwarps=1 | 45.7 |
| MMVQ nwarps=8 | 28.2 |
| GGML_CUDA_PTQ1_FORCE_MMQ=1 | 20.3 |
| CUDA_LAUNCH_BLOCKING=1 | 50.7 (async 51.2) |
| L2 persist window on Q8 + GDN state | 50.7 |
| nvidia-smi beyond 200 W / 3105 / 10501 | refused (card max; no Afterburner) |

Launch-blocking almost matches async: the leftover is not launch tax.
4-warp small_k is a local maximum. 90 tok/s assumed memcpy-peak 504 GB/s;
51 tok/s is ~280 GB/s, which is what this 28-byte AoS GEMV actually streams.
Next cut has to change load geometry or skip work (speculative / persistent
GEMV), not retune warp count or steal GB10 tiles.

## Cut 3: the GEMV was LSU-bound on activations, not GDDR-bound (shipped)

Measured with nvidia-smi sampling during TG: SM 2747 MHz, mem 10251 MHz (GeForce
CUDA P2), 192 W against the 200 W cap, throttle reason = SW power cap. Every
PTQ1 GEMV in-graph plateaued at 340-400 GB/s regardless of shape, and the same
kernel varied 2-3x between runs with the first kernel after an idle park always
fastest: clock hunting under the cap.

Two changes, both bit-identical to the old math (test-backend-ops vs CPU
reference: 78/78 MUL_MAT, 75/75 MUL_MAT_ID ptq1_0 OK):

1. `quantize_q8_1<exact_isum>` stores the exact int16 sum of the 32 q8 values
   in `ds.y` for PTQ1 consumers. The vec-dot accumulates raw digits {0,1,2}
   with DP4A and subtracts the bias once per 32-block, deleting the `__vsub4`
   (no native SIMD byte sub on sm_89) from every 4-weight round.
   Result: TG flat (51.07), but power 192 -> 179 W and the power-cap throttle
   flag cleared. The GEMV is not ALU-bound; ALU savings became clock headroom.

2. Warp-transposed (SoA) q8 activation layout (`ggml_cuda_ptq1_q8_word`).
   In the small-K geometry PTQ1 uses on Ada (nwarps=4, rows_per_block=4) lane
   l owns K-block l and reads 36 activation words from `block_q8_1` structs
   36 B apart per K-block = 144 B apart per lane. Each warp-wide load spans
   4.6 KB = ~36 L1 lines, so a K-iteration spent ~1300 L1 wavefronts on
   activations vs ~250 on the 28 B weight blocks. At ~1 wavefront/clk/SM that
   is 2.8 B/clk/SM = ~370 GB/s at 2.79 GHz: exactly the plateau. K-blocks are
   now grouped by 32 and word w of the group is stored contiguously, so the
   same load is 32 consecutive words = 1 wavefront. Same bytes per column
   (K padded to 4096); no staging, no shuffles, no extra traffic. The MoE
   kernel and every ncols_dst route through `vec_dot_ptq1_0_q8_1_multi` with
   the column base + K-block index.

| Cut | TG128 | pp512 | power | SM clk |
| --- | ---: | ---: | ---: | ---: |
| before | 50.9 | 606 | 192 W (capped) | 2747 |
| exact isum, no vsub | 51.1 | - | 179 W | 2790 |
| + SoA q8 layout | **55.7 +-0.04** | 606 | 174 W | 2805 (max boost) |

Transferable: any g128 quant whose MMVQ gives one lane a whole block (Q1_0,
Q2_0, PQ2_0, TQ1_0 upstream) has the same AoS activation wavefront problem.

## Profiling that actually works on Windows: CUPTI injection (surgery/cupti_trace)

Event-pair timing under `GGML_CUDA_DISABLE_GRAPHS=1` is not GPU time on WDDM: the host
needs ~20 us to issue a group (2 event records + quantize + mmvq) while the GPU eats it
in ~12, so the GPU drains the queue and idles inside the brackets. That produced the
phantom "post-rotation penalty" (qkv at 165 GB/s) that moved to whatever GEMV was
scheduled first. Events captured into a CUDA graph cannot be timed
(`cudaEventElapsedTime` -> invalid argument on this driver).

`surgery/cupti_trace/cupti_trace.dll` is a 200-line CUPTI injection library
(`CUDA_INJECTION64_PATH`, no toolkit, headers + dll from the `nvidia-cuda-cupti` pip
wheel, CUPTI loaded dynamically). It records GPU-side start/end of every kernel,
including graph replays, at ~3% overhead, and writes a CSV; `surgery/cupti_analyze.py`
groups by kernel/grid. Do not flush CUPTI in `atexit` on Windows (deadlock against
driver teardown); a worker thread flushes every 250 ms instead.

In-graph truth for one decode token (17.7 ms GPU, 1.6 ms idle) before cuts 4-5:

| GEMV | grid | us | GB/s |
| --- | ---: | ---: | ---: |
| down K=17408 (all 128 lanes active) | 5120 | 42.4 | 460 |
| gate+up fused, small_k | 4352 | 102.6 | 380 |
| gate / up unfused, small_k | 4352 | 55.5 | 351 |
| qkv small_k | 2560 | 29.3 | 391 |
| z small_k | 1536 | 18.5 | 363 |
| lm_head | 62080 | 657 | 414 |

## Cut 4: warp-per-row small_k geometry (shipped)

The stock small_k loop is `for (kbx = tid; kbx < blocks_per_row_x; kbx += 128)`. With
K=5120 (40 blocks) only threads 0..39 ever enter it: warp 0 full, warp 1 eight lanes,
warps 2-3 only wait at the block barrier while occupying SM warp slots. 48 resident
warps per SM, ~15 issuing loads. The K=17408 geometry keeps all four warps streaming
and reaches 460 GB/s; that is the whole difference.

`mul_mat_vec_q` now takes a PTQ1 small_k branch where warp w owns row row0+w and its
32 lanes stride that row's K-blocks: every warp loads, shuffle reduction, no shared
memory, no `__syncthreads`. Same grid, same bytes. qkv 391 -> 445 GB/s, wq 388 -> 442,
z 363 -> 415, lm_head 414 -> 460. TG 55.7 -> 58.1. Power hit the 200 W cap again
(189 W avg, throttle 0x4, SM 2743): the L1 wall moved to the power wall.

## Cut 5: fold the recurrent-state gather into the GDN kernel (shipped)

CUPTI showed the fused gate+up GEMV at 100 us in GDN layers and 85 us (459 GB/s) in
attention layers, identical kernel and shapes; in unfused layers `gate` 48 us then
`up` 53 us. Each GDN layer leaves 6 MB dirty in L2 (3 MB GET_ROWS temp of the state
plus 3 MB new state); a 36 MB L2 evicts it as writebacks ~36 MB of weight stream
later, i.e. inside gate/up. 6/39 = 15% extra DRAM bytes = the 85 -> 100 us.
`__stwt` does nothing here (device stores land in L2 regardless), tested and reverted.

The reducible half is the temp. Prism's "rows mode" only exists for the snapshot-ring
path (`n_rs_seq > 0`) on CPU/Metal, so this is done in the CUDA backend:
`ggml_cuda_try_gdn_gather_skip` matches GET_ROWS(cache, ids) -> [RESHAPE] ->
GATED_DELTA_NET src[5] with a single consumer and n_seqs == 1, skips the GET_ROWS and
registers (cache base, ids, row stride); the kernel indexes `cache + ids[seq]*stride`.
Removes an 8.4 us kernel and 3 MB of dirty L2 per GDN layer.
`GGML_CUDA_GDN_GATHER_FUSION=0` restores the gather. 200 greedy tokens identical on/off.
TG 58.3 -> 60.1 (llama-bench), 57.0 -> 59.5 (live server).

| Cut | TG128 | vs baseline |
| --- | ---: | ---: |
| baseline (stock Prism CUDA, PTQ1_0) | 50.9 | - |
| 3: exact isum + SoA q8 activations | 55.7 | +9.4% |
| 4: warp-per-row small_k | 58.1 | +14.1% |
| 5: fused GDN state gather | 60.1 | +18.1% |

Same weights, same 1.75 bpw, bit-identical GEMV math (test-backend-ops 153/153 vs CPU).

## Cut 6: raise the DRAM ceiling itself (Afterburner memory offset, shipped)

Once the GEMV is truly DRAM-bound (cuts 3-5), the only lever left on the bytes is the
memory clock. `surgery/afterburner_apply.ps1 -Profile N` writes the per-GPU profile cfg
and applies it (self-elevates; one UAC prompt). `surgery/bench_with_smi.py` confirms the
clock actually held under load (Afterburner offsets are in kHz; llama-bench TG128,
same binary, mem clock read by nvidia-smi during the run):

| mem offset | mem clock | TG | vs stock clocks | driver events |
| --- | ---: | ---: | ---: | --- |
| 0 | 10251 (P2) | 60.3 | - | none |
| +500 | 10751 | 62.6 | +3.8% | none |
| +1000 | 11251 | 64.7 | +7.3% | none |
| +1300 | 11551 | 66.3 | +9.9% | none |
| **+1500** | **11751** | **67.4** | **+11.8%** | none |
| +1750 | 12001 | 67.2 | +11.4% | none (EDR replay knee) |
| +2000 | 12251 | 68.2 | +13.1% | **TDR** (nvlddmkm 14 + 4x153), driver reverted OC |

+1500 is the operating point: 153/153 GEMV shapes bit-exact vs CPU, 400 greedy tokens
identical to stock clocks, 3 x 1024-token soak at 65.3 +-0.1 with zero driver events,
57 C. GDDR6X EDR makes over-clock show up as flat throughput (+1750) before it becomes a
hang (+2000); do not run above +1500 on this card. Live server: 59.5 -> 64.2 t/s.

Locked SM clock under +1500 (`surgery/core_clock_sweep.ps1`, `nvidia-smi -lgc`):
2100 -> 61.1 @ 135 W, 2400 -> 66.0 @ 147 W, 2600 -> 67.2 @ 162 W, default (power-cap
hunting 2505-2820) -> 67.6 @ 184 W. The kernel still needs ~2400 MHz of LSU issue rate;
locking 2600 gives 99.5% of the throughput at 88% of the power with the cap flag clear.
Power cap on this card is fixed at 200 W by vBIOS (`power.max_limit`).

| Cut | TG128 | vs baseline |
| --- | ---: | ---: |
| baseline (stock Prism CUDA, stock clocks) | 50.9 | - |
| 3+4+5 kernel surgery | 60.1 | +18% |
| 6: +1500 MHz memory | 67.4 | **+32%** |

## Cut 7: prefill, the PTQ1_0 MMQ tile loader was divergent (shipped)

Prefill takes the MMQ path (int8 tensor-core GEMM over shared-memory tiles), and PTQ1_0
prefilled at half the speed of PQ2_0 from the same weights: llama-bench pp2048 630 vs
~1300 t/s. CUPTI on a pp2048 run put the whole gap in `mul_mat_q<PTQ1_0>`: 2.7x the
per-call time of the PQ2_0 instantiation for identical shapes. Two causes, both in code
that never ran on a DGX Spark hot path:

1. `mmq-config-ampere.cuh` capped PTQ1_0 at `mmq_x = 64`; every other type (PQ2_0
   included) has 80/96/112/128 entries. So a 2048-token prompt ran twice the number of
   K-passes over the weight tiles. Adding the four missing `CASE` lines: 630 -> 914 t/s.
2. `ggml_cuda_mmq_load_tiles_ptq1_0` unpacked each 28-byte block with an
   `if (lane < 4) ... else if (lane < 6) ... else if (lane == 6)` chain: lanes 0-3 ran five
   `*3` trit-extraction iterations, lanes 4-5 five more, lane 6 two, lane 7 idle. Divergent
   branches execute serially within a warp, so every warp paid 12 iterations for 5 of work
   while PQ2_0's loader is uniform. Rewritten so all 8 lanes run the same 5-iteration loop
   on their own 32-bit word of the block (lane 6 walks the two qh bytes in both 16-bit
   halves and recombines adjacent digits with one `__byte_perm`); only the shared-memory
   store offsets differ per lane. 914 -> 1304 t/s.

| llama-bench, official PTQ1_0, -fa on, +1500 mem | pp512 | pp2048 | tg128 |
| --- | ---: | ---: | ---: |
| before cut 7 | 630 | 630 | 66.7 |
| + wide MMQ tiles | 915 | 913 | 66.7 |
| + branch-free loader | **1304** | **1297** | 66.9 |

Correctness: test-backend-ops MUL_MAT 78/78 and MUL_MAT_ID 75/75 PTQ1_0 shapes vs CPU,
greedy 300-token generation identical, `llama-perplexity -c 2048 -b 2048` on a 4-chunk
text 7.6740 vs 7.6742 stock (float noise) at 1.80 vs 3.59 s per pass. PTQ1_0 now prefills
at PQ2_0 speed while keeping its faster Ada decode, so there is no longer a reason to
pick the 7.2 GB pack on this card.

A first version of the loader that pre-advanced lane 6's high half by one trit and stored
from inside the loop failed 21/78 shapes despite bit-identical arithmetic in emulation;
the plain register-array form above is what shipped. Left as a note for anyone tempted
by the shorter version.

## What is left (in-graph, per token, ~15 ms at +1500)

Stock-clock breakdown (CUPTI): GEMV 13.3 ms (75%), ~1900 small kernels 2.8 ms (16%),
idle 1.6 ms (9%). Memory OC scales only the first term; the other 4.4 ms is now 29% of
the token and is the next target. PDL kernels start early and their CUPTI duration
includes the wait on the predecessor, so per-kernel numbers below are critical-path
contributions, not work.

Plan (GDN layer: 27 small kernels -> ~4, est. -40 us/layer = -1.9 ms/token, ~+13%):
- After the down / ssm_out GEMV: residual add + rms_norm(weight) + sign flip + FWHT +
  q8_1 quantize (SoA exact-isum layout) as one single-row kernel that hands the q8
  buffer straight to the next MMVQ (needs a "pre-quantized src1" slot in mmvq; Prism's
  gb10 shared-q8 path is the template). 2x per layer, all 64 layers.
- After qkv/z GEMVs: conv-state shift (concat+cpy) + ssm_conv + silu + l2_norm(q,k) +
  the two bf16 [5120x48] projections (concat their weights at load) in one kernel that
  feeds GDN.
- After GDN: norm_gated + sigmoid*z + cpy + FWHT + quantize as one kernel.
- Host side: 0.42 ms inter-token turnaround (graph param refresh + logits D2H +
  sampling); check Prism's graph-reuse path is active for the server.

- GEMV 13.3 ms at 415-460 GB/s. 460 is ~93% of the 492 GB/s the P2 memory clock
  (10251 MHz) allows; the ceiling is now DRAM and the 200 W cap, not the kernel.
- ~27 small kernels per GDN layer, 59 us/layer: rms_norm(3.3)+fwht(1.3)+quantize(1.1)
  twice, norm_gated+sigmoid*mul+cpy+fwht+quant, concat+cpy+get_rows+ssm_conv, two bf16
  [5120x48] GEMVs, l2_norm, GDN. Fusing these is worth ~1.2 ms/token.
- 0.42 ms inter-token host turnaround, 2 x 2.2 us stalls per layer (stream fork/join).
