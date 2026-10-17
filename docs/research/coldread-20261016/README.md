# Cold read-in on 8 GB, 2026-10-16

Goal (issue #138): make deep context usable on 8 GB. After bundle-20261016 the RTX 2060 SUPER reads a cold 64k prompt
in ~206 s, 128k in ~595 s and 245k in ~1,695 s (P143 / P150). A fit of the prefill rates gives ~2.4 ms per token of
fixed work (PTQ1_0 matmul ~70 %, GDN, the rest) plus attention that grows with depth: the fixed part alone is ~310 s
at 128k. The plan, the scoreboard and the four tracks are on #138:

| track | what | status |
| --- | --- | --- |
| T1 avoid | persistent prefix cache on disk: save the KV + GDN / conv states, restore in seconds | **T1-b pass** (4070: 245k in 2.2 s instead of 468 s; 2060 P153: 5.2 s instead of 28 min); launcher switch `BONSAI_SLOT_SAVE_PATH` merged; MTP draft-context sidecar (product-slotdraft 303f01131) passes T1-h, P158 on the 2060 next |
| T2 exact speed | FA prefill tiles, PTQ1_0 MMQ tuning, op fusion | T2a not exact as built (waits for P154 on the 2060); T2b is a control on the 4070, the real test is sm_75 |
| T3 sparse prefill | block-sparse attention for prompt chunks from the page bounds | closed as a default: 1.22x cold 245k on the 2060 (P159), but loses n24 vaults 14 / 15 against the product dense reference on the 4070 (G2); opt-in on the kernel fork |
| T4 fewer tokens | token selection before the full pass | feasibility |

Each plan was written before its run (the plan comments on #138 carry the times). Results: [EXPERIMENTS.md](EXPERIMENTS.md).
Scripts as run: `scripts/` (user paths replaced by `<user>`). The 2060's runs (P-numbers) are logged on #138 / #105.
