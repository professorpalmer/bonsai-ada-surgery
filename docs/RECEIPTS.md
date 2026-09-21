# Receipts

Same sheet for every card: Ternary Bonsai 2 27B `PTQ1_0` (1.75 bpw, 5.95 GB), PrismML
llama.cpp fork, `-fa on`, one slot, `--jinja`. Trained context **262,144**. Shipped 12 GB
recipe is **96k / q8_0**; 12 GB full window is **262k / q4_0** (`BONSAI_SPEC=0`); 16 GB+ is
**262k / q8_0**. Run `python bench/receipt.py` and add a column.

## The bundle, 2026-09-20 (RTX 4070 12 GB, stock clocks, q8_0 KV)

Final numbers for the shipped 20-patch stack (`bin/`, commit `0974424` on PrismML `9a9394a`)
against PrismML's official Windows CUDA release binaries, same GGUF, same flags, same hour.
Headline window: **262,144 trained max**, served here as **96k / q8_0** (quality default on
12 GB). Everything below is q8_0 K/V, 96k unless stated; the older sections of this page are
the q4_0 / 262k receipts from the kernel work.

`llama-bench`, `bench/head_to_head.py`, 2 rounds x 3 reps (`artifacts/h2h_release_4070.json`):

| | PrismML | bundle |
| --- | ---: | ---: |
| pp512 | 635 | 1311 |
| pp2048 | 632 | 1304 |
| tg128 | 54.3 | 67.6 |
| SM clock / power during tg | 2775 MHz / 178 W | 2670 MHz / 197 W |

Served, `bench/served_depth.ps1` (server `timings`, 400-token answers, three prompts, filler
sized with `/tokenize`; `artifacts/eval/served_*.txt`):

| decode tok/s | fresh | 32k deep | 64k deep | 100k deep | VRAM in use |
| --- | ---: | ---: | ---: | ---: | ---: |
| PrismML, 128k/q8_0 | 54.0 | 40.7 | 31.9 (96k window) | 26.8 | 11.3 GB |
| bundle, no draft, 128k/q8_0 | 68.3 | 49.1 | | 30.3 | 10.9 GB |
| bundle + draft, 128k/q8_0 | 96.7 | 30.1 (paging) | | 12.6 (paging) | 11.96 GB |
| bundle + draft, 64k/q8_0 | | 47.3 | | | 9.6 GB |
| bundle + draft, 96k/q8_0 | 101.2 | 45.3 | 27.2 | | 10.8 GB |
| bundle + draft, 128k/q4_0 | 99.9 | 44.0 | 26.3 | | 9.9 GB |
| bundle + draft, 262k/q4_0 | 94.0 | 28.6 (paging) | 16.4 (paging) | | 11.96 GB |
| **bundle + draft to 24k, 96k/q8_0 (shipped)** | **100.7** | **47.6** | **36.9** | | 10.8 GB |
| shipped, with the thinking budget on (default) | 96.8 | | | | |

MTP head A/B, same PTQ1_0 trunk, 96k / q8_0, draft-mtp n-max 2, think off, sudo probe
(3 prompts x 3 x 400 tokens; `artifacts/eval/mtp_head_ab.json`):

| head | code | prose | bash | mean | accept | VRAM |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Qwen 3.8 teacher Q4_K graft (`mtp-lean`) | 108.2 | 80.1 | 91.1 | 93.5 | 66.3% (1594/2403) | 11061 |
| **ProCreations on-policy Q8 (`mtp-procreations`, default)** | **114.5** | 79.5 | **98.3** | **97.1** | **70.6%** (1705/2416) | 11153 |

+3.9% mean tok/s, +4.3 pp acceptance, +92 MiB. Strip of the trained graft hashes equal the
official PTQ1_0 file. Greedy draft-on vs draft-off matches on code and shows the same close-token
mmap flip the teacher graft already had (`GGML_CUDA_BATCH_INVARIANT` does not make every
near-tie identical). Their combined PQ2 GGUF was not used.

Prefill through the server on a 32k prompt: PrismML 578 tok/s (55 s to first token), bundle
1012-1072 tok/s (30-32 s). Two rows carry the lesson of the day: anything at 11.96 GB in use
runs the fresh probe at full speed and then pages at depth.

Tool calls, `bench/toolcall_stress.py`, 3 tasks x 3 runs per arm, thinking off
(`artifacts/eval/toolcall_stress.json`): native XML through the server grammar parsed **9/9**
(66.9 tok/s); Hermes JSON written in content parsed **1/9** (77.5 tok/s, 4 of 9 hit the
9,000-token cap). KV precision, `bench/kv_kl_sweep.ps1`, 16k-token chunks vs f16 KV
(`artifacts/eval/kl_*_16k.log`): q8_0 KL 0.00017 / top-1 agreement 99.38%; q4_0 KL 0.00218 /
97.93%; q8_0 K + q4_0 V 0.00094 / 98.59% (CPU fallback, 10x slower). Method and reading for
both: [`QUALITY.md`](QUALITY.md).

