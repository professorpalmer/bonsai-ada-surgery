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

## S04 8 GB default rule (RTX 2060 SUPER, P129 / P130 / P131 on `b86298dba`, by the 8 GB tester)

| rule item | result | record |
| --- | --- | --- |
| 1. 64k decode q3_0 within 5 % of q4_0 (alternated x2, same session) | 41.0 vs 39.6, **+3.5 %** | P130 |
| 2. perplexity at 16k at most +1 % | **+0.56 %** (7.9491 vs 7.9050); 64k +0.03 %; identical to P108 to 4 decimals | P129 |
| 3. HumanEval 164 at least 157 | **163/164** (HumanEval/93 fails) | P131 |
| 4. 160k copies / needles = q4_0 | q3_0 10/10 + 12/12 = q4_0 10/10 + 12/12 | P130 |

- Sweep (one server per type): 4k -1.8 %, 64k -1.7 %, **128k +44 %**, **192k +34 %**; line 80,640 vs 61,696 cells
  (1.31x); trace minimum free >= 91 MiB; 0 one-token answers. q3_0 op tests (SET_ROWS 14/14, GET_ROWS 4/4, CPY 7/7,
  FLASH_ATTN_EXT 110/110) pass on sm_75.
- The tester reads 163/164 as no loss on code, not a gain (greedy runs flip near-tie items).
- **Verdict: pass.** By the rule written before the runs, q3_0 becomes the 8 GB default (#91).

## S05 8 GB q4_0 under 0056 + 0057 (P140)

- `b86298dba` vs the `bundle-20261014` zip bins, q4_0 default switches, same session, alternated x2: answers identical
  11/11 in all four runs; mean decode **64k 35.7 -> 39.6 (+11.2 %), 128k 15.7 -> 16.9 (+7.6 %)**. On sm_75 the
  packed-half tile dequant removes more conversion work than on the 4070 (D28: +0.6 %).
- **Verdict: pass** (the gate was "not more than 2 % slower"; it is faster). Users who set `BONSAI_CTK=q4_0` get it.

## Status

- S01-S05 pass. P132 (sparse + q3_0) adds numbers but is not a rule item. Next: #88 + #91 merge, the README note
  (release commit), S06 (publish). The bundle also carries #95 (`BONSAI_SPARSE=1` budget 1/8, R10 / R10b / R11 in
  release-20261014).
