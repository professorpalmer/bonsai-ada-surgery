# Depth research: report (2026-10-10 to 2026-10-14)

Speed past the VRAM line on one RTX 4070 12 GB (PCIe 4.0), with the RTX 2060 SUPER 8 GB (PCIe 3.0) runs from #21 /
#22. Paired arms on the same binary where possible; gates declared before results (see README for where).
Experiment entries: `EXPERIMENTS.md`; machine-readable: `runs.jsonl` (with `gpu_h`, RTX 4070 hours from receipt timestamps: 17.4 h for this folder).

## Bottom line

1. **The largest gain was a configuration fault, not a kernel.** The tier prefetch (copy engine moves the next
   attention op's host rows while the current op computes) only ran without a CUDA graph, and the launcher keeps CUDA
   graphs on. Found from D07 (graphs off beat the shipped setup by 15 % at 192k), isolated and gated as patch 0053 (shipped in bundle-20261011, 2026-10-13):
   +25 % decode at 192k on 12 GB, +8 to +16 % past the line on 8 GB, nothing lost below the line. Isolation, gates and
   release: `docs/research/release-20261011/`.
2. **Sparse reads of the host tail shipped as an opt-in for 8 GB: patch 0055, bundle-20261014, `BONSAI_SPARSE=1`.**
   Gated on both cards with CUDA graphs on (0053 turns them off per graph past the line) and the packed mask on:
   RTX 2060 SUPER 160k 10.6 -> 17.5 tok/s (1.65x), 245k 6.3 -> 13.7 (2.17x), exact copies and needles equal to dense
   at 160k / 200k / 245k (P135, P136); RTX 4070 8 GB-like line 160k 14.4 -> 24.1 (R05b), 245k 8.8 -> 20.4 (R04).
   What it took:
   - the kernels skip what the mask hides at the page's own granularity (D06, D10, D17);
   - the sparse-only VRAM counted in the launcher's line: f16 then int8 page bounds rounded outward, 514 B per host
     cell, a chunked first fill, 64 MiB headroom from a 245k trace (D18, D22, release-20261014);
   - a budget that grows with depth: max(12288, host tail / 16). A fixed 8192 lost an exact copy at 245k, 1/16 alone
     lost one at 200k on a 20-item set (D22c, R04b-R04d);
   - below `MIN_HOST` the op is the dense op, prefetch included (P118 routing fix).
   Opt-in, not default: the bounds reserve shortens the VRAM line, which costs ~8 % at 64k on the 2060 (P123, P127)
   and ~2.6 % on the 4070 (D26a). The engine itself adds nothing at an equal line (D26a).
3. **The kernel must skip what the mask hides, or sparse is slower than dense.** The first sparse builds read every
   masked host tile in place (D07, D09, D10: 9.1 vs 13.6 tok/s), because draft-verify steps run the MMA kernel, which
   had no skip. Each kernel path needs its own skip at the page's own granularity (D06, D10, D17).
4. **Quality fails first where selection is aggressive:** sparse prefill (D10: 8/10 copies) and selection over the VRAM
   part (D11: 7/12 needles) are rejected at the tested settings.
5. **Chunked gated-delta-net prefill shipped: patch 0054, bundle-20261013** (D14): prefill +3 to +7 % on RTX 30 / 40,
   decode unchanged, perplexity +0.024 %; HumanEval 158 vs 160 (two long-thinking flips, trajectory drift); not taken
   on RTX 20 (P116).
6. **What did not help the sparse path:** per-head normalized ranking (D23: it moves the needed pages down), a
   per-layer budget (D25: the middle layers carry mid-context items too), two-level bounds in host memory (D26c / D26e:
   98.9 % overlap at 256-cell superpages, but the per-token PCIe read cancels the line it saves).
7. **No gain:** V skip (D12), a larger prefill micro-batch (D13: 512 is best), a third-party template for tool work
   (D15). **KL at depth (D05):** one chunk measured (B = 8192: mean KLD 0.0030, same top-1 97.7 %); the longer runs froze the PC and produced the RAM guard rule.

## Promoted / rejected

| item | status |
| --- | --- |
| CUDA graphs off past the line (patch 0053) | **shipped**: bundle-20261011 (2026-10-13), all gates passed on both cards |
| `LLAMA_SLOT_KEEP_TOKENS` (D01) | prototype; blocked on the two-slot cost (D02) |
| sparse host-tail decode (D10-D22, release-20261014) | **shipped, opt-in**: patch 0055, bundle-20261014, `BONSAI_SPARSE=1` on 8 GB |
| sparse prefill (D10), whole-context selection (D11 page 256, D19 page 64 / B 16384) | rejected (D19: needles 11/12) |
| chunked gated-delta-net prefill (D14) | **shipped**: patch 0054, bundle-20261013 |
| normalized ranking (D23), per-layer budget (D25), two-level bounds (D26) | rejected |
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
6. **Round 6 (2026-10-13):** the 245k loss traced to VRAM over-commit (P107); sparse memory cut (D18);
   whole-context selection closed (D19); page 64 holds on 12 GB (D20).
7. **Round 7 (2026-10-13 night to 10-14):** sparse on the product base with graphs and the packed mask (D21); int8
   bounds (D22); the 245k miss traced to budget, not ranking (D22b-D24); per-layer budget and two-level bounds
   rejected (D25, D26); line vs engine overhead split (D26a); release gates and publish (release-20261014).

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
- **A gate that the dense arm cannot pass is not a gate.** R04 said "copies 10/10"; dense itself missed an item at 200k
  (R04b). Compare sparse to dense on the same items, and use 20 items where a single miss decides.
- **Check that a debug run's logs exist before reading its verdict.** D26c looked void: a shell escape (`\$NAME` in
  double quotes) put the server logs one directory up.
- **Plan files.** Gates were declared in chat or on issues, not frozen in `<ID>-plan.json`. Write the plan file
  first next time.
- **RAM.** Estimate a run's host memory before starting it. Keep `tools/ramguard.ps1` in every heavy script. KL
  divergence with this 248k vocab only at 16k context or less.

## Open

- D02: the -16 % of a second slot.
- Sparse default-on needs a way to keep the line at shallow depth (the reserve is unused until the tail grows). P137
  (D26a on PCIe 3.0) shows how much of the 2060's 7-8 % is per cell; a smaller bound format is worth it only then.
- Engine: a separate pool per context when a second model is loaded (the launcher works around it since #75).
- D12: V skip on top of patch 0053, if attention ever dominates.
