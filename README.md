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
Review takes the time it takes. This repo ships the combined stack now: 23 patches on PrismML
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
| 0022 | define the host layout helper after the CUDA device declarations; fixes clean-build undefined identifiers | ours, `32842f6` |
| 0023 | Wait for the PDL activation dependency in the planar PTQ1_0 mat-vec on Hopper/Blackwell | ours, from LamplighterPaul's #218 finding |

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

## Quick start (Linux, NVIDIA)

This repository is the patch and serving bundle. It now includes a Linux build
script that fetches the pinned PrismML source and applies **all 23 bundled patches**,
including the `common.cuh` header fix and the Hopper/Blackwell PDL dependency wait. No manual patch application or Git author
configuration is needed. There is no prebuilt Linux binary yet.

Prerequisites: NVIDIA driver, CUDA toolkit (`nvcc` on PATH), Git, CMake >=3.24,
and a C++ compiler supported by your CUDA toolkit. On Ubuntu/Debian, the ordinary
build dependencies are:

```bash
sudo apt-get update
sudo apt-get install -y git cmake build-essential libcurl4-openssl-dev libssl-dev
```

Install the NVIDIA CUDA toolkit separately if `nvcc --version` is unavailable.
CUDA 13.x is not the cause of the undefined `ggml_cuda_info` error below.

```bash
git clone https://github.com/professorpalmer/bonsai-ada-surgery.git
cd bonsai-ada-surgery
bash build/build_linux.sh
bash start-linux.sh /absolute/path/to/Ternary-Bonsai-2-27B-PTQ1_0.gguf
```

Use the official original `Ternary-Bonsai-2-27B-PTQ1_0.gguf` from
[the official model download](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/blob/main/Ternary-Bonsai-2-27B-PTQ1_0.gguf); the model download is
separate. If you already have it, pass its existing path. The scripts do not
install system packages, download weights, or change your existing
`vendor/prism-llama` checkout.

Open **http://127.0.0.1:8080** on the same machine. The API is at
`http://127.0.0.1:8080/v1`. Ctrl-C stops it. This first-run configuration uses
8k context, full GPU offload, flash attention, and no speculative draft. It is
not the 96k plus MTP recipe behind the headline serving numbers.

Set `BONSAI_CTX` and `BONSAI_PORT` to change the launch defaults. The build uses
four jobs by default; lower `BONSAI_BUILD_JOBS` on low-memory hosts. CMake detects
the GPU by default. For a headless build without an attached GPU, pass its target
architecture, e.g. `BONSAI_CUDA_ARCH=89 bash build/build_linux.sh` for Ada.

The build uses a separate source directory keyed by the base commit and patch
contents. Repeating the command reuses its build; changed patches get a new source
directory. It refuses to overwrite tracked edits in an existing generated source
tree. After pulling updates to this bundle, rerun the build script.

The [Linux CUDA build workflow](.github/workflows/linux-cuda.yml) compiles the
patch stack with CUDA 13 for Ada without a GPU. A successful compile does not
establish GPU inference correctness or Linux benchmark results.

### Direct fork build (alternative)

