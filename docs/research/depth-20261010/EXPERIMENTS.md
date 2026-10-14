# Experiments D01-D20

Format per entry: **question**, **gate** (and where it was declared), **setup** (hardware, engine commit, root, env,
script), **result**, **verdict**, **receipts**. RTX 4070 12 GB, 12 GB recipe (262k window, q8_0 KV, tiered cache,
MTP + lookup drafting, layer off) unless stated. "Mean decode" is `bench/quick_tps.py`'s mean over its code / prose /
bash items (400 tokens each). Retrieval: `bench/needle_depth.py` (12 facts) and `bench/code_needle.py` (exact copies
of 10 short Python functions from `artifacts/eval/pycode.raw`).

---

## D01 Side request re-reads the whole prompt (2026-10-10 09:30-11:51)

- **Question.** Coding agents send short side requests (titles, summaries) between turns. With one slot, does the next
  turn re-read the whole prompt?
- **Gate.** None (diagnosis). Fix gate declared in chat: turn 2 reuses the cached prompt.
- **Setup.** 120k-token prompt, then a 25-146-token side request, then turn 2 (`bench/side_request.py`,
  `bench/side_ab.sh`). Arms: `np1` (product), `np2` (`BONSAI_SLOTS=2`, unified KV, idle-slot cache off), `np2keep`
  (same + `LLAMA_SLOT_KEEP_TOKENS=4096`, engine `87e2ac160`).
- **Result.**

  | arm | turn 2 tokens read | cached | turn 2 wall |
  | --- | ---: | ---: | ---: |
  | np1 | 119,995 | 121 | 178.8 s |
  | np2 | 120,116 | 0 | 232.3 s |
  | np2keep | **19** | **120,097** | **0.7 s** |

  The first np2keep run (11:16) is void: two test chains ran on the GPU at the same time (out of memory).
- **Verdict.** Cause found: the side request takes the only slot (np1), or the similarity rule gives it the deep slot
  (np2). `LLAMA_SLOT_KEEP_TOKENS` keeps a deep slot for its conversation. Prototype only; see D02 for its cost.
- **Receipts.** `docs/receipts/side_ab.log`, `docs/receipts/side_ab.jsonl`.

## D02 Cost of a second slot (2026-10-10 12:24-12:32)

- **Question.** What does `-np 2` cost at 32k?
- **Gate.** None (measurement).
- **Setup.** `bench/slots_prefill.sh`, code item at 32k, `BONSAI_VRAM_MARGIN=1300` in all arms.
- **Result.** Mean decode / prefill: np1 85.5 / 1045.5, np1 unified 86.0 / 1041.8, np2 not unified 12.6 / 161.4
  (broken), **np2 unified 71.9 / 819.9 (-16 % / -22 %)**, np1 again 86.1 / 1040.6.
- **Verdict.** Unified KV is required for two slots; the remaining -16 % is unexplained (open). D01's fix is not
  shipped until this cost is understood.
- **Receipts.** `docs/receipts/slots_prefill.log`.

## D03 Sparse host-tail reads: retrieval, emulation (2026-10-10 11:23-12:12)

- **Question.** If each query reads only the top pages of the host tail (Quest page bounds), does retrieval hold?
- **Gate.** Declared in chat and #21: needles equal to dense.
- **Setup.** Engine `f5f273aed` (emulation: every host row still read, the mask hides the rest). 160k, VRAM line
  pinned at 32,768 cells (`BONSAI_KV_VRAM_CELLS`), graphs off, f16 mask, `GGML_CUDA_FA_SPARSE=B,64,1024`
  (`bench/needle_ab.sh`).
- **Result.** Needles: dense 12/12, B = 8192 12/12, B = 4096 12/12. (The first dense arm at 11:23 did not start:
  health = 0; rerun at 11:51.)
- **Verdict.** Pass at both budgets.
- **Receipts.** `docs/receipts/needle_ab.log`, `.jsonl`.

## D04 Sparse host-tail reads: exact code copies, emulation (2026-10-10 13:24-13:49)

- **Question.** Does exact recall of code hold? Needles are easy; copying a function needs every token.
- **Gate.** Declared in chat: copies equal to dense.
- **Setup.** As D03, `bench/code_needle_ab.sh`.
- **Result.** Exact copies: dense 10/10, B = 8192 **10/10**, B = 4096 8/10.
- **Verdict.** B = 8192 (page 64) passes; B = 4096 fails. B = 8192 is the budget from here on.
- **Receipts.** `docs/receipts/code_needle_ab.log`, `.jsonl`.

## D05 Sparse reads: KL on wikitext (2026-10-10 10:02-11:16, then 12:54-13:23)

