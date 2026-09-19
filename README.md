# Bonsai 2 27B on a 12 GB card: CUDA decode surgery for ternary GEMV

Kernel-level work on the [PrismML llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp)
that makes 1.58-bit ternary (`PTQ1_0`) decode run at the DRAM ceiling on consumer NVIDIA
cards, measured and profiled on an RTX 4070 12 GB with Bonsai 2 27B.

**Same weights, same 1.75 bits per weight, bit-identical math.** Nothing is re-quantized.
Every kernel change is verified against the CPU reference (`test-backend-ops`, all 153
PTQ1_0 GEMV / GEMM shapes), by byte-identical greedy generations with each change on/off,
and by perplexity at batch 2048 (7.6740 vs 7.6742 stock).

| RTX 4070 12 GB, Bonsai-2-27B PTQ1_0, TG128 | tok/s | vs stock |
| --- | ---: | ---: |
| Stock Prism CUDA build, stock clocks | 50.9 | - |
| + kernel surgery (this repo), stock clocks | 60.1 | +18% |
| + kernel surgery, GDDR6X +1500 MHz | 67.4 | **+32%** |

Prefill doubled too: llama-bench pp2048 630 -> 1304 tok/s (**2.07x**), live server 2k-context
prefill 617 -> 1275 tok/s, 35k-context prefill 498 -> 847, first token on a 1611-token
prompt 2.75 s -> 1.39 s. Same +1500 memory clock either side; prefill is compute-bound.

## Upstream status

Everything here is submitted to PrismML's fork so it lands in their official binaries (and
from there in whatever bundles their llama.cpp) without anyone needing this repo:

