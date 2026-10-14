# Depth research: report (2026-10-10 to 2026-10-11)

Speed past the VRAM line on one RTX 4070 12 GB (PCIe 4.0), with the RTX 2060 SUPER 8 GB (PCIe 3.0) runs from #21 /
#22. Paired arms on the same binary where possible; gates declared before results (see README for where).
Experiment entries: `EXPERIMENTS.md`; machine-readable: `runs.jsonl` (with `gpu_h`, RTX 4070 hours from receipt timestamps: 17.4 h for this folder).

## Bottom line

1. **The largest gain was a configuration fault, not a kernel.** The tier prefetch (copy engine moves the next
   attention op's host rows while the current op computes) only ran without a CUDA graph, and the launcher keeps CUDA
   graphs on. Found from D07 (graphs off beat the shipped setup by 15 % at 192k), isolated and gated as patch 0053 (shipped in bundle-20261011, 2026-10-13):
   +25 % decode at 192k on 12 GB, +8 to +16 % past the line on 8 GB, nothing lost below the line. Isolation, gates and
   release: `docs/research/release-20261011/`.
2. **Sparse reads of the host tail keep retrieval at 4-6 % of the tail, and give 2x decode on an 8 GB-like layout**
   (D10: 13.6 -> 27.6 tok/s at 160k, copies 10/10, needles 12/12, page 64 with a 64-cell MMA tile map). The page size
   matters for exact copies (256 misses one function twice). On the real 8 GB card: 1.9x at 160k, not yet faster at
   245k (D16). Causes found: the vec kernel skip granularity (fixed, D17) and ~780 MiB of sparse-only VRAM at 245k
   outside the launcher budget, which pushes the card over its total (P107; cut to ~230 MiB in D18: 4070 gates pass,
   -391 MiB peak at 160k; 2060 run P110 pending). Not in a release: it needs CUDA graphs off and the f16 mask.
3. **The kernel must skip what the mask hides, or sparse is slower than dense.** The first sparse builds read every
   masked host tile in place (D07, D09, D10: 9.1 vs 13.6 tok/s), because draft-verify steps run the MMA kernel, which
   had no skip. Each kernel path needs its own skip at the page's own granularity (D06, D10, D17).
4. **Quality fails first where selection is aggressive:** sparse prefill (D10: 8/10 copies) and selection over the VRAM
   part (D11: 7/12 needles) are rejected at the tested settings.
5. **Chunked gated-delta-net prefill: +3-6 % prefill, quality held on retrieval, HumanEval 158 vs 160** (D14). The
   two flips are long-thinking items; the perplexity gate passed (+0.024 %, 2026-10-13): promoted as patch 0054.
6. **No gain:** V skip (D12), a larger prefill micro-batch (D13: 512 is best), a third-party template for tool work
   (D15). **KL at depth (D05):** one chunk measured (B = 8192: mean KLD 0.0030, same top-1 97.7 %); the longer runs froze the PC and produced the RAM guard rule.

## Promoted / rejected

| item | status |
| --- | --- |
| CUDA graphs off past the line (patch 0053) | **shipped**: bundle-20261011 (2026-10-13), all gates passed on both cards |
| `LLAMA_SLOT_KEEP_TOKENS` (D01) | prototype; blocked on the two-slot cost (D02) |
| sparse host-tail decode, page 64, 64-cell tile map (D10) | candidate for 8 GB; 1.9x at 160k on the 2060; 245k waits on D18 |
| sparse prefill (D10), whole-context selection at page 256 (D11) | rejected at tested settings (retry of D11 at page 64 / B 16384 queued) |
| chunked gated-delta-net prefill (D14) | **promoted**: patch 0054 (PR #40, merged); perplexity +0.024 %; 2060 sm_75 check passed (P116); bundle pending |
| V skip (D12), ubatch > 512 (D13), third-party template (D15) | rejected |

## Order of the work

1. **Round 1 (2026-10-10 morning):** side-request re-read diagnosed and fixed in a prototype (D01); two-slot cost
   measured (D02).
2. **Round 2 (2026-10-10 midday):** sparse reads in emulation; quality holds at B = 8192, page 64 (D03, D04); the KL run
   froze the PC twice (D05, void).
3. **Round 3 (2026-10-10 afternoon/evening):** exact tile skip in the vec kernel (D06); first fast builds, no speed
   (D07); bounds tracking proven with the CHECK mode (D08).
4. **Round 4 (2026-10-11 night):**
   - sync removed;
   - op timing (D09);
   - tile maps and page size on an 8 GB-like layout: the 2x result (D10);
   - whole-context selection rejected (D11);
   - chunked gated-delta-net port (D14).
5. **Round 5 (2026-10-11 morning):** V skip, ubatch (D12, D13); 8 GB card results and the warp-level skip (D16, D17).
6. **Round 6 (2026-10-13):** the 245k loss traced to VRAM over-commit (P107); sparse memory cut (D18).

## Lessons for the next model

- **Count every device allocation of a new path in the VRAM budget.** The 245k sparse loss (P107) was not in the
  kernel: ops that sparse does not touch got 2.5-24x slower once the card went over its total. Op timing finds this
  shape (slow ops that did not change); a VRAM trace across the first decode step confirms it.
- **Measure before building.** The op timing (D09) and a plain graphs-off arm (D07) explained more than the kernel
  prototypes did. Next time, run a graphs on/off and per-op timing pair at depth first.
- **Every new path needs a "did it engage" log line.** The chunked gated-delta-net kernel ran zero times in the first
  A/B (D14), and the sparse path was invisible in the server log at INFO level. Make such lines WARN or always on.
- **Test the 8 GB card early.** The 8 GB-like layout on the 4070 does not reproduce the 2060's decode shape: MTP
  tail 1 gives 2-query steps that run a different kernel.
- **Plan files.** Gates were declared in chat or on issues, not frozen in `<ID>-plan.json`. Write the plan file
  first next time.
- **RAM.** Estimate a run's host memory before starting it. Keep `tools/ramguard.ps1` in every heavy script. KL
  divergence with this 248k vocab only at 16k context or less.

## Open

- D02: the -16 % of a second slot.
- D18: 4070 gates passed; the 2060 run (P110: P107 on `3299a0b4b`, margin 475); then the launcher counts the sparse
  fixed cost (host cells x 1 KiB x 64 / page + 36 MiB) and the 160k follow-up prefill is checked again.
- D16: a depth threshold for sparse (it costs 16 % at 64k on the 2060).
- D11 retry: whole-context selection at page 64, B = 16384 (`root-sparse10`).
- D12: V skip on top of patch 0053, if attention ever dominates.