- **Question.** KL divergence of sparse vs dense logits at depth.
- **Gate.** None declared.
- **Setup.** `llama-perplexity --kl-divergence-base` on wikitext-2 with a 64k-class window, one chunk (the first
  attempt with three chunks wrote 16 GB of logits per chunk and was restarted with `--chunks 1`); the exact flags of this
  early run were not kept, because `bench/sparse_kl.sh` was rewritten afterwards (13:49) with safe defaults.
- **Result (one chunk).**

  | arm | mean KLD | same top-1 | max KLD | 99.9 % KLD |
  | --- | ---: | ---: | ---: | ---: |
  | dense base | | | | |
  | B = 8192 | 0.002998 | 97.720 % | 0.624 | 0.155 |
  | B = 4096 | 0.008089 | 96.356 % | 3.135 | 0.370 |

  Base perplexity 7.9458 +/- 0.11443. Two lines at 10:21 are void (an old instance ran against a deleted base file).
  The follow-up runs at 64k (wikitext and Python source, 12:54-13:23) froze the PC twice (12:55 and about 13:10). From
  the Windows event log: low virtual memory naming `llama-perplexity`; the KL base keeps about n_ctx / 2 x 248,320 vocab
  x 4 bytes = ~32 GB of logits on a 32 GB machine. A rerun at the safe size (`-c 16384`) wrote nothing usable.
- **Verdict.** Consistent with D03 / D04: B = 8192 is close to dense, B = 4096 lossier. One chunk only, so it is a
  check, not a gate. Lasting changes: `tools/ramguard.ps1` (kills `llama-server` / `llama-perplexity` when free commit
  < 6 GB or free RAM < 1.5 GB) in every heavy script, and the rule "estimate a run's RAM first; KL at most 16k context
  with this vocab".
- **Receipts.** `docs/receipts/sparse_kl.log`.

## D06 Vec kernel skips fully masked tiles (2026-10-10, `346b123b5`)

- **Question.** Can the decode attention kernel skip a 128-cell tile whose mask is `-inf` for every cell and column,
  so unselected host pages are not read?
- **Gate.** Exactness: all `FLASH_ATTN_EXT` op tests pass.
- **Result.** `test-backend-ops -o FLASH_ATTN_EXT -b CUDA0`: 3007 ok, 0 fail.
- **Verdict.** Exact; kept. (Its 128-cell size later turned out too coarse for 64-cell pages on 2-query steps, D17.)
- **Receipts.** `docs/receipts/sparse_speed.log` (first line).

## D07 Sparse decode speed, first fast builds (2026-10-10 18:55-20:23)

- **Question.** Does reading only the kept pages speed up decode at 192k and 250k?
- **Gate.** None (measurement).
- **Setup.** `bench/sparse_speed.sh`, 12 GB recipe's own VRAM line. Arms: dense as shipped (graphs on, packed mask),
  dense-fair (graphs off, f16 mask), sparse `8192,256,1024` fast. Lookup off: engine `c084831aa`; lookup on: engine
  `71371d4cb` (fast path up to 64 queries, page staging).
- **Result.** Mean decode at 192k / 250k:

  | arm | lookup off | lookup on |
  | --- | --- | --- |
  | dense as shipped | 19.8 / 12.3 | 19.7 / 12.7 |
  | dense-fair (graphs off) | 22.8 / 13.4 | |
  | sparse | 21.5 / 13.5 | 14.4 / 9.2 |

- **Verdict.** No gain; slower with lookup. Two findings came out of it: dense-fair beat dense as shipped by 15 %,
  which led to the CUDA graphs finding (patch 0053, `docs/research/release-20261011/`); and the sparse arms paid a host
  sync per K write (fixed in `2f47c38b7`, D09) and read masked tiles (D11).
- **Receipts.** `docs/receipts/sparse_speed.log`.

## D08 Cached page bounds after a deep prompt edit (2026-10-10 18:55-19:07)

- **Question.** The fast path caches page bounds per K tensor. After a deep prompt edit, are they stale?
- **Gate.** Declared in chat: 0 stale-bound ops with tracking on.
- **Setup.** `bench/sparse_edit.sh`, engine `71371d4cb` with `GGML_CUDA_FA_SPARSE_CHECK=1` (recomputes all bounds every
  op and logs differences). 160k of Python files; then the file at 91 % replaced (24,966 tokens written again in the
  host tail); then the same request again. Arms: tracking on, `GGML_CUDA_FA_SPARSE_NOTRACK=1`.
- **Result.** Stale-bound ops (base / edit / again): tracking on 0 / 0 / 0, off 0 / 208 / 208 (for example 312 of 576
  page-heads differ from page 60). Device vs host page choice: 0 differences in all ops. The answer changed after the
  edit with tracking off, and stayed changed.
- **Verdict.** Pass. Tracking is required, and the device selection equals the host selection.
- **Receipts.** `docs/receipts/sparse_edit.log`.

## D09 Where a step's time goes at 192k: op timing (2026-10-11)

