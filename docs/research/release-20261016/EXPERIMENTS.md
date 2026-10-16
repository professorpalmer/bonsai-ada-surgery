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

## U06 RTX 2060 SUPER (P146, P148, by the 8 GB tester)

- **P146 (D26h gates):** <= 128k worst -1.5 % vs sparse off (the line step is gone), 160k +2.6 %, 245k +10.1 %; the same
  128k answer byte for byte on two fresh servers; 0 one-token; minimum free >= 71 MiB. Bands: dense to 128k, sparse at
  144-160k and 224-240k. **Pass.**
- **P148 (245k quality, auto vs dense, fresh server per test):** copies 20/20 = 20/20; needles n 24 23/24 = 23/24
  (vault 14 in both); n 28 27/28 = 27/28 (vault 15 in both). The auto arm ran sparse (`keeps 668 of 2675 pages`).
  **Pass.**
- Not blocking: P149 (forced FRAC 1/8 on the same sets) for the budget question.

## Launcher addition before the release commit: #134

- From #16 (howdya): under Windows PowerShell 5.1 a launcher started with redirected output died on the server's first
  stderr line. #134 sets `$ErrorActionPreference = 'Continue'` before the server runs and exits with the server's exit
  code. Tested: the old launcher piped through `Out-File` never reached health, the fixed one did; a server that fails
  to load exits the launcher with 1. **U02 re-run on the final zip:** the three paths, each started piped
  (`2>&1 | Out-File`), reach health and answer.

## U07 Publish (2026-10-16 03:00-03:10)

- Release commit `fed8ae2d` (#135, README note; the KV precision row and bullet reworded for the 12 GB q4_0 default).
  Zip: the bundle-20261015c layout (66 entries), 9 changed (README, launcher, 7 engine files), engine bins identical to
  the gated staged root (16 / 16, `LLAMA_COMMIT ab94810051`), 616,653,192 bytes, SHA-256
  `24343fd9964ec42c2e2f016bbec940ba4225a9e8e516cc8e9b38f211a0aa66dc`.
- GitHub release `bundle-20261016` (digest matches; 15c notes say superseded); Hugging Face zip `3fe66fd` + card
  `5558057` (#136; 59 patches, the 12 GB q4_0 rows), LFS oid matches. Product `bin/` installed (`ab94810051`; 15c kept in
  `bin-20261015c/`).
- **Verdict.** Published. The 2060's post-zip check follows on #105.
