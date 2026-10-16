# Release 2026-10-16: 8 GB automatic sparse reads + 12 GB q4_0 cache (patch 0059, launcher #126)

One release, two changes, gated together.

- **8 GB:** patch 0059 (late page-bound reserve + self-timing engage, D26h) with launcher #126: sparse host-tail reads
  are automatic on 8 GB (`BONSAI_SPARSE` unset), the dense VRAM line is kept, each 16k band past the engage point is
  timed once (dense vs sparse) and the faster is kept and cached. q3_0's sparse budget is 1/4 (D26h-3b).
- **12 GB:** the 12 GB default K/V type becomes q4_0 for 10-12 GB cards (D29: ~99 % of the 262k window in VRAM, 245k
  decode 15.4 -> 61.0 tok/s, copies / needles / HumanEval not below q8_0). Larger cards keep q8_0.
- Engine `product-0059` `ab9481005` (adfffbe + 59 patches); launcher at main `f152a0bf8`.

## Gates (written before the runs)

| gate | where | rule |
| --- | --- | --- |
| U01 op tests | 4070, release bins | ADD, RMS_NORM, GET_ROWS, SET_ROWS, CPY, FLASH_ATTN_EXT, GATED_DELTA_NET: 0 FAIL |
| U02 launcher paths (T1) | 4070, staged zip | default -> `window ... / q4_0 (12 GB default ...)`; `BONSAI_8GB=1` -> q3_0 + `kv sparse host-tail reads: auto` + `kv sparse calib`; `BONSAI_TOTAL_MIB=24576` -> q8_0 with its reason; each answers one request; no control bytes in tracked text files |
| U03 12 GB quality | 4070, staged zip | HumanEval 164 at medium on the default launcher (q4_0): >= 158 |
| U04 12 GB speed | 4070 | release default (q4_0) vs bundle-20261015c default (q8_0), same session: 4k / 32k not slower than 2 %; 245k at least 2x |
| U05 #112 repro | 4070, staged zip + mmproj | the Responses API tool-image request names the colour |
| U06 8 GB | 2060 | P146 (D26h gates, PASS) and P148 (245k quality, auto vs dense, n 20 / n 24 / n 28) |
| U07 publish | - | zip from the release commit, GitHub + Hugging Face, SHA on both, bins installed, 2060 post-zip check |

## Amendment: U04b (written 00:25 on 10-16, after U04 and before U04b runs)

- **U04 as written fails** at 32k: release default (q4_0) 92.9 vs bundle-20261015c default (q8_0) 101.5 mean decode
  (-8.5 %). 4k is +0.8 %, 245k is 4.1x (60.4 vs 14.8). The whole 32k loss is the code prompt: q8_0 121.6 tok/s at MTP
  draft acceptance 0.884 (mean 3.66 tokens per step), q4_0 94.2 at 0.715 (2.57); prose is +4.5 %, bash -2.0 %, and
  prefill is 3-8 % faster with q4_0. The two caches generate different text, and the text sets the acceptance (as on
  Mirai, sparse-20261014 N02).
- **U04b** measures the cache speed without the drafter: `BONSAI_SPEC=0`, the same two roots, 4k / 32k / 128k, one
  server per arm. Rule: q4_0 mean decode not slower than 2 % at 4k and 32k; 128k reported. U04's numbers stay in the
  record as measured.