- **Question.** Is attention a large share of a decode step at 192k on 12 GB?
- **Gate.** Declared in chat: if attention is a small share, skip the whole-context and V-skip runs.
- **Setup.** `GGML_CUDA_OP_TIMING=1` (an event before every node, graphs off, printed every 100 graphs at WARN),
  engine `2f47c38b7` (no sync per K write), 12 GB line 121,344, f16 mask (`bench/depth_arms.sh`, tag `optime6`).
- **Result.** Dense: 21.7 tok/s, 25.1 ms per graph, ROPE 22 %, FLASH_ATTN_EXT 13 %. The ROPE share is the stream
  waiting for the staged host rows. Sparse without the tile map: 13.1 tok/s, 43.1 ms per graph, FLASH_ATTN_EXT 71 %.
  No "one sync per K write" warnings.
- **Verdict.** Attention plus the copy wait is ~35 % of a dense step: worth more work. Sparse without the tile map
  reads all masked tiles in place.
- **Receipts.** `docs/receipts/depth_arms.log` (tag `optime6`), `docs/receipts/op_timing_decode_bonsai.txt`.

## D10 Sparse reads at depth, 8 GB-like layout (2026-10-11 00:17-03:18)

- **Question.** With an 8 GB-like layout (VRAM line pinned at 32,768 cells, ~127k cells of host tail at 160k), what
  do the tile maps, the page size and sparse prefill do?
- **Gate.** Declared in chat and #21: copies 10/10 and needles 12/12 (equal to dense); then decode decides.
- **Setup.** `bench/sparse_prefill.sh`, 160k, `GGML_CUDA_FA_SPARSE_FAST=1 GGML_CUDA_KV_TIER_STAGE_MIN_Q=9`, graphs
  off, f16 mask. FA op tests on each new engine: 3007 / 0.
- **Result.**

  | arm (engine) | prefill | mean decode | copies | needles |
  | --- | ---: | ---: | --- | --- |
  | dense (`2f47c38b7`) | 583.8 | 13.6 | 10/10 | 12/12 |
  | sparse 8192,256, no tile map (`2f47c38b7`) | 583.7 | 9.1 | 9/10 | 12/12 |
  | sparse 8192,256 + sparse prefill (`MAXQ=4096`, tile map) | 618.4 | 29.6 | 8/10 | 11/12 |
  | sparse 8192,256, tile map (`85d949f5e`) | | 31.1 | 9/10 | 12/12 |
  | sparse 8192,64, 256-cell map (`85d949f5e`) | | 18.9 | 10/10 | 12/12 |
  | **sparse 8192,64, 64-cell map (`d6c6e9f01`)** | **583.6** | **27.6** | **10/10** | **12/12** |

  Page 256 misses the same copy (`_div_nearest`, 7 lines at 65 % depth) in both runs; page 64 gets it.
- **Verdict.** Page 64 with the 64-cell map passes the gate at 2.0x dense decode. Sparse prefill is rejected (+6 %
  prefill, quality loss). The no-map slowdown explained: 5-query verify ops run the MMA kernel, which read every
  masked host tile in place (slower than the dense DMA).
- **Receipts.** `docs/receipts/sparse_prefill.log`, `.jsonl`.

## D11 Whole-context selection (2026-10-11 06:03-06:56)

- **Question.** If the selection also covers the VRAM part (sinks kept), does attention cost follow the budget?
- **Gate.** Declared in chat: copies 10/10 and needles 12/12.
- **Setup.** `bench/sparse_whole.sh`, engine `85d949f5e`, 12 GB line 121,344, speed at 192k, quality at 160k; arms
  dense, host tail (`8192,256,1024`, tile skip), whole context (`SINKS=1024`).
- **Result.** Mean decode: dense 22.8, host tail 25.2, whole context **36.3**. Quality: dense 10/10 12/12, host tail
  10/10 12/12, whole context **8/10, 7/12**.
- **Verdict.** Rejected at this budget and page size. The page-64, B = 16384 retry is D19 (also rejected).
- **Receipts.** `docs/receipts/sparse_whole.log`, `.jsonl`.

## D12 V skip in the vec decode kernel (2026-10-11 08:48-09:23)

- **Question.** Skip the V rows of 32-cell groups whose weights are all below exp(-20) of the running maximum
  (`GGML_CUDA_FA_V_SKIP=1`, engine `f6f2d146c`)?
- **Gate.** Exactness (op tests, copies, needles), then decode.
- **Result.** FA op tests 3007 / 0; copies 10/10 and needles 12/12 in both arms; mean decode at 192k 19.7 / 19.7.
- **Verdict.** Exact, no gain on this engine: it lacks patch 0053, so the host copy limits decode there. Parked; retest
  on top of 0053 is optional.
- **Receipts.** `docs/receipts/vskip_ab.log`, `.jsonl`.

## D13 Prefill micro-batch at depth (2026-10-11 07:56-08:47)

