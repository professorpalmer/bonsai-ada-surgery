# q8_0 at the full 262,144 window on a 12 GB card

Measured 2026-09-26/27 on the RTX 4070 (12 GB, PCIe 4.0 x16, Windows WDDM, i7-13700K, 32 GB), Bonsai 2 27B
PTQ1_0 with the ProCreations MTP head, served by `start-server.ps1`, genuine prefill (no slot restore)
unless noted. Runtime: `claude/q8-262k-tier` on top of the #221 combo (`f4be987`).

## Result

One recipe, no env vars: the full trained window with q8_0 K/V (the KV precision `docs/QUALITY.md` measured
at 1 flipped top token in 160 at depth, against 1 in 48 for q4_0).

| Depth | Prefill (tok/s, cumulative) | Decode (tok/s, code continuation, temp 0) | Before (README, 96k/q8_0 or 262k/q4_0) |
| ---: | ---: | ---: | --- |
| 4k | 1,155 | 86.9 | ~80 |
| 16k | 1,090 | 111.6 (prose 87) | ~75 |
| 32k | 913 | 105.1 | 47.6 |
| 64k | 714 | 90.3 (prose 72) | 36.9 |
| 93k | 566 | 88.6 | edge of the 96k window |
| 131k | 344 | 34.3 | q8_0 did not fit |
| 180k | 280 | 22.7 | q8_0 did not fit |
| 258k | 222 | 14.1 | q8_0 did not fit |

(4k/16k rows are with the MMA attention path at every depth; 32k and deeper from the same recipe's sweep.)

## What changed, and what each part measured

1. **Tiered KV (`LLAMA_KV_VRAM_CELLS`).** Each attention layer's K/V is one CUDA VMM range: cells below N
   backed by VRAM, the rest by pinned system RAM mapped into the same range, so no kernel changes. The
   first N positions run at full speed; past N a step reads the RAM tail over PCIe (~20-25 GB/s).
   Greedy output is **bit-identical** to an all-VRAM cache (hashes of 256-token code and prose
   continuations at 20k depth, with and without staging). N is sized at launch from free VRAM minus
   `BONSAI_VRAM_MARGIN` (1300 MiB): 800 MiB held for a few minutes and then Windows demoted the
   background server (56.8 vs 79.9 tok/s); 1300 held through a 10-minute soak (84.2 / 76.9 tok/s at
   4k / 16k, above the 96k recipe's 82.5 / 75.3). Why WDDM does this is in `docs/QUALITY.md` (paging).
2. **RAM-tail staging (`GGML_CUDA_TIER_BOUNCE`, `_DECODE`).** Past the line, attention first copies the used
   tail into a VRAM staging buffer with the copy engine, through a second VMM alias of the same VRAM head.
   Prefill: the tail is read once instead of once per query tile (146 -> 280+ tok/s in the tail).
   Decode: DMA instead of SMs reading over PCIe, +28% at 180k.
3. **Drafting at every depth, with a draft window.** The old `--spec-draft-depth-max 24576` cutoff was
   measured when deep verify batches ran on the vector attention kernel and the draft cache grew with the
   conversation. Now: full draft history to 24k, then only the last 16k rows (`LLAMA_SPEC_DRAFT_WINDOW`),
   so the draft cache stays ~100 MB and in VRAM. 32k 54.5 -> 103.6 tok/s, 64k 48.0 -> 90.1 (prose
   47.8 -> 72.4), draft acceptance unchanged. The window alone was +17-18% at 131k.
4. **Draft size by depth.** 2 below the VRAM line (prose at 16k: 87 vs 82.5 for 3; code +3% for 3), 4 past
   it (+26% code / +15% prose at 180k for 4 vs 2: a PCIe-bound verify is nearly free per extra column).
5. **MMA attention at every depth for <= 8 queries (`GGML_CUDA_FA_DEEP_MMA=256`).** Bonsai 2 has 24 query
   heads over 4 KV heads; the vector kernel reads each K/V row once per query head, the MMA kernel once per
   KV head. 4k 78.1 -> 86.9, 16k 77.7 -> 111.6 tok/s.
6. **Harness-proofing** (Killy's plate 035: the same weights score 0-160/164 by client alone). An effort
   word the template rejects ("high" -> HTTP 500 in Cline/Kilo/Open WebUI) becomes `medium`; so do `low`
   and `xhigh` (medium beats both at every output cap; PrismML's card says low behaves close to xhigh).
   With thinking on, a client `max_tokens` below the think budget + 4096 is raised to it (256/300/1024/
   4096-token app caps end the request mid-think). Smoke test: `reasoning_effort: "high"`, `max_tokens:
   256` returns the answer instead of HTTP 500. Opt out: `BONSAI_HARNESS_PROOF=0`.

## Measured and rejected

| Idea | Result |
| --- | --- |
| K mean-centering (`--kv-mean-center`, extended to q8_0) on top of the default Hadamard rotation | q4_0 KLD 0.00206 vs 0.00218, max KLD 2.87 vs 0.94 (worse); q8_0 unchanged. Rotation already absorbs the offset. |
| Model-card non-thinking sampling (0.7 / 0.8) for tool calls | `bench\toolcall_stress.py`, n=9: parsed 6/9 vs 8/9 at 1.0 / 0.95; more payloads ran into the cap. |
| Thinking `medium` + 24k cap for payload-heavy tool calls | 6/9 parsed vs 8/9 thinking-off; 10-17k thinking tokens before the call. Medium stays the chat/coding default; tool agents send `enable_thinking: false`. |
| `GGML_CUDA_GRAPH_OPT=1` (concurrent streams) | tg128 66.1 vs 67.9. |
| PTQ1_0 mat-vec at 5-6 columns instead of MMQ | pp5 161.7 vs 172.4. The 4-column crossover stands. |
| Draft cache fully in VRAM (lower main line to pay for it) | 16.0 vs 17.2 tok/s at 180k; the window (3) is the better fix. |
| Fixed MMA tile for batch invariance (`GGML_CUDA_FA_INVARIANT_TILE=1`) | -7% at 64k and still not fully invariant (below). Opt-in only. |

## Caveats

- **`BATCH_INVARIANT` does not make MTP-on bit-identical to MTP-off past ~32k, stock kernels included.**
  The attention KV split (stream-k partition, and the vector path's parallel-block count) follows the padded
  KV length, which a verify batch can push one 256-tile ahead of a later single-token decode. Rounding-level
  differences; both continuations are valid greedy decodes. `docs/QUALITY.md`'s identity claim holds only
  below that. With (5) on, the MMA path makes the same true at shallow depth.
- Numbers past the VRAM line depend on PCIe: x8 or PCIe 3.0 halves them.
- The VRAM line moves with what the desktop holds. Moving the display to the i7's iGPU (dwm alone holds
  ~600 MiB on the 4070) would put ~30k more positions at full speed.
- A slot restored with `/slots?action=restore` does not rebuild the draft context; deep measurements from a
  restored slot understate draft cost and acceptance.

## Reproduce

```
.\start-server.ps1                                   # the recipe above
$env:BONSAI_TIER='0'; .\start-server.ps1             # previous 96k all-VRAM recipe
bench\kv_mean_center_kl.ps1                          # mean-centering KL (needs the kv_kl_sweep base file)
python bench\toolcall_stress.py --temp -1 --top-p -1 # tool calls with server-side sampling
```