## Decode speed by context depth (tok/s)

| depth | RTX 3060 12 GB, stock Prism build (community) | RTX 4070 12 GB, stock Prism build | RTX 4070, this patch + GDDR6X +1500 |
| ---: | ---: | ---: | ---: |
| fresh (0) | 26.1 | 50.7 | 65.6 (+29%) |
| 7k | 24.4 | 47.1 | 59.8 (+27%) |
| 12k | 21.9 | 44.7 | 56.7 (+27%) |
| 35k | 17.8 | 36.5 | 44.6 (+22%) |
| 77k | 13.0 | 27.3 | 32.2 (+18%) |

The two 4070 columns are the same card, same GGUF, same flags, same morning: only the
`ggml-cuda.dll` (official Prism release vs this branch) and the memory clock change.
Percentages are against the stock build. The gain shrinks with depth because the decode
patches touch the weight GEMVs; attention over the KV cache is an untouched, growing
share of the token at depth (see below).

## Prefill (tok/s, 2048-token prompt)

| context depth | RTX 3060 (community) | RTX 4070, stock Prism build | RTX 4070, this patch + +1500 |
| ---: | ---: | ---: | ---: |
| 2k | 295 | 588 | 1275 (**2.17x**) |
| 35k | 243 | 473 | 847 (1.79x) |

Prefill takes the int8 tensor-core MMQ path. Stock PTQ1_0 ran it at half the speed of
PQ2_0 because its tile table was capped at 64 columns and its tile loader was
branch-divergent (see `surgery/ADA4070_PTQ1.md`, cut 7). Fixing both makes PTQ1_0 prefill
at PQ2_0 speed. Memory clock does not matter here; llama-bench pp2048 at +1500 went
630 -> 1304 from the kernel change alone.

## Power

3060 pinned 149 of 150 W. 4070 pinned at its 200 W cap during fresh decode (190 W avg
at +1500), 182-197 W at depth. tok/s per watt at the fresh end: 3060 0.158, 4070 stock
build 0.271, patched +1500 0.346.

## What context costs (resident VRAM, server process)

| window | 3060 (community) | 4070, this build |
| ---: | ---: | ---: |
| 64k | 7.3 GB | 7.1 GB |
| 128k | 8.8 GB | 8.6 GB |
| 192k | 10.2 GB | 10.0 GB |
| 262k | 11.7 GB | 10.9 GB (11.6 of 12.0 GB in use incl. desktop) |

~1.47 GB per 64k of q4_0 KV on both cards; the whole native 262k window fits on 12 GB.
Decode speed does not depend on the window size, only on how deep the conversation
actually is (62.9 tok/s at a 64k window vs 61.5 at 262k, same 1.6k prompt).

## Live server (1611-token prompt, `/completion`, 256 tokens)

| | 3060 (community, shorter prompt) | 4070 this patch, before cut 7 (+1500) | 4070 this patch, cuts 1-7 (+1500) |
| --- | ---: | ---: | ---: |
| prefill tok/s | 295 | 585 | **1159** |
| first token | 0.6 s | 2.75 s | **1.39 s** |
| decode tok/s | 26.1 | 62.1 | 61.5 |

262k window resident either way; same numbers at the 64k window. The stock Prism build
was not measured through the live server (its prefill leg above, 588 tok/s at 2k, is the
same MMQ path the pre-cut-7 server column runs).

## Reading the depth curve

Both cards lose ~46% from fresh to 77k deep. At 77k the q4_0 KV read is only about
1.4 GB per token (16 attention layers x 8 KV heads x 128 x 2 x 0.5625 B x 77k), which is
~3 ms at 4070 bandwidth on top of a 15 ms token, i.e. the model *should* still be doing
~50 tok/s there. It does 32. The flash-attention decode kernel over quantized KV is far
from bandwidth-bound; that is the next kernel to open up for deep-context work, and
the 3060 has the same ratio so it is not an Ada quirk.

## Raw data

- `artifacts/receipt_stock_prism_build.json` (4070, official Prism CUDA release binaries)
- `artifacts/receipt_oc1500_v2.json` (4070, this build, cuts 1-7, +1500 memory)
- `artifacts/receipt_stock.json`, `artifacts/receipt_oc1500.json` (this build before
  the prefill work: stock clocks 58.1 fresh / +1500 64.7 fresh, prefill 600 / 617)
- community 3060 sheet: [@sudoingX, 2026-09-18](https://x.com/sudoingX)
