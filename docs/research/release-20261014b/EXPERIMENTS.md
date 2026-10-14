# Experiments S01-S06

Gates in `README.md` (written before the runs). Engine `product-0056` `b86298dba9` (= bundle-20261014's `4de6185494` +
0056 q3_0 + 0057 packed-half dequant), release build sm 75 / 86 / 89 (`LLAMA_COMMIT b86298dba9`), root `/tmp/root-0056` =
the bundle-20261014 zip + these bins + main's launcher (`07538d1`, with the q3_0 cell size from #83). RTX 4070, memory
clock 11751 MHz under load, driver 610.88. The PR #88 patch files applied on `4de6185494` give tree `bb92bcff`, the
same tree as the build.

---

## S01 Op tests (16:24-16:27)

- `FLASH_ATTN_EXT` 3115/3115, `GATED_DELTA_NET` 55/55, `SET_ROWS` 177/177, `CPY` 259/259, `GET_ROWS` 123/123; 0 FAIL.
  **Pass.**

## S02 12 GB same text (16:27-17:24)

- HumanEval 164 at medium on the bundle's binaries: 158/164; **164/164 answers identical** to bundle-20261014 (the
  b0055 run on the same bins as that bundle); 0 test-process failures. 0057's q8_0 dequant (the 12 GB default) is
  bit-exact. **Pass.**

## S03 12 GB speed (17:24-17:32)

- `bench/depth_arms.sh bench/arms/release_0056.txt` (tag rel0056), product `bin/` (bundle-20261014) vs root-0056:

  | depth | prefill 1014 | prefill 0056 | mean decode 1014 | mean decode 0056 |
  | ---: | ---: | ---: | ---: | ---: |
  | 4k | 1278.8 | 1285.0 (+0.5 %) | 95.4 | 96.5 (+1.2 %) |
  | 32k | 1084.9 | 1084.9 (0.0 %) | 101.7 | 102.3 (+0.6 %) |
  | 128k | 607.7 | 611.3 (+0.6 %) | 74.3 | 74.7 (+0.5 %) |

  **Pass** (all within 2 %, all at or above bundle-20261014).

## Status

- 4070 gates S01-S03 pass. S04 / S05 on the 2060 (P129-P132 on `b86298dba`) decide the 8 GB default; then #88 merges
  and S06 (publish).
