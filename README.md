# Bonsai 2 27B: 262k context, 97~105 tok/s on a 12 GB card

The model's **full 262,144-token trained window** on consumer NVIDIA, plus the speed and
serving recipe that make that window usable. Patched [PrismML llama.cpp](https://github.com/PrismML-Eng/llama.cpp)
for Bonsai 2 27B (1.58-bit ternary `PTQ1_0`, 5.9 GB). Measured on an RTX 4070 12 GB; the kernels
target the same small-K ternary GEMV geometry on any Turing, Ampere, Ada or Blackwell part.

**262,144 tokens is the max this model was trained for.** Most 12 GB write-ups never say the
window. This bundle serves it: **96k with q8_0 KV** as the 12 GB quality default (10.8 GB, no
paging), **262k with q4_0 KV** on the same 12 GB card, **262k with q8_0 KV** on 16 GB and up.

| | |
| --- | --- |
| **Context** | **262,144 trained max** · 96k / q8_0 default on 12 GB · 262k / q4_0 on 12 GB · 262k / q8_0 on 16 GB |
| **Decode** | **96.8 tok/s** served fresh (100.7 thinking budget off) vs 54.0 stock |
| **Prefill** | **1304 tok/s** `llama-bench` / **1012 tok/s** served 32k vs 632 / 578 |
| **KV quality** | **q8_0** default: 12x lower KL than the community q4_0 12 GB sheet |
| **Tools** | native XML grammar **9/9** parsed vs 1/9 JSON-in-content |

**Same weights, same 1.75 bits per weight.** Nothing is re-quantized. Every kernel is checked
against the CPU reference (`test-backend-ops`, all PTQ1_0 shapes), greedy output is byte-identical
with each optimization on and off, and the speculative draft is byte-identical to plain decoding.

| RTX 4070 12 GB, original `Ternary-Bonsai-2-27B-PTQ1_0.gguf`, stock clocks | PrismML build | this bundle |
| --- | ---: | ---: |
| **context window** | not stated; community 12 GB sheets use q4_0 to squeeze 262k | **262,144 trained max**, served: **96k / q8_0** default, **262k / q4_0** on 12 GB |
| decode, `llama-bench` tg128 (kernels only, no draft) | 54.3 tok/s | 67.6 tok/s |
| decode, served, fresh context, code / prose / bash mean | 54.0 tok/s | **96.8 tok/s** (100.7 with the thinking budget off) |
| decode, served, at 32k tokens of context | 40.7 tok/s | 47.6 tok/s |
| decode, served, at 64k tokens of context | 31.9 tok/s | 36.9 tok/s |
| prefill, `llama-bench` pp2048 | 632 tok/s | 1304 tok/s |
| prefill, served, 32k prompt (time to first token) | 578 tok/s (55 s) | 1012 tok/s (32 s) |
| VRAM in use, served recipe | 11.3 GB at 128k | 10.8 GB at 96k / q8_0, with the draft context |
| KV cache in the 12 GB quality recipe | q4_0 (community sheet) | **q8_0**: 12x lower KL, see below |

Served numbers are the server's own `timings`, 400-token answers, `bench/quick_tps.py`; the
32k/64k rows put that much varied filler in front of the prompt. The draft head is worth +80% on
a fresh context and nothing at depth, where a step is bound by reading the cache, so the bundle
stops drafting past 24k tokens (`--spec-draft-depth-max`, added here) and runs on the kernels
alone from there. Full method and every run: [`docs/RECEIPTS.md`](docs/RECEIPTS.md);
`bench/served_depth.ps1` prints the served rows for your card.

## Why a bundle and not "wait for the PRs"

Everything in here is submitted upstream ([#214](https://github.com/PrismML-Eng/llama.cpp/pull/214),
[#215](https://github.com/PrismML-Eng/llama.cpp/pull/215), [#216](https://github.com/PrismML-Eng/llama.cpp/pull/216),
[#220](https://github.com/PrismML-Eng/llama.cpp/pull/220), [#221](https://github.com/PrismML-Eng/llama.cpp/pull/221),
and sudoingX's [#217](https://github.com/PrismML-Eng/llama.cpp/pull/217) / [#218](https://github.com/PrismML-Eng/llama.cpp/pull/218)).
Review takes the time it takes. This repo ships the combined stack now: 21 commits on PrismML
`prism@9a9394a`, as `git am`-able patches in [`patches/`](patches/), as a branch
([`bonsai-combo`](https://github.com/professorpalmer/llama.cpp-ada-ternary/tree/bonsai-combo)),
and as Windows binaries on the [Releases](../../releases) page.

| Commits | What | From |
| --- | --- | --- |
| 0001-0002 | planar-transposed q8 activations, dedicated 2-8 column PTQ1_0 mat-vec (speculative verify batches) | sudoingX #218 |
| 0004-0006 | `GGML_CUDA_BATCH_INVARIANT`, bf16 small-row mat-vec, Hadamard inverse on token embeddings in the MTP graph | sudoingX #217/#218 |
| 0007 | recurrent-state gather folded into the GatedDeltaNet kernel | ours #220 |
| 0008-0009 | branch-free PTQ1_0 MMQ tile loader + full Ampere tile table (2x prefill), 4-column GDN warp layout on all Ampere+ | ours #214, #216 |
| 0010-0011 | SoA q8 activations with exact integer sums, warp-per-row small-K GEMV, hybrid single/multi-column dispatch | ours #215, #221 |
| 0012 | flash attention MMA reads q4_0/q8_0 K/V in place (no F16 scratch copy) | ours #221 |
| 0013 | multi-column PTQ1_0 mat-vec: raw digits, exact activation sums, per-pair epilogue (+13-24% on verify batches) | ours #221 |
| 0014-0015 | MTP graph publishes only the output rows; draft-mtp decodes catch-up rows with the first draft row | ours #221 |
| 0016 | the Hadamard transform quantizes its own output when every consumer is a PTQ1_0 mat-vec (~390 fewer launches per step) | ours #221 |
| 0017 | out-of-vocab ids from the backend sampler / draft are rejected, not fed to the tokenizer | ours #221 |
| 0018-0019 | draft-mtp discards stale catch-up rows when a new task lands on the slot; FWHT-q8 pool blocks released LIFO before the pools (llama-bench teardown assert) | ours, new |
| 0020 | `--spec-draft-depth-max`: stop drafting once the sequence is deep, where speculation costs more than it saves | ours, new |
| 0021 | `GGML_CUDA_RESTRICT` off the PTQ1_0 kernel signature (sm_120 C2912); Ampere 1-col uses the #218 PT kernel | ours, on #221 |

The write-up of how each cut was found (CUPTI traces, L1 wavefront counts, what did not work):
[`surgery/ADA4070_PTQ1.md`](surgery/ADA4070_PTQ1.md).

## 262k context (the trained maximum)

Bonsai 2 / Qwen3.8-27B is trained to **262,144 tokens**. That is the number. The bundle exposes it
instead of silently serving an 8k–32k slice.

| Card | Window | KV | Draft | VRAM in use (measured, 4070) |
| --- | ---: | --- | --- | --- |
| 12 GB, **default** | **98,304** | q8_0 | on, to 24k | **10.8 GB**, no paging at any depth |
| 12 GB, longer | 131,072 | q4_0 | on | 9.9 GB |
| 12 GB, **full trained max** | **262,144** | q4_0 | off | ~12 GB (draft context would page; `BONSAI_SPEC=0`) |
| 16 GB and up | **262,144** | q8_0 | on | q8_0 at the full window |

```powershell
.\start-server.ps1
# full 262k on 12 GB:
$env:BONSAI_CTX=262144; $env:BONSAI_CTK='q4_0'; $env:BONSAI_SPEC=0; .\start-server.ps1
# full 262k, q8_0 (16 GB+):
$env:BONSAI_CTX=262144; .\start-server.ps1
```

q4_0 is how 12 GB holds 262k; it flips the top token 3.5x more often than q8_0 (see quality).
16 GB cards should take the max window at q8_0 and stop thinking about it.

## Quality: the recipe matters as much as the kernels

The complaint about Bonsai 2 is code and agentic work, and most of that gap is runtime, not
compression. Measured on this card, on the original PrismML file, documented in
[`docs/QUALITY.md`](docs/QUALITY.md):

- **q4_0 KV cache flips the top token on 1 in 48 positions at depth; q8_0 on 1 in 160** (KL
  0.00218 vs 0.00017 against f16 KV). Every published 12 GB recipe uses q4_0 *so the 262k
  window fits*, and then never says the window. The default here is **96k with q8_0 K/V**
  (10.8 GB; 128k/q8_0 allocates but Windows pages the cache and decode at depth drops by a
  third). **262k / q4_0** on 12 GB and **262k / q8_0** on 16 GB are one variable away.
- **Runaway thinking**: the GGUF template defaults to `xhigh` (an extra "think carefully..."
  system line). That is Killy's "reasoning madness": no stop, empty SVG/code, Terminal-Bench
  budgets blown. `medium` is thinking with **no** extra instruction and is the setting that
  closed his MBPP/HumanEval gap to the 27B teacher — *if* the output cap is ≥ 20k. A 10k cap
  makes medium *worse* than thinking off. The recipe is therefore **`medium` + 20,480 think
  tokens** for chat, with a force-close message so a trip still yields the answer, and
  **`BONSAI_THINK=0`** for agent harnesses (9/9 parseable tool calls; thinking-on spent the
  whole budget first).
- **Tool-call syntax**: the model's native format is Qwen3-Coder XML with raw string parameters,
  and this server grammar-constrains it. **9 of 9 calls parsed** through it, against **1 of 9**
  when the model is asked to write Hermes-style JSON in content (the failure Killy measured:
  one bracket short at the end of a 20k-character payload). Costs ~14% decode on requests that
  carry tools.

## Quick start (Windows, NVIDIA)

1. Download `bonsai-bundle-win-x64.zip` from [Releases](../../releases) and unzip into this repo
   (it fills `bin\`), or build it yourself (below). Binaries carry sm_75 / 86 / 89 machine code
   (RTX 20 / 30 / 40) plus compute_89 PTX that RTX 50 cards compile at first load, built with
   CUDA 13; they need only the NVIDIA driver.
2. Put `Ternary-Bonsai-2-27B-PTQ1_0.gguf` from [prism-ml on Hugging Face](https://huggingface.co/prism-ml)
   in `models\`.
3. Optional, recommended (+MTP speculative decoding, lossless): build the draft-head file.

   ```powershell
   git clone -b bonsai-combo https://github.com/professorpalmer/llama.cpp-ada-ternary vendor\prism-llama
   .\build\make_mtp_lean.ps1     # ~1 GB download, writes models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf
   ```

   This grafts the Qwen 3.8 27B next-token head onto the ternary file with
   [sudoingX's graft tools](https://github.com/sudoingX/bonsai2-small-gpu) (his idea and code;
   this script only wires them up and fetches the 15 head tensors sparsely instead of the 16 GB
   donor). The script proves the graft by stripping the head again and hashing the result against
   the original.
4. Serve:

   ```powershell
   .\start-server.ps1
   ```

   OpenAI-compatible API on `http://<host>:8080/v1`, bearer key in `artifacts\api_key.txt`, LAN
   exposed. `start-remote.ps1` adds a Cloudflare tunnel for use from another machine.

Knobs (environment variables) and defaults: `BONSAI_CTX` 98304, `BONSAI_CTK` q8_0, `BONSAI_SPEC`
2 (draft n-max, 0 off), `BONSAI_SPEC_DEPTH` 24576 (stop drafting past this depth), `BONSAI_THINK`
1 (0 = thinking off for every request — use this in front of Cursor/Cline/aider), `BONSAI_EFFORT`
medium (template default is xhigh; do not leave it unset), `BONSAI_THINK_BUDGET` 20480 (-1
unlimited; also re-enables GPU-side sampling, +4% decode), `BONSAI_PORT` 8080, `BONSAI_MODEL`.

| Card | Recipe | Notes |
| --- | --- | --- |
| 12 GB, default | 96k, q8_0, draft on | 10.8 GB in use, every number above |
| 12 GB, longer window | `BONSAI_CTX=131072 BONSAI_CTK=q4_0` | 9.9 GB; q4_0 noise (see quality) |
| 12 GB, full 262k | `BONSAI_CTX=262144 BONSAI_CTK=q4_0 BONSAI_SPEC=0` | the draft context pushes 262k over the paging line, so no draft |
| 16 GB and up | `BONSAI_CTX=262144` | q8_0 at the full window |
| 8 GB (2060 Super, 3060 Ti, 4060) | `BONSAI_CTX=32768` (q8_0, ~1.2 GB KV) or `65536 BONSAI_CTK=q4_0` | untested here; expect the ratio of your bandwidth to 504 GB/s |

For agent harnesses (Cursor, Cline, OpenCode, aider): `BONSAI_THINK=0`, and let the harness send
`tools`; do not have it prompt for JSON tool calls in content. Please run the receipt on other
cards and post the numbers.

### Build from source

Windows without the CUDA toolkit (VS 2022 Build Tools C++ workload + NVIDIA's pip wheels):

```powershell
python -m pip install cmake ninja nvidia-cuda-nvcc nvidia-cuda-runtime nvidia-cublas nvidia-cuda-nvrtc
git clone -b bonsai-combo https://github.com/professorpalmer/llama.cpp-ada-ternary vendor\prism-llama
.\build\build_windows.ps1                    # arch from nvidia-smi; -Arch "75;86;89;89-virtual" for a release build
```

Linux, or from PrismML's tree directly:

```bash
git clone https://github.com/PrismML-Eng/llama.cpp && cd llama.cpp && git checkout 9a9394a
git am ../bonsai-ada-surgery/patches/*.patch
cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="86;89" && cmake --build build --target llama-server -j
```

## Measure it yourself

```powershell
python bench\receipt.py <tag>                 # decode by depth, prefill, TTFT, power, VRAM by window (~10 min)
bench\served_depth.ps1 -Bin bin -Model models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf -Spec 2 -SpecDepthMax 24576 -Tag mine
python bench\quick_tps.py --key-file artifacts\api_key.txt --depth 32000   # served decode at depth, running server
bench\kv_kl_sweep.ps1                         # KV precision KL table (needs wikitext-2 test set)
python bench\toolcall_stress.py               # tool-call syntax, XML+grammar vs JSON-in-content
python bench\reason_ab.py --key-file artifacts\api_key.txt   # think-off / low / medium / xhigh, SVG + code
python bench\head_to_head.py --model models\Ternary-Bonsai-2-27B-PTQ1_0.gguf --arm prism=<stock bin> --arm bundle=bin
```

## Layout

| Path | What |
| --- | --- |
| `patches/` | the 21-commit stack on PrismML `9a9394a`, `git am`-able |
| `start-server.ps1`, `start-remote.ps1` | the recipe (LAN / Cloudflare tunnel) |
| `build/build_windows.ps1` | toolkit-free Windows CUDA build |
| `build/make_mtp_lean.ps1` | MTP head graft (sudoingX's tools, sparse donor fetch) |
| `docs/QUALITY.md` | KV precision, thinking budget, tool-call syntax: measurements and recipe |
| `docs/RECEIPTS.md` | speed receipts, this card and others |
| `bench/` | receipt, served depth ladder, KL sweep, tool-call stress, head-to-head, served TPS |
| `surgery/` | the investigation: write-up, CUPTI injection profiler, clock sweeps, dead ends |

## Credits

PrismML for the model and the fork. sudoingX for the planar-transposed layout, the batch-invariant
mode, the Hadamard-inverse fix and the MTP graft. Killy (@net_termina) for the failure census that
turned "quality is worse" into three fixable buckets. MIT for everything here; weights are
PrismML's (Apache 2.0). Not affiliated with PrismML.
