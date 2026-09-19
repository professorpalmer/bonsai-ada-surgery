# Receipts

Same sheet for every card: Ternary Bonsai 2 27B `PTQ1_0` (1.75 bpw, 5.95 GB), PrismML
llama.cpp fork, `-fa on`, q4_0 KV cache, one slot, `--jinja`. Run `python bench/receipt.py`
and add a column.

## Decode speed by context depth (tok/s)

| depth | RTX 3060 12 GB, stock Prism build (community) | RTX 4070 12 GB, stock Prism build | RTX 4070, this patch, stock clocks | RTX 4070, this patch, GDDR6X +1500 |
| ---: | ---: | ---: | ---: | ---: |
| fresh (0) | 26.1 | 50.9 | 58.1 | 64.7 |
| 7k | 24.4 | - | 53.8 | 59.0 |
| 12k | 21.9 | - | 51.1 | 55.4 |
| 35k | 17.8 | - | 40.8 | 43.7 |
| 77k | 13.0 | - | 30.0 | 31.9 |

Prefill (tok/s): 3060 295 at 2k / 243 at 35k; 4070 patched 600 at 2k / 482 at 35k
(617 / 498 at +1500). Prefill is compute-bound and untouched by this work (the patch
targets the batch-1 GEMV; larger batches take the MMQ path).

Power: 3060 pinned 149 of 150 W. 4070 pinned at its 200 W cap during fresh decode
(189 W avg), 157-173 W at depth where attention kernels are latency-bound and let the
card breathe. tok/s per watt at the fresh end: 3060 0.158, 4070 stock-build ~0.27,
patched 0.308, patched +1500 0.343.

## What context costs (resident VRAM, server process)

| window | 3060 (community) | 4070, this build |
| ---: | ---: | ---: |
| 64k | 7.3 GB | 7.1 GB |
| 128k | 8.8 GB | 8.6 GB |
| 192k | 10.2 GB | 10.0 GB |
| 262k | 11.7 GB | 11.0 GB (11.6 of 12.0 GB in use incl. desktop) |

~1.47 GB per 64k of q4_0 KV on both cards; the whole native 262k window fits on 12 GB.
Decode speed does not depend on the window size, only on how deep the conversation
actually is (62.0 tok/s at a 64k window vs 62.1 at 262k, same 1.6k prompt).

## Live server (1611-token prompt, `/completion`, 256 tokens)

4070 +1500, 262k window: prefill 585 tok/s, first token 2.75 s (= the whole prompt),
decode 62.1 tok/s. Same at the 64k window.

## Reading the depth curve

Both cards lose ~46% from fresh to 77k deep. At 77k the q4_0 KV read is only about
1.4 GB per token (16 attention layers x 8 KV heads x 128 x 2 x 0.5625 B x 77k), which is
~3 ms at 4070 bandwidth on top of a 15 ms token, i.e. the model *should* still be doing
~50 tok/s there. It does 32. The flash-attention decode kernel over quantized KV is far
from bandwidth-bound; that is the next kernel to open up for deep-context work, and
the 3060 has the same ratio so it is not an Ada quirk.

## Raw data

- `artifacts/receipt_stock.json`, `artifacts/receipt_oc1500.json` (4070, this build)
- community 3060 sheet: [@sudoingX, 2026-09-18](https://x.com/sudoingX)