- **Question.** Each micro-batch reads the whole prefix K/V once per attention op. Does a larger ubatch speed up deep
  prefill?
- **Gate.** None (measurement).
- **Setup.** `bench/ubatch_depth.sh`, release engine, `BONSAI_UBATCH`, cold prefill of a 128k / 192k prompt.
- **Result.** Prefill tok/s at 128k / 192k: ub 512 **654 / 524**, ub 1024 418 / 361, ub 2048 100 / (stopped).
- **Verdict.** 512 (the default) is best; larger loses VRAM to the compute buffer and moves more of the cache to
  system RAM. No change.
- **Receipts.** `docs/receipts/ubatch_depth.log`.

## D14 Chunked gated-delta-net prefill (2026-10-11 01:11-10:20)

- **Question.** Does a chunked MMA kernel for the 48 gated-delta-net layers (port of ggml-org/llama.cpp#29353) speed
  up prefill, also with speculative decoding on?
- **Gate.** Declared in chat: op tests pass; copies and needles equal; HumanEval 164 parity (160/164); sm_75 builds.
- **Setup.** Branch `gdn-chunked`: raw gates activated into temporaries; with K > 1 rollback snapshots the MMA kernel
  runs n - K tokens and the recurrent kernel the last K; the fused state gather copies the live rows first.
  `bench/gdn_prefill_ab.sh`, same binary, `GGML_CUDA_GDN_MMA_DISABLE=1` for the recurrent arm.
- **Result.**
  - Op tests: `GATED_DELTA_NET` 55 / 0 (7 new cases in this model's shape). The receipt says "ok 57": that was a count
    of OK lines (55 cases + 2 backend summary lines), corrected 2026-10-13.
  - First A/B (`ce27b9d14`): no change, because the kernel never engaged (the served graph uses the fused gather,
    which the first port excluded).
  - Second A/B (`31c337bbb`), engaged (log: 121 tokens, 116 by MMA, K 5, raw 1, gather 1). Prefill recurrent -> MMA:
    4k 1203.9 -> 1280.9 (+6.4 %), 32k 1021.3 -> 1080.5 (+5.8 %), 128k 581.1 -> 600.7 (+3.4 %). Decode unchanged.
    Copies 10/10, needles 12/12 at 32k in both arms.
  - sm_75 build of `ggml-cuda`: clean (on Turing the runtime check falls back to the recurrent kernel).
  - HumanEval 164, medium: **158/164** (release engine 160/164). New fails: #10 (release thought 18,077 tokens,
    MMA 1,000 and a wrong loop) and #132 (10,435 vs 20,632 tokens); no new passes; tokens unchanged (mean 2313).
- **Verdict.** Below the parity gate as written. The two flips are long-thinking items, where greedy trajectories
  diverge on tiny numeric differences, so a token-level measure decides: wikitext-2 perplexity, MMA vs recurrent on the
  same binary (`bench/gdn_ppl_ab.sh`), queued.
- **Perplexity gate (2026-10-13, `root-gdn2`, `-c 2048`, 32 chunks, gate +0.1 %).** Recurrent 8.0714 +/- 0.117, MMA
  8.0733 +/- 0.117 (**+0.024 %**); per chunk within ~0.013 (chunk 1: 6.7038 / 6.6994; chunk 16: 7.9998 / 8.0031);
  engaged line in the MMA arm only. So the two HumanEval flips are trajectory drift, not damage.
- **Final verdict.** Promoted: patch 0054 (PR #40, merged 2026-10-13, `de873117e`). 2060 check P116: not taken on sm_75,
  32k prefill and decode equal to 0053 within 0.2 %, op tests 55/55. From its note, 0054 checks the device before any
  temporaries (clean skip line on RTX 20).
- **Receipts.** `docs/receipts/gdn_prefill_ab.log`, `.jsonl`, `docs/receipts/gdn_ppl_ab.log`,
  `artifacts/humaneval-gdnmma` (local).

## D15 A third-party "sharp" chat template on tool work (2026-10-10 13:50-18:27)

- **Question.** Does a user's template with a different tool prompt help tool work?
- **Gate.** None declared (exploration).
- **Setup.** `bench/tool_template_ab.sh`: the GGUF's own template vs the third-party template file (kept local, not
  in this repo); suite plan `bench/plans/tools_template.json` (12 coding + 10 workspace items), then
  `bench/toolcall_stress.py --n 6`.
- **Result.** Suite: own template 9/22 (workspace 9/10, coding 0/12), third-party 6/22 (workspace 6/10, coding 0/12).
  Stress (native grammar arm): parsed 17/18 vs 18/18, payload ok 13 vs 14. Completion tokens 653,178 vs 562,661.
- **Verdict.** Rejected for tool work. The coding items are too hard for both (0/12), so later template tests use the
  workspace items only (`bench/plans/tools_workspace.json`).
- **Receipts.** `docs/receipts/tool_template_ab.log`.

## D16 RTX 2060 SUPER runs on the sparse branch (#21, 2026-10-10 to 2026-10-11)

Run by the 8 GB rig (numbers from its posts on #21; P-numbers are its run ids). Main 262k launcher, 245k context,
VRAM line 43,520 (f16 mask), host tail ~197k cells, graphs off.

| run | engine | result |
| --- | --- | --- |
| P101 | `87e2ac160` (emulation) | copies 10/10, needles 12/12 at B = 8192 and 16384 (page 64): quality holds at 4 % of the host tail |
| P102 | `87e2ac160` | decode dense 5.7, sparse 2.9; 512-token follow-up prefill 79 -> 39 |
| P102c | `ae61c4cf3` | sparse 2.6; one sync per K write still logged |
| P102d | `ae61c4cf3`, `GGML_CUDA_KV_TIER_REDIRECT=0` | 2.5; warning still there (not the redirect) |
| P102e | `d6c6e9f01` | sync gone (0 warnings); decode sparse 4.3 (lookup off and on), with `SINKS=4096` 5.2; prefill 39, with sinks 6.2 |
| P105 | `d6c6e9f01` | 160k: dense 9.7, sparse **18.3 (x1.9)**; code items with lookup 12.8 -> 21.5; needles 12/12, copies 10/10. 245k: copies 9/10, needles 12/12. MTP tail 4 (line 20,992, acceptance 0.55): dense 9.1, sparse 11.5 |
| P106 | `028f606fc` | 160k: dense 9.7, sparse **18.5 (x1.9)**; 245k: 5.7 vs 4.9; 64k: 34.5 vs 29.0 (-16 %); follow-up prefill 160k 107 -> 85, 245k 79 -> 39-44, the same with `NOTRACK` (not the write tracking) |
| P107 | `028f606fc`, `GGML_CUDA_OP_TIMING=1`, 245k | per graph: FLASH_ATTN_EXT 91.8 -> **61.5 ms** (sparse works), but the ternary mat-vecs 2.5-24x slower (17408x5120: 2.6 -> 63.0 ms); total 155.5 -> 183.9 ms. `nvidia-smi` free VRAM wraps at the first sparse decode step: VRAM over-commit (cause in D18) |

- **Verdict so far.** On the real 8 GB card: x1.9 at 160k (P105, P106), quality equal to dense; not yet faster at
  245k (4.9 vs 5.7 with the `028f606fc` warp skip); costs 16 % at 64k, so a default needs a depth threshold; the
  follow-up prefill drop is not the write tracking (P106). P107: the loss at 245k is in ops that sparse does not
  touch, after the card goes over its total VRAM at the first sparse decode step (D18).
  Full records: `../depth-8gb-20261006/experiments/P101.md` to `P107.md`.

## D17 Tile skip at warp granularity (2026-10-11, `028f606fc`)

- **Question.** Can the vec kernel skip 32-cell groups, so 64-cell pages skip on 2-query steps?
- **Gate.** Exactness (op tests).
- **Result.** `FLASH_ATTN_EXT` 3005/3005 on sm_75 (2060, P106). 245k sparse decode 4.3 -> 4.9 tok/s (P102e -> P106);
  160k unchanged (18.3 -> 18.5).
- **Verdict.** Exact; kept. The remaining 245k gap is not in the attention kernel (P107, D18).

## D18 Sparse VRAM: f16 page bounds and a chunked first fill (2026-10-13, `8d5b862fc`)

- **Question.** P107 shows the card going over its VRAM total at the first sparse decode step. What does the sparse
  path allocate there, and can it be made small enough to fit the launcher's budget?
- **Analysis (from the code; 16 attention layers, H_kv 4, D 256, page 64).** Two allocations, both at the first
  sparse op (prefill ops above `MAXQ` leave before the sparse work), neither in the launcher's budget:

  | | 160k (1,753 host pages) | 245k (3,077 host pages) |
  | --- | ---: | ---: |
  | page-bound tables (`cudaMalloc`, kept; f32 max + min, +64 pages headroom) | 227 MiB | 393 MiB |
  | first fill: whole host tail of K as f16 (pool temporary; the pool keeps its high-water mark) | 219 MiB | 385 MiB |

- **Change.** Bounds stored in f16: the K values are f16 at that point (`to_fp16` first), so the max and min are exact
  and the page selection is unchanged (1 KiB per host cell at page 64: 114 / 196 MiB). The first fill in chunks of
  `GGML_CUDA_FA_SPARSE_FILL_CELLS` cells (default 16384): 32 MiB at any depth.
- **Gate (declared before the run, `D18-plan.json`).** `FLASH_ATTN_EXT` op tests all pass; `sparse_edit` track arm
  0 stale ops with `CHECK` (cached bounds vs a full recompute); 160k on the 8 GB-like layout copies 10/10 and needles
  12/12, decode within 3 % of `root-sparse11`; peak VRAM lower than `root-sparse11` in the same arm.
- **Result (2026-10-13 18:12-18:59, RTX 4070, Afterburner profile on).**

  | gate | `root-sparse11` (before) | `root-sparse12` (`8d5b862fc`) |
  | --- | --- | --- |
  | `FLASH_ATTN_EXT` op tests | | 3005/3005 |
  | `sparse_edit` 160k, stale ops (base / edit / again) | | track 0 / 0 / 0; notrack control 0 / 192 / 192 |
  | 160k exact copies / needles | 10/10, 12/12 | 10/10, 12/12 |
  | peak `memory.used` (8 GB-like layout, line 32,768) | 9,747 MiB | **9,356 MiB (-391 MiB)** |
  | mean decode (code / prose / bash) | 25.5 (29.3 / 20.4 / 26.9) | 27.6 (31.6 / 22.0 / 29.0) |
  | cold prefill 159k | 545.6 | 581.4 |

  The memory drop matches the analysis at this depth (host tail 126,720 cells: tables 256 -> 128 MiB, first fill
  248 -> 32 MiB; ~344 MiB expected). Speed: the new arm is faster in decode (+8 %) but also in cold prefill (+6.6 %),
  which never runs the sparse path, so the arms differ by run-to-run spread of that size and no speed change is
  claimed. The new arm's 27.6 equals D10's 27.6.
- **Verdict.** Pass: exact selection, no stale bounds, quality equal, 391 MiB less VRAM, no slowdown. Kept on
  `fa-sparse-proto`. The 8 GB effect at 245k is the 2060 run P110 (`3299a0b4b` = this + `GGML_CUDA_FA_SPARSE_MIN_HOST`,
  margin 475).
- **Receipts.** `docs/receipts/sparse_vram_d18.log`, `docs/receipts/sparse_edit.log` (18:13 block),
  `docs/receipts/sparse_prefill.log` and `.jsonl` (18:26 and 18:43 blocks), `docs/receipts/d18_vram_root-sparse1{1,2}.csv`.

## D19 Whole-context selection, retry at page 64 and B = 16384 (2026-10-13 19:00-19:19)

- **Question.** Does the D11 whole-context selection keep retrieval with smaller pages and twice the budget?
- **Gate.** Same as D11 (declared in chat 2026-10-11): copies 10/10 and needles 12/12 at 160k; then decode at 192k.
- **Setup.** `bench/sparse_whole.sh`, `root-sparse10` (engine `d6c6e9f01`: 64-cell MMA tile map, vec kernel with the
  128-cell tile skip only), `GGML_CUDA_FA_SPARSE=16384,64,1024`, `SINKS=1024`, `FA_TILE_SKIP=1`, graphs off, f16 mask.
  The launcher put the line at 109,056 (D11: 121,344).
- **Result.** Copies 10/10, **needles 11/12**. Mean decode at 192k 18.8 tok/s (21.3 / 15.5 / 19.5), cold prefill 501.
- **Verdict.** Rejected on quality: one needle lost even at 16384 cells (~8.5 % of the context) with 64-cell pages.
  The speed is not a fair measure: this engine has no 32-cell warp skip (D17), and the log shows 1-query decode ops
  (vec kernel), which then cannot skip 64-cell pages. The quality result does not depend on that. Whole-context
  selection is closed; the host-tail form stays (D10, D20).
- **Receipts.** `docs/receipts/sparse_whole.log` (19:00 block), `docs/receipts/sparse_whole.jsonl`.

## D20 Host-tail selection at page 64 on the 12 GB line (2026-10-13 19:19-19:37)

- **Question.** Does the page-64 form (the 8 GB candidate, D10) hold on the 12 GB line at 192k, with the D18 engine?
- **Gate.** Copies 10/10 and needles 12/12 at 160k; decode not below the D11 host-tail arm (25.2).
- **Setup.** `bench/sparse_whole.sh` host-tail arm, `root-sparse12` (`8d5b862fc`), `8192,64,1024`, `FA_TILE_SKIP=1`,
  graphs off, f16 mask; line 112,128 (D11: 121,344).
- **Result.** Copies 10/10, needles 12/12. Mean decode at 192k 24.9 tok/s (28.9 / 20.3 / 25.7), cold prefill 515.
- **Verdict.** Pass on quality; decode equal to the page-256 arm of D11 (25.2) with a 9k-cell lower line. Against
  dense from D11 (22.8, graphs off, another day and line) that is about +9 %, a cross-run figure only. On 12 GB the
  host tail at 192k is small (~80k cells), so the sparse gain is small here; the 8 GB card is where it matters (D16).
- **Receipts.** `docs/receipts/sparse_whole.log` (19:19 block), `docs/receipts/sparse_whole.jsonl`.

## D21 Sparse on the product base, CUDA graphs on, packed mask on (2026-10-13 20:49-21:40 void, 22:02-22:48)

- **Question.** Does the sparse host-tail path (patch 0055 candidate) hold on the product base (0053 + 0054) with the
  product switches: CUDA graphs on (0053 turns them off per graph past the line) and the packed mask on?
- **Gate.** `D21-plan.json`, declared about 20:10 before the run: op tests 0 failures (`GATED_DELTA_NET` 55/55);
  `sparse_edit` track arm 0 stale ops, engaged lines, no "needs an f16 mask" warning for decode; 160k at line 32,768:
  sparse copies 10/10 and needles 12/12, sparse mean decode above dense; minimum free VRAM above 0.
- **Setup.** `product-sparse` `3ab0af3c2` (`product-0054` + the sparse ggml diff of `9d9a968d9`), `root-psparse`
  (bundle-0054 layout, `build-psparse` sm_89), the other session's script `d21_sparse_product.sh`, run by the 4070
  release session. `SPARSE=8192,64,1024 GRAPHS=on PACKED=1`.
- **Void first run.** It started 20:49 and stopped at a power cut at about 21:40 in the sparse-prefill step. The run
  was repeated from the start at 22:02, after the memory overclock was checked under load (11751 MHz).
- **Result (22:02-22:48).**
  - Op tests: `FLASH_ATTN_EXT` 3005/3005, `GATED_DELTA_NET` 55/55.
  - `sparse_edit`: track arm 0 stale ops on all three requests; the no-track control 272 stale ops (the check works);
    engaged lines 1 per arm. One "needs an f16 mask" line, at 0.11 s (warmup, a prefill op), not from decode;
    `c8bbb1898` (D22) logs it only for decode-sized ops.
  - 160k: dense mean decode 13.8 tok/s (15.3 / 11.3 / 14.6), copies 10/10, needles 12/12; sparse 27.5 (31.1 / 23.2 /
    28.2), copies 10/10, needles 12/12, 12 engaged lines. Cold prefill 571 (dense) and 605 (sparse).
  - VRAM: peak used 9,140 MiB, minimum free 2,871 MiB. 1,820 CUDA-graph lines in the sparse arm's server log.
  - CPU builds of other branches ran during parts of the run (logged as NOTE lines in the receipt; the speed gate's
    margin is 2x).
- **Verdict.** Pass. Sparse is 2.0x dense at 160k on the product base with graphs and the packed mask on, and keeps
  the copies and needles.
- **Receipts.** `docs/receipts/sparse_product_d21.log`, `docs/receipts/d21_vram.csv`, `docs/receipts/sparse_edit.log`
  (22:02 block), `docs/receipts/sparse_prefill.log` + `.jsonl` (22:15 block; the 21:03-21:40 block is the void run).

## D22 int8 page bounds, rounded outward (2026-10-13 22:49 - 10-14 00:14)

- **Question.** Can the page bounds be int8 (one f16 scale per page and head, max rounded up and min rounded down, so
  each page's score stays an upper bound) to halve the VRAM reserve (514 B per host cell at page 64 instead of 1 KiB)
  without losing quality or speed? Background: P122 / P123 on the 2060 showed the f16 reserve costs about 14k VRAM
  cells, -7 % at 64k.
- **Gate.** `D22-plan.json` (declared before the run): `sparse_edit` track arm 0 stale ops; 160k copies 10/10 and
  needles 12/12; 245k copies and needles not below the f16 arm; decode within 3 % of the f16 arm at 160k; peak VRAM
  lower than the f16 arm.
- **Setup.** int8: `product-sparse` `c8bbb1898` (`root-psparse8`); f16: `3ab0af3c2` (`root-psparse`, D21). Graphs on,
  packed mask on, line 32,768, `8192,64,1024`, the other session's `d22_int8_bounds.sh`, run by the 4070 release
  session at the product memory clock.
- **Result.**

  | | int8 bounds | f16 bounds |
  | --- | ---: | ---: |
  | `sparse_edit` stale ops, track arm | 0 / 0 / 0 | 0 (D21) |
  | "needs an f16 mask" lines | 0 | 1 (warmup, D21) |
  | 160k mean decode | 27.3 tok/s | 27.5 (D21) |
  | 160k copies / needles | 10/10, 12/12 | 10/10, 12/12 (D21) |
  | 245k mean decode | 24.5 | 23.0 |
  | 245k copies / needles | 9/10, 12/12 | 9/10, 12/12 |
  | 245k peak used / min free | 9,164 / 2,847 MiB | 9,309 / 2,702 MiB |

  `FLASH_ATTN_EXT` 3005/3005. The 245k copy miss is the same item in both arms (`_pydecimal.py` `_convert_other`,
  at 44 % of the context). D22 has no dense arm at 245k, so whether dense also misses it is open: a dense control is
  queued.
- **Verdict.** Pass on every gate. int8 bounds: -0.7 % at 160k (inside the 3 % gate), +6.5 % at 245k, 145 MiB less
  peak at 245k, the same quality. Half the reserve gives the 2060 back about 7k VRAM cells (P127 measures it).
- **Receipts.** `docs/receipts/sparse_int8_d22.log`, `d22_vram_*.csv`, `sparse_edit.log` (22:50 block),
  `sparse_prefill.log` + `.jsonl` (23:01, 23:17, 23:45 blocks).

## D22b Dense control at 245k (2026-10-14 01:10-01:42)

- **Question.** Is D22's 245k copy miss (`_pydecimal.py` `_convert_other`, both bound formats) a model limit or a
  sparse loss?
- **Setup.** `root-psparse8` (`c8bbb1898`), dense arm (no sparse switches), graphs on, packed mask on, line 32,768.
  Stock memory clock (the OC profile was not applied after the 00:31 Windows-update reboot).
- **Result.** Copies 10/10 (including `_convert_other`), needles 12/12, mean decode 8.8 tok/s (10.0 / 6.7 / 9.7).
- **Verdict.** The miss is a sparse loss. On the 2060, P105 (older build) shows the same pattern with another
  mid-context item.
- **Receipts.** `docs/receipts/sparse_int8_d22.log` (01:10 block), `docs/receipts/sparse_prefill.log` + `.jsonl`.

## D22c Budget at 245k (2026-10-14 02:09-03:07)

- **Question.** Does a larger budget fix the 245k miss?
- **Setup.** `root-psparse8`, int8 bounds, P 64, R 1024, B 16384 and B 12288; graphs on, packed mask on, line
  32,768; stock memory clock.
- **Result.** B 16384: copies 10/10, needles 12/12, 18.6 tok/s. B 12288: 10/10, 12/12, 20.8 tok/s. (B 8192 at the
  same clock, q3_0 run Q05b: 9/10, 27.4 tok/s.)
- **Correction.** The first summary lines in the receipt said B 16384 missed `_convert_other`: they read the last 40
  lines of the shared jsonl, which still held the B 8192 run. The per-run item lines show 10/10; a correction line
  is in the receipt. Lesson: split a shared jsonl by run before a summary.
- **Verdict.** A budget of 12288 (about 5.8 % of the 212k-cell host tail) is enough at 245k.

## D23 Per-head normalized page ranking (2026-10-14 03:08-03:53)

- **Question.** Is the miss a ranking problem? `GGML_CUDA_FA_SPARSE_NORM=1` ranks each page by each Q head's bound
  relative to that head's best page (`product-sparse` `8d6e0d3f4`).
- **Gate.** `plans/D23-plan.json` (committed before the run; the decode gate was marked not applicable because of
  the stock clock).
- **Result.** 245k at B 8192: copies 9/10 (the same `_convert_other` miss), needles 12/12, 24.5 tok/s, 14 norm lines.
  160k: 10/10, 12/12, 27.3.
- **Verdict.** Fail at 245k. By the rule agreed before the run, the default becomes the budget fraction:
  `GGML_CUDA_FA_SPARSE_FRAC` = 1/16 (B = max(8192, host tail / 16)), in the engine of `product-0055` `4de618549`
  (PR #56); NORM is removed.
- **Note.** D23's decode at the stock clock (24.5 / 27.3) equals D22's at the OC clock: decode at this depth is
  bound by PCIe, not by the memory clock.

## D24 Page-rank trace of the missed function (2026-10-14 03:53-04:11)

- **Question.** Where do the pages of `_convert_other` rank, per layer, with plain and with normalized ranking?
- **Setup.** `product-sparse` `44e18f79c` (int8 bounds, NORM switch, `GGML_CUDA_FA_SPARSE_TRACE`), the function's
  KV cells 107,391-107,531 (from `bench/code_needle.py --span`), one item at 245k, B 8192 (about 128 pages kept, plus
  the last 1024 cells).
- **Result.**
  - Plain: 720 trace lines, 223 with the function's best page dropped. Mean rank per layer 42-130 in layers 2-12
    (near or inside the cut of about 128), but 324 / 408 in layers 0 / 1 and 187-232 in layers 13-15.
  - NORM: 2,320 lines, 1,670 dropped, mean rank 153-682 in every layer. Normalized ranking moves the function's
    pages down, not up.
  - The item stays wrong in both runs.
- **Verdict.** The miss is budget plus looseness in the first and last layers, not a score blind spot: a cut of about
  192 pages (B 12288) holds the target in most ops, which matches D22c. Normalized ranking is worse, which matches
  D23. A per-layer budget (more pages in layers 0-1 and 13-15) is a possible later gain.
- **Receipts.** `docs/receipts/sparse_trace_d24.log`.

