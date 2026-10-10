---
license: apache-2.0
base_model:
  - prism-ml/Ternary-Bonsai-2-27B-gguf
base_model_relation: quantized
library_name: gguf
pipeline_tag: text-generation
tags:
  - llama.cpp
  - gguf
  - qwen3_5
  - ternary
  - ptq1_0
  - bonsai
  - mtp
  - speculative-decoding
  - long-context
  - 262k
  - agents
  - tool-calling
  - windows
language:
  - en
---

# Bonsai 2 27B, served: the full 262,144-token window at q8_0 on a 12 GB card

**A 27B model with its whole trained context window, at q8_0 KV precision, on one RTX 4070 12 GB. 78 tok/s of new
text at 32k tokens of context (175 on code), 69 at 64k, 61 at 112k, and the window keeps going to 262k. Lossless speculative decoding at
every depth. A server that answers the requests agents and apps actually send. One command on Windows.**

This is PrismML's [Ternary Bonsai 2 27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) (1.58-bit
ternary `PTQ1_0`, 5.9 GB, Apache 2.0), the same weights, nothing re-quantized, with its MTP draft head grafted back
on (byte-identical trunk, proof below) and the serving stack from
[github.com/professorpalmer/bonsai-ada-surgery](https://github.com/professorpalmer/bonsai-ada-surgery): a tiered KV
cache that puts the first ~119k positions in VRAM and the rest in pinned system RAM with bit-identical output,
MTP drafting that pays at every depth, harness-proofing for the apps that send `effort: "high"` or tiny output caps,
and an optional server-side layer (exact API cards, an API check, a sandboxed Python tool) that lifts the model's
coding and agentic scores without touching the weights.

| RTX 4070 12 GB, served, one slot | decode, new text (tok/s) | decode, code (tok/s) | prefill (tok/s) |
| --- | ---: | ---: | ---: |
| 4k tokens of context | **102** | 102 | 1,173 |
| 16k | **83** | 242 | 1,137 |
| 32k | **78** | 175 | 1,031 |
| 64k | **69** | 109 | 867 |
| 112k (in VRAM) | **61** | 91 | 698 |
| 131k | **30** | 63 | 649 |
| 180k | **17.9** | 28 | 547 |
| 258k (the window's end) | **8.6** | 12.1 | 436 |

Measured 2026-10-08 (`bench/depth_table.sh`), a fresh prompt at each depth: 400-token greedy answers with the
default drafting (lookup + MTP head); new text = an essay, code = a Python module; prefill = cumulative for the
whole prompt; display on the CPU's iGPU. Every number
has a receipt in the repository (`docs/Q8_FULL_CONTEXT.md`, `docs/RECEIPTS.md`, `docs/QUALITY.md`).

## What the serve changes, same weights

| | before: the published 12 GB recipes | this serve |
| --- | --- | --- |
| window on 12 GB with q8_0 KV | 96k (q4_0 KV to reach 262k) | **262,144 at q8_0** |
| KV precision at depth | q4_0: 1 flipped top token in 48 | q8_0: **1 in 160** |
| decode at 32k / 64k | 47.6 / 36.9 | **78 / 69** on new text, **175 / 109** on code (2026-10-08 table) |
| decode when the answer copies the context (file rewrite), 4k / 130k / 250k | 117 / 63 / 18.5 (MTP only) | **352 / 164 / 66** (lookup drafting) |
| speculative decoding | up to 24k, then off | **at every depth**, outputs identical to drafting off |
| apps that send `effort: "high"` (Cline, Kilo, Open WebUI) | HTTP 500 on every request | **answered** (normalized to medium) |
| apps with a 256-4096 token output cap, thinking on | cut off mid-think | **answered** (cap raised to the thinking budget) |
| HumanEval 164 from an app that sends `effort: "high"` | 0 (HTTP 500) | **160** |
| tool calls parsed (9 requests) | 1 of 9 (JSON asked for in content) | **9 of 9** (native XML, server grammar) |
| AppWorld, all 168 test tasks, ReAct code agent | 64.3% (published, stock serve); 16 wrong-format replies, 15 step-cap exits | **70.8%** (95% CI 63.6-77.2); **1 and 1** |
| long exact-work suite, 37 tasks, same seeds | 17 raw | **28** behind the layer (13 rescues, 2 losses); 29 on a second seed set |
| AIME 2025 (60) / MMLU-Pro (100), raw -> layer | 52 / 71 | **56 / 76** |
| HumanEval 164, medium reasoning, sandbox-scored | | **161** |

Most of the quality gap people report on Bonsai 2 for code and agents is runtime, not compression: the effort word
the template rejects, the output cap that ends a thinking model mid-thought, the tool-call format. The server fixes
those; the layer adds exact references and a sandbox. The weights are untouched.

## Files

| file | what | size |
| --- | --- | ---: |
| `Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf` | PrismML's PTQ1_0 file with the on-policy Q8_0 MTP draft head from [ProCreations/Ternary-Bonsai-2-27B-MTP](https://huggingface.co/ProCreations/Ternary-Bonsai-2-27B-MTP) grafted on as `blk.64.*`; every original tensor byte-identical to PrismML's file (proof below). This is the file the launcher uses: lossless speculative decoding, 70.6% draft acceptance, +50-100% decode | 6.40 GB |
| `bonsai-bundle-win-x64.zip` | Windows binaries: the patched llama.cpp (PrismML fork + 49 patches), sm_75 / 86 / 89 machine code (RTX 20 / 30 / 40) plus compute_89 PTX for RTX 50, CUDA 13 runtime included, NVIDIA driver only. Launcher, layer, suite and docs at the release tag (`bundle-20261009-probe`) | 608 MB |
| `start-server.ps1` | the launcher (also inside the bundle): reads free VRAM, sizes the VRAM line, starts the layer and the server | |

The original `Ternary-Bonsai-2-27B-PTQ1_0.gguf` without the head also works with everything here (`BONSAI_SPEC=0`
for no drafting, or let the launcher fall back); get it from
[prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf).

## Run it (Windows, NVIDIA RTX 20 / 30 / 40 / 50)

```powershell
git clone https://github.com/professorpalmer/bonsai-ada-surgery && cd bonsai-ada-surgery
hf download CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF bonsai-bundle-win-x64.zip --local-dir .
Expand-Archive bonsai-bundle-win-x64.zip -DestinationPath . -Force
hf download CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf --local-dir models
.\start-server.ps1
```

OpenAI-compatible API on `http://<host>:8080/v1`, bearer key in `artifacts\api_key.txt` (created on first run),
llama.cpp's chat UI on the same port. The launcher prints the VRAM line it chose. Optional, once:
`layer\fetch_runtime.ps1` downloads the sandbox runtime for the layer (CPython 3.12 on WASI, checksummed, 14 isolation
canaries); without it the plain server runs.

Linux: `bash build/build_linux.sh` in the repository builds the pinned PrismML source with all 49 patches applied;
the full-window command line is in the repository README. No prebuilt Linux binary yet.

Cards: 12 GB is the measured recipe (display on the iGPU: ~119k positions in VRAM; display on the card: ~95k, measured 2026-09-27).
16 GB and up: the whole q8_0 window fits, the tier switches itself off. 8 GB: the launcher detects the card and
uses its 8 GB preset (q4_0 K/V, a 131k window, a Q4_0 MTP head). Measured on an RTX 2060 SUPER that also draws
the desktop: 51.2 / 43.1 tok/s at 4k / 32k, HumanEval medium 157 of 164 (repository `docs/8GB.md`).

## For agents and apps

- Send `tools` and let the server format and parse the calls (native Qwen3-Coder XML, grammar-constrained).
- Tool-heavy agents: `chat_template_kwargs: {"enable_thinking": false}` per request. Chat and coding answers: the
  server default (medium reasoning, 20k thinking budget, forced close).
- Clients that cap `max_tokens` low are fine: with thinking on the server raises the cap.
- `effort: "high"`, `"xhigh"`, `"low"`: mapped to medium, answered, logged. `BONSAI_HARNESS_PROOF=0` passes words
  through unchanged.

## Knobs

`BONSAI_CTX` (262144), `BONSAI_CTK` (q8_0), `BONSAI_TIER` (1), `BONSAI_KV_VRAM_CELLS` (auto), `BONSAI_VRAM_MARGIN`
(1000 headless / 1300 with the display on the card), `BONSAI_SPEC` / `BONSAI_SPEC_DEEP` (2 / 4), `BONSAI_DRAFT_WINDOW`
(16384), `BONSAI_EFFORT` (medium), `BONSAI_THINK` (1), `BONSAI_THINK_BUDGET` (20480), `BONSAI_HARNESS_PROOF` (1),
`BONSAI_LAYER` (1), `BONSAI_PORT`, `BONSAI_MODEL`, `BONSAI_MMPROJ` / `BONSAI_MMPROJ_GPU` (vision projector;
image encoder on the CPU by default, no VRAM cost). Full table and the VRAM arithmetic in the repository README.

## How it works, in one paragraph each

**Tiered KV cache** (`--kv-vram-cells`). The first N positions of every layer's K/V live in VRAM, the rest in pinned
system RAM mapped into the same CUDA address range. Kernels are unchanged and output is bit-identical to an all-VRAM
cache. Past the line, attention copies the used RAM rows into VRAM with the copy engine first, so decode there is
bound by PCIe (4.0 x16 here). The box needs ~8 GB of free RAM for the tail at 262k.

**MTP drafting at every depth** (`--spec-draft-window`). The draft head only needs recent context, so its cache
keeps the last 16k rows and stays small. With quantized-KV decode on the tensor-core attention kernel (one K/V read
per verify batch), drafting pays at every depth; greedy output equals greedy output without the head.

**Harness-proofing** (`--reasoning-effort-allow`, `--reasoning-max-tokens-floor`). The same weights score 0 to 160
of 164 on HumanEval depending on what the client sends. The server absorbs both causes.

**Lookup drafting** (patch 0039, on by default). An n-gram drafter drafts text that is already in the context, up to
32 tokens at a time, in front of the MTP head. File rewrites 117 -> 352 tok/s at 4k and 18.5 -> 66 at 250k; new text
unchanged; same output.

**Prefill past the VRAM line** (patch 0041). The K/V rows a prefill batch writes past the line go to VRAM first and
then to system RAM in whole blocks; the next layer's RAM rows are copied while the layers before it compute. A 258k
prompt: 369 -> 436 tok/s, same output.

**Many tools cost no decode speed** (patch 0042). With speculative decoding the server copies the sampler on each
draft step; with tools, the copy of the tool-call grammar searched every grammar element, about 15 ms per step with
107 tool schemas. Now a binary search: 107 tools at 63k, 41.8 -> 61.2 tok/s (2 tools: 63.5), same output.

**The layer.** A small proxy the launcher starts in front of `llama-server` on the same port. Exact API cards for
the Python modules a request involves (generated from the sandbox's own runtime), an API check that flags names that
do not exist, and a sandboxed Python tool with the user's text as `input.txt`. Clients change nothing.

## Proof the weights are untouched

Checked tensor by tensor against PrismML's published file (`bench/gguf_tensor_identity.py` in the repository, run
2026-10-06): **all 851 tensors of `Ternary-Bonsai-2-27B-PTQ1_0.gguf` are byte-identical** in this file; the only
tensors added are the 15 of `blk.64.*`, the draft head. Metadata differs by five added keys (`graft.*`,
`qwen35.nextn_predict_layers`, block count 64 -> 65) and by the embedded chat template, which is this repository's
template: PrismML's, plus a system block of operating rules for tool use (save long command output to a file and
read the part you need, and so on) that every measurement here was taken with. The launcher uses the GGUF's embedded
template with `--jinja`, so this file serves with that template; PrismML's original file serves with PrismML's.

| file | sha256 |
| --- | --- |
| `Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf` | `5f212d02ff57cb8eaad260fd7ff57bfaff87ae2bc9183a21dd2f127c27252505` |
| PrismML's `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (the base) | `53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3` |
| `bonsai-bundle-win-x64.zip` | `18b2a51966c2bee13ec7240447ac43ec82ca89f935eefc930bb94e8fc4e9f5c3` |

Every kernel in the stack is checked against the CPU reference, and the served output is checked greedy
token-for-token against the unpatched fork before any speed number is recorded.

## Credits and licenses

- **PrismML** for Bonsai 2 27B and the [llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp) this runtime is
  built on. The serving patches are submitted there (#319-#323, #295, #296, #333; earlier work merged in #214, #216, #221).
- **sudoingX** for the planar-transposed activation layout, the batch-invariant mode, the MTP graft tools and the
  Hadamard fix for the draft graph ([bonsai2-small-gpu](https://github.com/sudoingX/bonsai2-small-gpu), PrismML #217,
  #218).
- **ProCreations** for the on-policy MTP draft head
  ([Ternary-Bonsai-2-27B-MTP](https://huggingface.co/ProCreations/Ternary-Bonsai-2-27B-MTP)).
- **Alibaba Qwen** for Qwen3.5-27B, the base model.
- **Testers who filed issues with full logs:** [@Milor123](https://github.com/Milor123) (empty JSON-schema unions,
  the vision projector and GPU sharing, deep-context agent runs) and
  [@outbackdingo](https://github.com/outbackdingo) (GCC 16 build).
- The serving stack, launcher, layer, suite and docs: MIT, Cary Palmer. The weights are Apache 2.0 as published by
  PrismML; this repository redistributes them with the head added and the notices kept. Not affiliated with,
  endorsed by or sponsored by PrismML, sudoingX, ProCreations or Alibaba.

Issues and measurements: [github.com/professorpalmer/bonsai-ada-surgery](https://github.com/professorpalmer/bonsai-ada-surgery).
