# Experiments R01-R07

Gates in `README.md` (written before the runs). Engine `product-0055` `4de6185494` (FRAC 1/16 default), release build
sm 75 / 86 / 89 (`LLAMA_COMMIT 4de6185494`), root `/tmp/root-0055` = the bundle-20261013 zip + the 0055 bins + the
#49 launcher. RTX 4070, driver 610.88, stock memory clock (10251 MHz under load; the OC profile was not applied after
the 00:31 Windows-update reboot). Every A/B is inside one session.

---

## R00 Release build (2026-10-14 03:55-04:04)

- The first configure failed: Windows' temp cleanup had deleted 1,484 old tracked files from the `%TEMP%` source
  worktree (`Cannot find source file: ggml-cpu/hbm.h`). `git checkout -- .` restored them; the build then ran clean.
  The success check looks at the output files (a failed configure had shown rc 0 through `cmd /c start /wait`).

## R01 Op tests (04:12)

- `FLASH_ATTN_EXT` 3005/3005, `GATED_DELTA_NET` 55/55, 0 FAIL. **Pass.**

## R02 12 GB same text (04:12-05:10)

- HumanEval 164 at medium on the bundle's binaries: 158/164; **164/164 answers identical** to bundle-20261013 (the
  vec kernel's skip of fully masked tiles is exact, as expected); 0 test-process failures. **Pass.**

## R03 12 GB speed (05:10-05:20)

- `bench/depth_arms.sh bench/arms/release_0055.txt` (tag rel0055), product `bin/` (bundle-20261013) vs root-0055:

  | depth | prefill 1013 | prefill 0055 | mean decode 1013 | mean decode 0055 |
  | ---: | ---: | ---: | ---: | ---: |
  | 4k | 1264.0 | 1260.9 (-0.2 %) | 89.8 | 89.6 (-0.2 %) |
  | 32k | 1065.2 | 1070.2 (+0.5 %) | 97.0 | 96.2 (-0.8 %) |
  | 128k | 593.3 | 599.2 (+1.0 %) | 70.1 | 69.7 (-0.6 %) |

  **Pass** (all within 2 %).

## R04 / R05 8 GB-like quality and speed (05:20-07:15)

- `bench/sparse_prefill.sh` on root-0055, line 32,768, sparse forced on by environment (`8192,64,1024`, FRAC 1/16 in
  the engine), graphs on, packed mask on.

  | depth | dense decode | sparse decode | ratio | sparse copies | sparse needles | dense copies / needles |
  | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
  | 160k | 14.4 | 27.0 | 1.88x | 10/10 | 12/12 | 10/10, 12/12 |
  | 200k | - | 22.9 | - | **9/10** | 12/12 | (R04b) |
  | 245k | 8.8 | 20.4 | 2.32x | 10/10 | 12/12 | 10/10, 12/12 |

- **R05 pass** (>= 1.8x at 160k and 245k). **R04 fail at 200k**: miss `_pydatetime.py` `_check_tzname` (position
  0.15). The server log: "host tail 166656 cells, keeps 162 of 2604 pages" (FRAC 1/16 = about 10.4k cells). At 245k
  FRAC keeps about 208 pages and passes; at 160k B 8192 (127 pages) passes. So 1/16 is too thin in the middle.
- **Publish stopped.** R04b (dense control at 200k, sparse with a 12288 floor) is queued; the kernel session picks the
  rule from it.

## Decision: opt-in (07:20)

- P127 on the 2060 (int8 bounds): the reserve still costs about 8 % at 64k. Sparse is opt-in for 0055
  (`BONSAI_SPARSE=1`, #49 `d927d6b`). R04 / R05 ran with sparse forced on, which is the opt-in path.
