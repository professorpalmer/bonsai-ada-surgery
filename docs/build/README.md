# Install, build and run

| You have | Do this | Section |
| --- | --- | --- |
| Windows, an NVIDIA card (RTX 20/30/40/50) | download the release zip, add the model, run `start-server.ps1` | [Quick start (Windows)](#quick-start-windows-nvidia) |
| Hugging Face | the same bundle plus the ready-made MTP-grafted GGUF (`hf download`, no graft step) | [CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF](https://huggingface.co/CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF) |
| Linux, NVIDIA driver + CUDA toolkit | `bash build/build_linux.sh` builds the pinned PrismML source with every patch in `patches/` | [Quick start (Linux)](#quick-start-linux-nvidia) |
| your own llama.cpp workflow | build the fork branch `bonsai-q8-product`, or `git am` the series in `patches/` onto PrismML `adfffbe` | [The patch stack](PATCHES.md) |
| an older bundle of this repo | `git pull`, unzip the latest zip over it, run `layer\fetch_runtime.ps1` once | [Upgrading](UPGRADING.md) |

Other pages in this directory:

- [Launcher settings](KNOBS.md): every `BONSAI_*` environment variable and its default.
- [Vision (images)](VISION.md): load the vision projector.
- [The patch stack](PATCHES.md): each patch, what it does and where it went upstream.
- [Upgrading](UPGRADING.md): what each bundle changed, newest first.

The serving flags behind the numbers are listed under [Quick start (Linux)](#quick-start-linux-nvidia) as one
`llama-server` command line. Any build of the patched engine can use them.

## Quick start (Windows, NVIDIA)

1. Download `bonsai-bundle-win-x64.zip` from [Releases](https://github.com/professorpalmer/bonsai-ada-surgery/releases)
   and unzip it into this repo (it fills `bin\`), or build it (below). Binaries carry sm_75 / 86 / 89 machine code
   (RTX 20 / 30 / 40) plus compute_89 PTX that RTX 50 cards compile at first load; they need only the NVIDIA driver.
2. Put `Ternary-Bonsai-2-27B-PTQ1_0.gguf` from [prism-ml on Hugging Face](https://huggingface.co/prism-ml) in
   `models\`.
3. Recommended: the MTP draft-head file (speculative decoding, +50-100% decode; every token is the target model's
   greedy choice, at rounding level not bit-identical to decoding without it, see
   [Q8_FULL_CONTEXT.md](../12gb/Q8_FULL_CONTEXT.md#identity-greedy-256-token-code-and-prose-continuations-fresh-prefill-each)).
   Ready-made on Hugging Face (`hf download CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf --local-dir models`;
   all 851 original tensors byte-identical to PrismML's file, `bench\gguf_tensor_identity.py`), or build it yourself:

   ```powershell
   git clone -b bonsai-q8-product https://github.com/professorpalmer/llama.cpp-ada-ternary vendor\prism-llama
   .\build\make_mtp_procreations.ps1   # ProCreations on-policy Q8 head grafted onto PTQ1_0
   ```

   It sparse-fetches the `blk.64` tensors from
   [ProCreations/Ternary-Bonsai-2-27B-MTP](https://huggingface.co/ProCreations/Ternary-Bonsai-2-27B-MTP), grafts
   them with [sudoingX's tools](https://github.com/sudoingX/bonsai2-small-gpu) and proves the trunk bytes by
   hashing against the original. `make_mtp_lean.ps1` is the older teacher-head graft (-4.3 pp acceptance).
   On an 8 GB card, also run `.\build\make_mtp_q4head.ps1` once (the Q4_0 head, see [8 GB](../8gb/README.md)).
4. Serve:

   ```powershell
   .\start-server.ps1
   ```

   OpenAI-compatible API on `http://<host>:8080/v1`, bearer key in `artifacts\api_key.txt` (created on first
   run), LAN exposed. `start-remote.ps1` adds a Cloudflare tunnel.

`start-server.ps1` sizes everything at launch. It reads free VRAM, keeps a safety margin below the point where
Windows demotes a background process's memory, and puts as many positions in VRAM as fit. It detects the card:

| Card | Window | K/V cache | Page |
| --- | --- | --- | --- |
| 8 GB (total VRAM up to 8.5 GB, or `BONSAI_8GB=1`) | 262,144 with 24 GB of system RAM or more and the MTP head file; else 131,072 | q3_0 | [8 GB](../8gb/README.md) |
| more than 8.5 GB, up to 14 GB | 262,144 | q4_0 (`BONSAI_CTK=q8_0` for the previous recipe) | [12 GB](../12gb/README.md) |
| more than 14 GB | 262,144 | q8_0 | [12 GB](../12gb/README.md#other-cards) |

Binaries from before the tiered-KV runtime are detected and get the previous 96k all-VRAM recipe.

### Keep the card to yourself

An app that keeps working on the GPU slows the server even when it uses no VRAM: Windows time-slices the card
between them, and MTP drafting (many short kernels per token) loses the most. Found by
[@Milor123](https://github.com/professorpalmer/bonsai-ada-surgery/issues/4): with KDE Connect running on the RTX 4070,
drafting gave 56 tok/s at 16k instead of 83; set to the iGPU, 83. The launcher samples GPU activity before it starts
the server and prints a `warn` line with the apps on the card when the GPU is already busy. Close the app or set it
to the integrated GPU in **Settings > System > Display > Graphics**.

A program that takes VRAM after the server starts makes the server much slower. The launcher prints a `spill` line
when this occurs (`BONSAI_SPILL_GUARD`, see [Launcher settings](KNOBS.md)).

## Quick start (Linux, NVIDIA)

`build/build_linux.sh` fetches the pinned PrismML source (`adfffbe`) and applies **every patch in `patches/`**,
including the `common.cuh` header fix (0024) and the Hopper/Blackwell PDL dependency wait (0026,
[details](../CREDITS.md#hopperblackwell-pdl-fix)). No manual patch application or Git author configuration is
needed. There is no prebuilt Linux binary yet.

Prerequisites: NVIDIA driver, CUDA toolkit (`nvcc` on PATH), Git, CMake >= 3.24, and a C++ compiler supported by
your CUDA toolkit. On Ubuntu/Debian, the ordinary build dependencies are:

```bash
sudo apt-get update
sudo apt-get install -y git cmake build-essential libcurl4-openssl-dev libssl-dev
```

Install the NVIDIA CUDA toolkit separately if `nvcc --version` is unavailable. CUDA 13.x is not the cause of the
undefined `ggml_cuda_info` error below.

```bash
git clone https://github.com/professorpalmer/bonsai-ada-surgery.git
cd bonsai-ada-surgery
bash build/build_linux.sh
bash start-linux.sh /absolute/path/to/Ternary-Bonsai-2-27B-PTQ1_0.gguf
```

Use the official original `Ternary-Bonsai-2-27B-PTQ1_0.gguf` from
[the official model download](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/blob/main/Ternary-Bonsai-2-27B-PTQ1_0.gguf);
the model download is separate. If you already have it, pass its existing path. The scripts do not install system
packages, download weights, or change your existing `vendor/prism-llama` checkout.

Open **http://127.0.0.1:8080** on the same machine. The API is at `http://127.0.0.1:8080/v1`. Ctrl-C stops it.
`start-linux.sh` is a first-run configuration: 8k context, full GPU offload, flash attention, no speculative draft.
It is not the Windows recipe behind the headline numbers. The same runtime flags work on Linux. For the full window
with q8_0 KV on a 12 GB card (the recipe before bundle-20261016), launch the built server directly, for example:

```bash
llama-server -m Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf -ngl 99 -fa on -c 262144 -np 1 \
  -ctk q8_0 -ctv q8_0 --kv-vram-cells 110000 \
  --spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-n-max-tail 4 --spec-draft-window 16384 -ctkd q8_0 -ctvd q8_0 \
  --reasoning-effort-allow medium --reasoning-max-tokens-floor 24576 --reasoning-budget 20480 \
  --chat-template-kwargs '{"reasoning_effort":"medium"}' --jinja --host 127.0.0.1 --port 8080
```

(`--kv-vram-cells`: as many positions as fit in VRAM next to the weights, ~34.8 KB per q8_0 position for this model;
Linux has no WDDM demotion, so less margin is needed than on Windows. Untested on Linux here.) The Windows launcher
uses 18,432 B per q4_0 position and 14,336 B per q3_0 position for the same sizing. A user-run Linux and Windows
comparison at the same cells on a 12 GB card is in
[`docs/research/os-same-cells-20261017/`](../research/os-same-cells-20261017/README.md).

Set `BONSAI_CTX` and `BONSAI_PORT` to change the `start-linux.sh` defaults. The build uses four jobs by default;
lower `BONSAI_BUILD_JOBS` on low-memory hosts. CMake detects the GPU by default. For a headless build without an
attached GPU, pass its target architecture, e.g. `BONSAI_CUDA_ARCH=89 bash build/build_linux.sh` for Ada.

The build uses a separate source directory keyed by the base commit and patch contents. Repeating the command reuses
its build; changed patches get a new source directory. It refuses to overwrite tracked edits in an existing
generated source tree. After pulling updates to this bundle, rerun the build script.

The [Linux CUDA build workflow](../../.github/workflows/linux-cuda.yml) compiles the patch stack with CUDA 13 for Ada
without a GPU. A successful compile does not establish GPU inference correctness or Linux benchmark results.

### Direct fork build (alternative)

The buildable llama.cpp fork is
[llama.cpp-ada-ternary, branch `bonsai-q8-product`](https://github.com/professorpalmer/llama.cpp-ada-ternary/tree/bonsai-q8-product)
(the same tree as the patch series). `bonsai-combo` is #221 alone, without the tiered KV cache and the newer flags.

```bash
git clone --branch bonsai-q8-product https://github.com/professorpalmer/llama.cpp-ada-ternary
cd llama.cpp-ada-ternary
cmake -S . -B build-linux -DGGML_CUDA=ON \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=native
cmake --build build-linux --target llama-server -j4
```

### Updating an existing source checkout

Run these inside the **llama.cpp fork**, such as `vendor/prism-llama`, rather than in the outer
`bonsai-ada-surgery` directory:

```bash
git fetch origin
git switch bonsai-q8-product
git pull --ff-only
```

Then rerun the configure and build commands above. Preserve any local changes; if Git cannot fast-forward, use a
separate fresh clone instead of resetting it.

The `common.cuh` errors saying `ggml_cuda_info` and `ggml_cuda_get_device` are undefined come from a
declaration-order bug fixed in
[`32842f6`](https://github.com/professorpalmer/llama.cpp-ada-ternary/commit/32842f6cf208187d1624da5d968e410e117772d8).
Patch `0024` carries that fix for patch-series users. Downgrading CUDA does not address this source-order error.
Updating only the outer bundle does not update an already cloned `vendor/prism-llama` checkout.

## Build from source (Windows)

Windows without the CUDA toolkit (VS 2022 Build Tools C++ workload + NVIDIA's pip wheels):

```powershell
python -m pip install cmake ninja nvidia-cuda-nvcc nvidia-cuda-runtime nvidia-cublas nvidia-cuda-nvrtc
git clone -b bonsai-q8-product https://github.com/professorpalmer/llama.cpp-ada-ternary vendor\prism-llama
.\build\build_windows.ps1                    # arch from nvidia-smi; -Arch "75;86;89;89-virtual" for a release build
```

### Alternative: apply the bundled patches to PrismML source

Use a fresh checkout at the exact base below. Do not apply this series on top of `bonsai-q8-product` or
`bonsai-combo`, which already include the changes. From this bundle's root:

```bash
BONSAI_PATCH_DIR="$PWD/patches"
git clone https://github.com/PrismML-Eng/llama.cpp vendor/prism-patched
cd vendor/prism-patched
git checkout adfffbe
git am "$BONSAI_PATCH_DIR"/*.patch
cmake -S . -B build-linux -DGGML_CUDA=ON \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=native
cmake --build build-linux --target llama-server -j4
```

`git am` requires your Git author name and email to be configured. The series is verified to reproduce the
`bonsai-q8-product` tree exactly on a fresh `adfffbe` checkout.

## Layout

| Path | What |
| --- | --- |
| `patches/` | the patch stack on PrismML `adfffbe`, `git am`-able ([list](PATCHES.md)) |
| `start-server.ps1`, `start-remote.ps1` | the recipe (LAN / Cloudflare tunnel) |
| `build/build_linux.sh`, `start-linux.sh` | Linux build from the pinned base + patches, first-run launcher |
| `tests/`, `.github/workflows/` | Linux setup tests, Linux CUDA compile and PDL code-generation CI |
| `build/` | toolkit-free Windows CUDA build, MTP head grafts |
| `layer/` | the Bonsai layer ([docs](../agents-layer/README.md)) |
| `bench/` | receipts, KL sweeps, tool-call stress, HumanEval runner and Killy replays; `render_cards.ps1` renders the cards |
| `surgery/` | the kernel investigation: write-up, CUPTI injection profiler, clock sweeps, dead ends |
| `docs/12gb/`, `docs/8gb/` | setup and numbers per card size |
| `docs/quality/` | KV precision, reasoning effort, tool-call syntax, harness-proofing, benchmark your own model |
| `docs/agents-layer/` | the Bonsai layer: API cards, sandboxed Python, saved conversations |
| `docs/build/` | this page, launcher settings, vision, the patch stack, upgrading notes |
| `docs/speed/` | decode and prefill past the VRAM line, decode efficiency, ideas tested and not adopted |
| `docs/cards/` | the card sources (HTML, one data object per card) |
| `docs/receipts/` | raw logs behind the numbers, and the speed receipts page |
| `docs/research/` | every study with its plan, decisions and receipts; `small-models-20261006/` has the Bonsai 2 2B / 4B / 9B early-access tests |