| PR | What | Gain on RTX 4070 |
| --- | --- | ---: |
| [PrismML-Eng/llama.cpp#215](https://github.com/PrismML-Eng/llama.cpp/pull/215) | decode: SoA q8 activations + exact isum, warp-per-row small-K GEMV, GDN gather fusion | +18% TG |
| [PrismML-Eng/llama.cpp#214](https://github.com/PrismML-Eng/llama.cpp/pull/214) | prefill: branch-free PTQ1_0 MMQ tile loader + full Ampere tile table | 2.07x pp2048 |
| [PrismML-Eng/llama.cpp#216](https://github.com/PrismML-Eng/llama.cpp/pull/216) | prefill: 4-column GDN warp layout on all Ampere+, not only GB10 | +6% pp2048 |

The three are independent and apply in any order. Until they merge, the branch below is
exactly those three commits on top of Prism's `prism` branch.

The card is one of the slowest "12 GB" parts for this workload (504 GB/s). The same
patches should help any GPU that runs the small-K PTQ1 GEMV geometry: Ampere and Ada
consumer cards, and (untested) Blackwell. Please run the receipt and open an issue with
your numbers.

## What the patch does (and why)

Full write-up with measurements: [`surgery/ADA4070_PTQ1.md`](surgery/ADA4070_PTQ1.md).

1. **Exact integer sums for the q8 activations.** `quantize_q8_1<exact_isum>` stores the
   int16 sum of each 32-value block; the ternary vec-dot accumulates raw trits {0,1,2}
   with DP4A and corrects once per block, deleting a `__vsub4` (no native SIMD byte
   subtract on sm_89) from every 4-weight round. Throughput flat, 13 W less power.
2. **Warp-transposed (SoA) activation layout.** In the small-K geometry every lane owns a
   K-block and read 36 activation words from `block_q8_1` structs 144 B apart per lane:
   ~36 L1 lines per warp load, ~1300 L1 wavefronts per K-iteration for activations vs
   ~250 for the weights. That LSU pressure capped every GEMV at ~370 GB/s. Grouping
   K-blocks by 32 and storing word *w* of the group contiguously makes the same load one
   wavefront. Same bytes, no staging, no shuffles. 50.9 -> 55.7 tok/s.
3. **Warp-per-row small-K geometry.** The stock loop strides K-blocks across the whole
   128-thread block, so for K=5120 only threads 0..39 ever load anything; two of four
   warps just hold SM slots. Each warp now owns a row and its lanes stride that row's
   K-blocks (shuffle reduction, no shared memory, no barrier). qkv 391 -> 445 GB/s,
   lm_head 414 -> 460 GB/s. 55.7 -> 58.1 tok/s.
4. **GatedDeltaNet state gather folded into the recurrence kernel.** The per-layer
   `GET_ROWS` of the 3 MB recurrent state left 3 MB dirty in L2 that was written back in
   the middle of the FFN weight stream (gate/up GEMV 100 us in GDN layers vs 85 us in
   attention layers, same kernel). The kernel now indexes the cache directly.
   58.1 -> 60.1 tok/s. `GGML_CUDA_GDN_GATHER_FUSION=0` restores the old path.
5. **Raise the DRAM ceiling.** After 1-4 the GEMV sits at ~93% of the P2-state memory
   bandwidth, so the memory clock is the remaining lever. Swept with Afterburner: +1500
   MHz is stable and bit-exact on this card, +1750 is flat (GDDR6X EDR replay), +2000
   TDRs. 60.1 -> 67.4 tok/s. See `surgery/afterburner_apply.ps1`.
6. **Prefill: branch-free PTQ1_0 MMQ tile loader + full tile table.** Prompts take the
   int8 tensor-core MMQ path, and PTQ1_0 ran it at half PQ2_0's speed. Its Ampere tile
   table stopped at `mmq_x = 64` (every other type goes to 128), and its shared-memory
   tile loader split a block's 8 lanes into three divergent `if / else if` branches, so
   each warp serialized 12 trit-unpack iterations for 5 of work. Uniform loop, per-lane
   store offsets only. pp2048 630 -> 1304 tok/s (2.06x), bit-identical output.
7. **GDN 4-column warp layout on Ada.** Prism's `cols_per_warp = 4` GatedDeltaNet path was
   gated to GB10. Nothing in it is GB10-specific, and prefill runs the recurrence serially
   over every token, so the kernel's per-step efficiency is prefill-critical. Neutral for
   decode, +6% pp2048 on the 4070 (1220 -> 1297 with cut 6 in place).

Things that were tried and did not help on Ada, with the measurements: a LUT trit unpack
(0.29x), L2 prefetch, L2 persistence windows, nwarps changes, forcing MMQ, PDL off,
`__stwt` write-through state stores. They are in the write-up so nobody repeats them.

How the bottlenecks were found: `surgery/cupti_trace/` is a 200-line CUPTI injection
profiler (`CUDA_INJECTION64_PATH`, no toolkit install, dynamically loads the CUPTI DLL
from NVIDIA's pip wheel) that records GPU-side timestamps for every kernel including CUDA
graph replays. `surgery/cupti_analyze.py` turns the CSV into per-GEMV GB/s. Event-pair
timing under WDDM is wrong for this (host-bound issue gaps), which is documented too.

## Get the patched runtime

The kernel branch lives at
[professorpalmer/llama.cpp-ada-ternary @ `ada-ptq1-surgery`](https://github.com/professorpalmer/llama.cpp-ada-ternary/tree/ada-ptq1-surgery)
(PrismML `9a9394a` + the three PR commits above). The same commits are in
[`patches/`](patches/) for `git am` onto PrismML-Eng/llama.cpp. The profiling
instrumentation used during the investigation (`GGML_CUDA_OP_TIMING`, `GGML_CUDA_GRAPH_STATS`,
`GGML_CUDA_MMVQ_DUMP`, the env-gated L2 persistence experiment) is kept out of the PRs; it
lives on `ada-ptq1-surgery-diagnostics` if you want to reproduce the traces.

```powershell
git clone -b ada-ptq1-surgery https://github.com/professorpalmer/llama.cpp-ada-ternary vendor/prism-llama
```

### Build on Windows without the CUDA toolkit

VS 2022 Build Tools (C++ workload) plus NVIDIA's pip wheels are enough; no admin, no
3 GB installer.

```powershell
python -m pip install cmake ninja nvidia-cuda-nvcc nvidia-cuda-runtime nvidia-cublas nvidia-cuda-nvrtc
.\build\build_windows.ps1            # arch from nvidia-smi; -Arch 86 for RTX 30xx, -Arch "86;89" for both
```

Produces `bin\llama-server.exe` and `bin\llama-bench.exe` with the DLLs they need. If an
official toolkit is installed (`CUDA_PATH`) it is used instead. Linux: normal llama.cpp
CMake build of the branch with `-DGGML_CUDA=ON`.

### Model

`Ternary-Bonsai-2-27B-PTQ1_0.gguf` (5.95 GB) from
[PrismML on Hugging Face](https://huggingface.co/prism-ml). `PQ2_0` also works with these
kernels (same trits, 2.13 bpw packing) but with cut 6 it no longer prefills faster, and
it decodes slower on Ada, so there is no reason to spend the extra 1.3 GB on it.

## Serve

`start-server.ps1` is the OpenAI-compatible server (64k context, q8 KV, LAN, bearer key
in `artifacts/api_key.txt`). The community 12 GB receipt uses q4 KV and the full 262k
window; that exact serve is:

```powershell
bin\llama-server -m models\Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa on -c 262144 -np 1 -ctk q4_0 -ctv q4_0 --jinja --temp 1.0 --top-p 0.95 --top-k 20 --host 127.0.0.1 --port 8899
```

## Receipt: run it on your card

```powershell
python bench\receipt.py <tag>            # ~10 min; add --quick for a 2-minute version
```

Decode by depth (7k / 12k / 35k / 77k), prefill at 2k and at 35k, fresh decode with
power and tok/s per watt, resident VRAM for 64k / 128k / 192k / 262k windows, live-server
TTFT. Same serve flags as the community sheet (PTQ1_0, `-fa on`, q4_0 KV, one slot). It
prints a markdown table and writes `artifacts/receipt_<tag>.json`; paste both in an issue.

Results so far: [`docs/RECEIPTS.md`](docs/RECEIPTS.md).

## Layout

| Path | What |
| --- | --- |
| `patches/` | the kernel commit as a `git am`-able patch |
| `surgery/ADA4070_PTQ1.md` | the full investigation: what was measured, what worked, what did not |
| `surgery/cupti_trace/` | CUPTI injection profiler (source + build.bat) |
| `surgery/cupti_analyze.py` | trace -> per-kernel GB/s |
| `surgery/afterburner_apply.ps1`, `core_clock_sweep.ps1` | memory offset / locked core clock sweeps |
| `surgery/ab_generate.py` | greedy A/B of two env configs through llama-server |
| `bench/receipt.py` | the receipt benchmark |
| `build/` | portable Windows build (pip-wheel CUDA) |

## Status and next

Per token at +1500 (~15 ms): GEMV ~11.6 ms at the DRAM limit; ~1900 small kernels ~2.8
ms; ~1.6 ms idle (0.42 ms host turnaround between tokens). Memory clock does not touch
the last two. Next surgery is collapsing the GDN layer's 27 small kernels into ~4 fused
ones (norm+sign+FWHT+quantize feeding the GEMV; conv-state+ssm_conv+l2norm+dt/A
projections feeding GDN; gated-norm+gate+FWHT+quantize), estimated ~1.9 ms/token.
Design notes at the end of `surgery/ADA4070_PTQ1.md`.

MIT. Weights are PrismML's (Apache 2.0). Not affiliated with PrismML.