The buildable llama.cpp fork is
[llama.cpp-ada-ternary, branch `bonsai-combo`](https://github.com/professorpalmer/llama.cpp-ada-ternary/tree/bonsai-combo).
This follows that branch rather than the bundle's pinned patch series:

```bash
git clone --branch bonsai-combo https://github.com/professorpalmer/llama.cpp-ada-ternary
cd llama.cpp-ada-ternary
cmake -S . -B build-linux -DGGML_CUDA=ON \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=native
cmake --build build-linux --target llama-server -j4
./build-linux/bin/llama-server \
  -m /absolute/path/to/Ternary-Bonsai-2-27B-PTQ1_0.gguf \
  -ngl 99 -fa on -c 8192 --spec-type none \
  --jinja --host 127.0.0.1 --port 8080
```

### Updating an existing source checkout

Run these inside the **llama.cpp fork**, such as `vendor/prism-llama`, rather than
in the outer `bonsai-ada-surgery` directory:

```bash
git switch bonsai-combo
git pull --ff-only
```

Then rerun the configure and build commands above. Preserve any local changes;
if Git cannot fast-forward, use a separate fresh clone instead of resetting it.

The `common.cuh` errors saying `ggml_cuda_info` and `ggml_cuda_get_device` are
undefined come from a declaration-order bug fixed in
[`32842f6`](https://github.com/professorpalmer/llama.cpp-ada-ternary/commit/32842f6cf208187d1624da5d968e410e117772d8).
Patch `0022` carries that same fix for patch-series users. Downgrading CUDA does
not address this source-order error. Updating only the outer bundle does not
update an already cloned `vendor/prism-llama` checkout.

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
   .\build\make_mtp_procreations.ps1   # default: ProCreations on-policy Q8 head on PTQ1_0
   # fallback teacher graft: .\build\make_mtp_lean.ps1
   ```

   `make_mtp_procreations.ps1` sparse-fetches the 15 `blk.64` tensors from
   [ProCreations/Ternary-Bonsai-2-27B-MTP](https://huggingface.co/ProCreations/Ternary-Bonsai-2-27B-MTP)
   (their PQ2 combined file is not used) and grafts that on-policy head onto official PTQ1_0.
   `make_mtp_lean.ps1` is the older Qwen 3.8 teacher-head graft. Both use
   [sudoingX's graft tools](https://github.com/sudoingX/bonsai2-small-gpu) and prove the trunk
   bytes by stripping the head and hashing against the original. On the 4070 the trained head
   accepted 70.6% of drafts vs 66.3% for the teacher graft (+3.9% tok/s on the paired probe).
   Do not load their combined PQ2 GGUF; that drops the PTQ1_0 Ada kernels.
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

### Alternative: apply the bundled patches to PrismML source

Use a fresh checkout at the exact base below. Do not apply this series on top of
`bonsai-combo`, which already includes the changes. From this bundle's root:

```bash
BONSAI_PATCH_DIR="$PWD/patches"
git clone https://github.com/PrismML-Eng/llama.cpp vendor/prism-patched
cd vendor/prism-patched
git checkout 9a9394a
git am "$BONSAI_PATCH_DIR"/*.patch
cmake -S . -B build-linux -DGGML_CUDA=ON \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=native
cmake --build build-linux --target llama-server -j4
```

`git am` requires your Git author name and email to be configured. The patch
series must include `0022`; a checkout ending at `0021` lacks the header fix.

## Measure it yourself

```powershell
python bench\receipt.py <tag>                 # decode by depth, prefill, TTFT, power, VRAM by window (~10 min)
bench\served_depth.ps1 -Bin bin -Model models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf -Spec 2 -SpecDepthMax 24576 -Tag mine
python bench\quick_tps.py --key-file artifacts\api_key.txt --depth 32000   # served decode at depth, running server
bench\kv_kl_sweep.ps1                         # KV precision KL table (needs wikitext-2 test set)
python bench\toolcall_stress.py               # tool-call syntax, XML+grammar vs JSON-in-content
python bench\reason_ab.py --key-file artifacts\api_key.txt   # think-off / low / medium / xhigh, SVG + code
python bench\mtp_head_ab.py                  # teacher graft vs ProCreations head
python bench\mtp_identity.py                 # greedy draft-on vs draft-off
python bench\head_to_head.py --model models\Ternary-Bonsai-2-27B-PTQ1_0.gguf --arm prism=<stock bin> --arm bundle=bin
```

## Layout

| Path | What |
| --- | --- |
| `patches/` | the 23-patch stack on PrismML `9a9394a`, `git am`-able |
| `start-server.ps1`, `start-remote.ps1` | the recipe (LAN / Cloudflare tunnel) |
| `build/build_windows.ps1` | toolkit-free Windows CUDA build |
| `build/make_mtp_procreations.ps1` | default MTP graft: ProCreations on-policy Q8 head on PTQ1_0 |
| `build/make_mtp_lean.ps1` | fallback MTP graft: Qwen 3.8 teacher head |
| `docs/QUALITY.md` | KV precision, thinking budget, tool-call syntax: measurements and recipe |
| `docs/RECEIPTS.md` | speed receipts, this card and others |
| `bench/` | receipt, served depth ladder, KL sweep, tool-call stress, head-to-head, served TPS |
| `surgery/` | the investigation: write-up, CUPTI injection profiler, clock sweeps, dead ends |

## Credits

PrismML for the model and the fork. sudoingX for the planar-transposed layout, the batch-invariant
mode, the Hadamard-inverse fix and the MTP graft tools. ProCreations for the on-policy MTP head
(Apache 2.0; independent of PrismML). Killy (@net_termina) for the failure census that
turned "quality is worse" into three fixable buckets. MIT for everything here; weights are
PrismML's (Apache 2.0). Not affiliated with PrismML.

### Hopper/Blackwell PDL fix

Patch `0023` carries `09b6cce` from the combo branch. The planar PTQ1_0
mat-vec now calls `ggml_cuda_pdl_sync()` before reading activations produced
by the q8_1 quantization kernel. Without that wait, programmatic dependent
launch can let the consumer read unfinished output on Hopper/Blackwell.
LamplighterPaul reported corrupt `llama-server` output on an RTX 5080,
including the `GGML_CUDA_PDL=0` isolation, in
[Prism #218](https://github.com/PrismML-Eng/llama.cpp/pull/218#issuecomment-5833071266).
This is a synchronization bug, separate from KV-cache quantization quality.
The helper is a no-op on Ampere/Ada. After updating this bundle, rerun the
build script to include the fix. Existing downloaded Windows binaries are
not updated by pulling patches; rebuild or use a binary explicitly containing
this commit. The reporter's hardware result is not a new hardware test of
this bundle.
