# Bonsai 2 27B: the full 262k window at q8_0 on a 12 GB card

The model's **full 262,144-token trained window with q8_0 KV cache on a 12 GB RTX 4070**, and the
speed and serving recipe that make that window usable. Patched [PrismML llama.cpp](https://github.com/PrismML-Eng/llama.cpp)
for Bonsai 2 27B (1.58-bit ternary `PTQ1_0`, 5.9 GB) with the MTP draft head. Same weights, nothing
re-quantized; every kernel checked against the CPU reference.

| RTX 4070 12 GB, served, one slot | decode (tok/s) | prefill (tok/s) |
| --- | ---: | ---: |
| 4k tokens of context | **83** | 1,100 |
| 16k | **106** | 1,100 |
| 32k | **100** | 918 |
| 64k | **87** | 724 |
| 112k (last position in VRAM) | **70** | 539 |
| 131k | **41** | 374 |
| 180k | 27 | 298 |
| 258k (the window's end) | 14.7 | 229 |

Greedy code continuation, 256 tokens, MTP draft head on, cumulative prefill; GDDR6X +1500 MHz (as in every
number in this repo since #221), display on the CPU's iGPU. What those numbers replace:

| | before (this repo, Sep 2026) | now |
| --- | --- | --- |
| window on 12 GB with q8_0 KV | 96k (q4_0 for 262k) | **262,144** |
| decode at 32k / 64k | 47.6 / 36.9 | **100 / 87** |
| KV precision at 262k | q4_0: 1 flipped top token in 48 | q8_0: **1 in 160** |
| apps that send `effort: "high"` | HTTP 500 on every request | answered (normalized to medium) |
| apps with a 256-4096 token cap, thinking on | cut off mid-think | answered (cap raised to the think budget) |

How, and every receipt: [`docs/Q8_FULL_CONTEXT.md`](docs/Q8_FULL_CONTEXT.md). Short version:

- **Tiered KV cache** (`--kv-vram-cells`): the first ~113k positions of each layer's K/V live in VRAM, the rest
  in pinned system RAM mapped into the same CUDA address range. Kernels are unchanged and output is
  **bit-identical** to an all-VRAM cache. Past the line, attention copies the used RAM rows into VRAM with the
  copy engine first.
- **MTP drafting at every depth** (`--spec-draft-window`): the draft head only needs recent context, so its cache
  keeps the last 16k rows and stays small. With quantized-KV decode on the tensor-core attention kernel (one K/V
  read per verify batch), drafting now pays at every depth; the old 24k cutoff is gone.
- **Harness-proofing** (`--reasoning-effort-allow`, `--reasoning-max-tokens-floor`): the same weights score 0 to
  160 of 164 on HumanEval depending on what the client sends. The server absorbs both causes.

## Quick start (Windows, NVIDIA)

1. Download `bonsai-bundle-win-x64.zip` from [Releases](../../releases) and unzip into this repo (it fills
   `bin\`), or build it (below). Binaries carry sm_75 / 86 / 89 machine code (RTX 20 / 30 / 40) plus compute_89
   PTX that RTX 50 cards compile at first load; they need only the NVIDIA driver.
2. Put `Ternary-Bonsai-2-27B-PTQ1_0.gguf` from [prism-ml on Hugging Face](https://huggingface.co/prism-ml) in
   `models\`.
3. Recommended: build the MTP draft-head file (lossless speculative decoding, +50-100% decode).

   ```powershell
   git clone -b bonsai-q8-product https://github.com/professorpalmer/llama.cpp-ada-ternary vendor\prism-llama
   .\build\make_mtp_procreations.ps1   # ProCreations on-policy Q8 head grafted onto PTQ1_0
   ```

   It sparse-fetches the `blk.64` tensors from
   [ProCreations/Ternary-Bonsai-2-27B-MTP](https://huggingface.co/ProCreations/Ternary-Bonsai-2-27B-MTP), grafts
   them with [sudoingX's tools](https://github.com/sudoingX/bonsai2-small-gpu) and proves the trunk bytes by
   hashing against the original. `make_mtp_lean.ps1` is the older teacher-head graft (-4.3 pp acceptance).
4. Serve:

   ```powershell
   .\start-server.ps1
   ```

   OpenAI-compatible API on `http://<host>:8080/v1`, bearer key in `artifacts\api_key.txt` (created on first
   run), LAN exposed. `start-remote.ps1` adds a Cloudflare tunnel.

`start-server.ps1` sizes everything at launch: it reads free VRAM, keeps a safety margin below the point where
Windows demotes a background process's memory, and puts as many positions in VRAM as fit. Binaries from before
the tiered-KV runtime are detected and get the previous 96k all-VRAM recipe.

### Knobs (environment variables)

| Variable | Default | |
| --- | --- | --- |
| `BONSAI_CTX` | 262144 | context window |
| `BONSAI_CTK` | q8_0 | K/V cache type (q4_0: 12x the flipped tokens, see Quality) |
| `BONSAI_TIER` | 1 | 0 = all-VRAM cache (then 96k window) |
| `BONSAI_KV_VRAM_CELLS` | auto | pin the VRAM line |
| `BONSAI_VRAM_MARGIN` | 1000 (display on iGPU) / 1300 | MiB kept free below the demotion point |
| `BONSAI_SPEC` / `BONSAI_SPEC_DEEP` | 2 / 4 | draft size, and past the VRAM line |
| `BONSAI_DRAFT_WINDOW` | 16384 | rows the draft head keeps |
| `BONSAI_EFFORT` | medium | server default reasoning effort |
| `BONSAI_THINK` | 1 | 0 = thinking off for every request |
| `BONSAI_THINK_BUDGET` | 20480 | thinking tokens before a forced close (-1 unlimited) |
| `BONSAI_HARNESS_PROOF` | 1 | 0 = pass effort words and output caps through unchanged |
| `BONSAI_EFFORT_ALLOWED` | medium | effort words the template sees; others become medium |
| `BONSAI_PORT`, `BONSAI_MODEL` | 8080, auto | |

### Getting more positions into VRAM

Every GB of VRAM the desktop does not use is ~30k more q8_0 positions at full speed. Run the display from the
CPU's integrated graphics (monitor on the motherboard output, iGPU enabled in the BIOS) and set GPU-accelerated
apps (browser, Discord, remote-desktop host) to the iGPU in Windows **Settings > System > Display > Graphics**.
Measured on this 4070: desktop VRAM 930 -> 285 MiB, the safe margin 1300 -> 1000 MiB, VRAM line 95k -> 113k
positions, decode at 112k from PCIe-bound to 70 tok/s. (Estimated beforehand: ~1 GB and ~30k positions. Windows
keeps ~220-275 MiB of compositor surfaces on the discrete card regardless, so the real gain was ~17k.)

### Other cards

| Card | Recipe | Notes |
| --- | --- | --- |
| 12 GB | defaults | this README |
| 16 GB and up | defaults | the whole q8_0 window fits: the tier switches itself off |
| 8 GB (2060 Super, 3060 Ti, 4060) | defaults, or `BONSAI_CTX=65536` | tiered KV keeps q8_0; expect speed in the ratio of your bandwidth to 504 GB/s. Untested here |

Past the VRAM line decode is bound by PCIe (4.0 x16 here, ~23 GB/s). PCIe 3.0 or x8 slots halve those rows.

## Quality: the recipe matters as much as the kernels

The complaint about Bonsai 2 is code and agentic work, and most of that gap is runtime, not compression.
Details and every measurement: [`docs/QUALITY.md`](docs/QUALITY.md).

- **KV precision.** q4_0 KV flips the top token on 1 in 48 positions at depth, q8_0 on 1 in 160 (KL 0.00218 vs
  0.00017 against f16 KV). Every published 12 GB recipe used q4_0 to fit the window; this one keeps q8_0 across
  all of it.
- **Reasoning effort.** The GGUF template defaults to `xhigh` (an extra "think carefully" line: runaway thinking,
  empty answers). `low` behaves close to `xhigh`. `medium` is the model's natural thinking and beats both, and
  thinking off, at every output cap from 2k up (Killy's HumanEval grid: 160-161 of 164). Default: `medium` with a
  20k thinking budget and a force-close message so a trip still yields the answer.
- **Harness-proofing.** Cline, Kilo and Open WebUI send `effort: "high"`, which the template rejects: HTTP 500,
  0 of 164. Apps with 256-4096 token caps end a thinking model mid-thought (17-137 of 164). The server maps
  unknown effort words to medium and raises small caps to the thinking budget. Replays of Killy's rows against
  this server: [Killy's plates, replayed](docs/Q8_FULL_CONTEXT.md#killys-plates-replayed): `effort: "high"` 0 -> **160** of 164 (the same server with harness-proofing off: HTTP 500, 0), a 4096-token cap 137 -> **157**, medium **161**.
- **Tool calls.** The native format is Qwen3-Coder XML with raw string parameters, grammar-constrained by the
  server: 9 of 9 parsed vs 1 of 9 for JSON-in-content. For file-writing agents, thinking off parsed 8 of 9 vs 6
  of 9 at medium (which spent 10-17k tokens thinking first): send `enable_thinking: false` per request.

### For agents and apps

- Send `tools` and let the server format and parse calls; do not prompt for JSON tool calls in content.
- Tool-heavy agents: `chat_template_kwargs: {"enable_thinking": false}` per request. Chat and coding answers:
  leave the server default (medium).
- Clients that cap `max_tokens` low are fine: with thinking on the server raises the cap (disable with
  `BONSAI_HARNESS_PROOF=0`).

## The patch stack

Everything is submitted upstream to PrismML; this repo ships the combined stack now: 33 commits on
`prism@adfffbe`, as `git am`-able patches in [`patches/`](patches/), as the branch
[`bonsai-q8-product`](https://github.com/professorpalmer/llama.cpp-ada-ternary/tree/bonsai-q8-product), and as
Windows binaries on [Releases](../../releases). Merged upstream already: #214 (branch-free PTQ1_0 MMQ tile loader,
2x prefill) and #216 (4-column GDN warp layout); the MTP Hadamard-embedding fix of sudoingX's #217 landed through
#205. Open: #215, #218, #220, #221, #285.

| Patches | What | Upstream |
| --- | --- | --- |
| 0001-0005 | planar-transposed q8 activations, 2-8 column PTQ1_0 mat-vec, `GGML_CUDA_BATCH_INVARIANT`, bf16 small-row mat-vec | sudoingX #218 |
| 0006 | recurrent-state gather folded into the GatedDeltaNet kernel | #220 |
| 0007-0008 | SoA q8 activations with exact integer sums, small-K GEMV, hybrid single/multi-column dispatch | #215, #221 |
| 0009 | flash attention reads q4_0/q8_0 K/V in place (no F16 scratch copy) | #221 |
| 0010 | multi-column PTQ1_0 mat-vec: raw digits, exact activation sums, per-pair epilogue | #221 |
| 0011-0016 | MTP graph and catch-up fixes, Hadamard self-quantization, out-of-vocab guard, pool teardown order | #221 |
| 0017-0027 | `--spec-draft-depth-max`, sm_120 build fix, #221 review round (PDL wait, BATCH_INVARIANT epilogue, ...) | #221 |
| 0028 | tiered KV cache (`--kv-vram-cells`) with copy-engine staging of the host tail | [#285](https://github.com/PrismML-Eng/llama.cpp/pull/285) |
| 0029 | quantized-KV GQA decode on the in-place MMA attention kernel | #285 |
| 0030 | `BATCH_INVARIANT`: occupancy-independent attention split, PTQ1_0 mat-vec up to 8 columns | #285 |
| 0031 | `--spec-draft-window`, `--spec-draft-n-max-tail` | #285 |
| 0032 | `--reasoning-effort-allow/-fallback`, `--reasoning-max-tokens-floor` | #285 |
| 0033 | `GGML_CUDA_OP_TIMING` per-node GPU time (diagnostics) | #285 |

How each cut was found (CUPTI traces, L1 wavefront counts, what did not work):
[`surgery/ADA4070_PTQ1.md`](surgery/ADA4070_PTQ1.md) and [`docs/Q8_FULL_CONTEXT.md`](docs/Q8_FULL_CONTEXT.md).

## Build from source

Windows without the CUDA toolkit (VS 2022 Build Tools C++ workload + NVIDIA's pip wheels):

```powershell
python -m pip install cmake ninja nvidia-cuda-nvcc nvidia-cuda-runtime nvidia-cublas nvidia-cuda-nvrtc
git clone -b bonsai-q8-product https://github.com/professorpalmer/llama.cpp-ada-ternary vendor\prism-llama
.\build\build_windows.ps1                    # arch from nvidia-smi; -Arch "75;86;89;89-virtual" for a release build
```

Linux, or from PrismML's tree directly:

```bash
git clone https://github.com/PrismML-Eng/llama.cpp && cd llama.cpp && git checkout adfffbe
git am ../bonsai-ada-surgery/patches/*.patch
cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="86;89" && cmake --build build --target llama-server -j
```

## Measure it yourself

```powershell
bench\killy_suite.ps1                          # HumanEval replays of Killy's plates + the voxel pagoda (~5 h)
python bench\receipt.py <tag>                  # decode by depth, prefill, TTFT, power, VRAM by window
python bench\quick_tps.py --key-file artifacts\api_key.txt --depth 32000   # served decode at depth
bench\kv_kl_sweep.ps1                          # KV precision KL table (needs wikitext-2)
bench\kv_mean_center_kl.ps1                    # K mean-centering on top of the Hadamard KV rotation (no gain)
python bench\toolcall_stress.py                # tool-call syntax, XML+grammar vs JSON-in-content
python bench\humaneval_run.py --arm medium     # HumanEval 164, tests executed
python bench\mtp_identity.py                   # greedy draft-on vs draft-off
```

## Layout

| Path | What |
| --- | --- |
| `patches/` | the 33-commit stack on PrismML `adfffbe`, `git am`-able |
| `start-server.ps1`, `start-remote.ps1` | the recipe (LAN / Cloudflare tunnel) |
| `build/` | toolkit-free Windows CUDA build, MTP head grafts |
| `docs/Q8_FULL_CONTEXT.md` | q8_0 at 262k on 12 GB: mechanisms, receipts, identity matrix, rejected ideas |
| `docs/QUALITY.md` | KV precision, reasoning effort, tool-call syntax, harness-proofing |
| `docs/RECEIPTS.md` | speed receipts, this card and others |
| `bench/` | receipts, KL sweeps, tool-call stress, HumanEval runner and Killy replays |
| `surgery/` | the kernel investigation: write-up, CUPTI injection profiler, clock sweeps, dead ends |

## Credits

PrismML for the model and the fork. sudoingX for the planar-transposed layout, the batch-invariant mode, the
Hadamard-inverse fix and the MTP graft tools. ProCreations for the on-policy MTP head (Apache 2.0; independent
of PrismML). Killy (@net_termina) for the failure census and the HumanEval plates that turned "quality is worse"
into fixable buckets. MIT for everything here; weights are PrismML's (Apache 2.0). Not affiliated with PrismML.
