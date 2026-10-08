# What we took from HyperQwen, and what we measured (2026-10-08)

[syv-ai/HyperQwen](https://github.com/syv-ai/HyperQwen) serves a model with the same attention shape as Bonsai 2 27B
(24 query heads, 4 KV heads, head size 256) on vLLM. We read its list of speed techniques and tested each one that
applies to this engine and this card (RTX 4070 12 GB). Decisions follow the measurement, not the idea.

| HyperQwen technique | What we did | Result | Decision |
| --- | --- | --- | --- |
| Draft from the prompt (copy text that is already in the context) | Lookup drafter in front of the MTP head, its own draft limit (patch 0039) | File rewrites 117 -> 352 tok/s at 4k, 63 -> 164 at 130k; new text unchanged; same output (`receipts/lookup_ab.jsonl`) | Shipped, on by default (`bundle-20261008-lookup`) |
| SSE keep-alive | A `: keep-alive` comment every 15 s while the server is silent (layer) | Long prefills no longer drop through proxies and tunnels | Shipped |
| Int8 score step in prefill attention | Built for q8_0 K, head 256 (`docs/INT8_ATTENTION.md`) | Kernel 12% faster (about +6% prefill at 128k); KL 0.000314, above the 0.00017 gate | Stopped |
| Int8 activations for the prefill matmuls | Already the case: the PTQ1_0 prompt matmuls run on int8 activations (MMQ) | - | Nothing to do |
| Calibrated 40k-token draft vocabulary | Not built. Estimate from the Q4_0 head A/B, which removes about the same bytes per draft token (~200 MB): +3% at 4k, 0 at 32k, -1.5% at 100k, acceptance 1.5-5 points lower (`receipts/head_ab.log`) | Expected 1-3% at short context, nothing at depth | Not worth the engine change on this card |
| 4-bit / 2-bit KV cache for the long window | q4_0 K/V measured before: 1 flipped top token in 48 against 1 in 160 for q8_0 (`docs/QUALITY.md`) | The tiered cache gives 262k at q8_0 | Not adopted (q8_0 stays) |
| Smaller draft head | Q4_0 MTP head on 12 GB (`bench/head_ab.sh`) | +6,656 positions in VRAM, decode +3% at 4k, -1.5% at 100k, lower acceptance, same text | Not adopted on 12 GB (it stays the 8 GB choice) |
| Batch mode vs single-user mode | This serve is one slot, one user | - | Not applicable |

What the measurements found on the way: the int8 work measured prefill by depth, and that showed a fixed extra cost
once a prompt passes the tiered cache's VRAM line. Its cause was the writes of the new K/V rows to system RAM, and
patch 0041 removes it (`bundle-20261008-tier`: one 258k prompt 369 -> 436 tok/s, same output).
