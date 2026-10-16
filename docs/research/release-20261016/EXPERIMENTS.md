# Experiments U01-U07

Gates in `README.md` (written before the runs; U04b added before it ran). Staged zip = the bundle-20261015c layout
with the release bins (`LLAMA_COMMIT ab94810051`, sm 75 / 86 / 89 + PTX) and main `f152a0bf8`'s launcher and docs, root
`/tmp/root-0059s`. RTX 4070, driver 610.88, memory clock 11751 MHz under load. Receipt `docs/receipts/release_0059.log`.

## U01 op tests (23:47)

- ADD 99/99, RMS_NORM 51/51, GET_ROWS 123/123, SET_ROWS 177/177, CPY 259/259, FLASH_ATTN_EXT 3115/3115,
  GATED_DELTA_NET 55/55; 0 FAIL. **Pass.**

## U02 launcher paths (23:51-23:55)

| path | window line | kv lines | reply |
| --- | --- | --- | --- |
| default (12 GB card) | `q4_0 (12 GB default, BONSAI_CTK=q8_0 for the previous one)` | line 260,352 | OK |
| `BONSAI_8GB=1` (margin 3600) | `q3_0 (8 GB default)` | line 143,872; `sparse host-tail reads: auto (dense line 143872 ...)`; `sparse calib: ... new` | OK |
| `BONSAI_TOTAL_MIB=24576` | `q8_0 (q8_0: the card holds most of the window)` | line 129,024 (sized from this card's free VRAM) | OK |

- Control bytes in tracked text files on main: 0. **Pass.**

## U05 #112 repro (23:56)

- The Responses API tool-image request (mmproj on the CPU): "The main (and only) color in the screenshot is a solid,
  vivid red." **Pass.**

## U04 12 GB speed, drafter on (23:56-00:16): fail as declared

| depth | bundle-20261015c default (q8_0) | release default (q4_0) | change |
| ---: | ---: | ---: | ---: |
| 4k | 95.4 | 96.2 | +0.8 % |
| 32k | 101.5 | 92.9 | **-8.5 %** |
| 245k | 14.8 | 60.4 | **4.1x** |

- The 32k loss is the code prompt alone (121.6 vs 94.2 tok/s at MTP draft acceptance 0.884 vs 0.715; prose +4.5 %,
  bash -2.0 %; prefill 3-8 % faster with q4_0): the caches generate different text, and the text sets the acceptance.

## U04b 12 GB speed, drafter off (01:12-01:21)

| depth | q8_0 | q4_0 | change |
| ---: | ---: | ---: | ---: |
| 4k | 67.2 | 67.2 | 0.0 % |
| 32k | 58.2 | 60.4 | +3.8 % |
| 128k | 41.5 | 45.5 | +9.6 % |

- **Pass:** the q4_0 cache is not slower at any depth; U04's 32k dip is draft acceptance on one prompt.

## U03 12 GB HumanEval (00:17-01:11)

- Default launcher (q4_0): **158/164**, fails 36, 47, 93, 116, 132, 145: the same six as D29's q4_0 run on the 15c bins,
  so patch 0059 does not change the 12 GB output. 0 test-process failures. **Pass.**

## Status

- 4070 gates done (U01, U02, U03, U04b, U05 pass; U04 failed as declared, explained by U04b). U06: P146 PASS; P148
  running on the 2060. Then U07 (publish).
