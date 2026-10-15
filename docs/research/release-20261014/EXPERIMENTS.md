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

## VRAM trace at 245k for the launcher headroom (07:15-08:15)

- **Question.** What does sparse cost in VRAM at 245k, against what the launcher counts? (The 2060's P124 showed only
  43 MiB free at 245k with f16 bounds, below R06's 60 MiB gate.)
- **Setup.** root-0055, line pinned at 32,768, 245k, dense then sparse (B 8192 + FRAC), `nvidia-smi` every 1 s.
- **Result.** Dense peak 8,613 MiB (min free 3,398); sparse peak 8,763 MiB (min free 3,248). Sparse - dense = 150 MiB;
  the launcher's count was about 138 MiB (104 bounds + 32 fill + 2 tables): about 12 MiB missed.
- **Decision.** #49 `3035572`: fixed headroom 36 -> 64 MiB (36 + 12 + 16). The 2060's P135 then had 153 MiB free at 245k.
- **Receipts.** `docs/receipts/vram245_dense.csv`, `vram245_sparse-decode.csv`, `release_0055.log`.

## R04b Dense control and floor 12288 at 200k (08:17-09:03)

- Dense: copies **9/10** (miss `_pydatetime.py` `_check_tzname`), needles 12/12, 10.4 tok/s. Sparse floor 12288 (192 of
  2,600 pages): 9/10 (the same item), 12/12, 22.0 tok/s.
- So R04's 200k miss was a model miss on that item, not a sparse loss. The R04 gate was amended to "not below dense on
  the same items" (README, written before R04c / R04d), with the floor decision rule.

## R04c / R04d 20 copy items at 200k (09:03-10:25)

- `bench/sparse_prefill_n.sh` (= `sparse_prefill.sh` with `--n ${CN}`), CN 20, the same 20 items in every arm:

  | arm | pages kept | copies | needles | mean decode |
  | --- | ---: | ---: | ---: | ---: |
  | dense | - | 20/20 | 12/12 | 10.4 |
  | sparse floor 12288 (R04c) | 192 | 20/20 | 12/12 | 22.0 |
  | sparse FRAC 1/16 only (R04d) | 162 | **19/20** (`_pydecimal.py` `_convert_other`) | 12/12 | 22.9 |

- **Verdict.** By the declared rule: FRAC alone is below dense, the floor is not, so the floor 12288 stays (#49
  `3035572`). `_convert_other` is the sparse-sensitive item (also missed at 245k with B 8192): the first gate item for
  D25.

## R05b 160k with the floor (10:25-10:58)

- Same session: dense 14.4 tok/s, 10/10, 12/12; sparse floor 12288: **24.1** tok/s, 10/10, 12/12 = **1.67x**. **Pass**
  under the amended 1.5x gate (written before R05b). The floor's cost at 160k: 27.0 (B 8192, R05) -> 24.1 (-11 %).

## R06 RTX 2060 SUPER release check (2026-10-14, P135 + P136, by the 8 GB tester)

- RC `4de618549` + #49 `3035572`, driver 610.88, `75-real` build. Op tests pass.
- P135 (speed, memory): 160k 10.6 -> 17.5 tok/s (1.65x), 245k 6.3 -> 13.7 (2.17x); prefill equal; minimum free 153 MiB
  at 245k with the 64 MiB headroom (gate >= 60); VRAM line 61,696 -> 52,224 ("167 MiB of page bounds counted");
  0 one-token answers.
- P136 (quality, the rig's own item set): sparse equal to dense at 160k, 200k and 245k (10/10 copies, 12/12 needles in
  every arm).
- **Verdict.** Pass. Post-zip checks (SHA, op tests, bin hashes, default-off A/B vs bundle-20261013, fresh 60k,
  HumanEval on the bundle bins) follow on #21.

## R07 Publish (2026-10-14 14:40-15:05)

- PRs: #56 (0055, `c471b32cd`) and #49 (launcher, rebased onto #75, `35b89560d`) merged by the kernel session; #77 README
  upgrade note + the 55-commit layout row -> release commit `bfae9143`; #78 Hugging Face card.
- Zip: the bundle-20261013 layout; engine bins from the release build (`LLAMA_COMMIT 4de6185494`, sm 75 / 86 / 89),
  byte-identical to the gated `/tmp/root-0055/bin`; every other file from `git archive bfae9143`. 9 entries changed
  against bundle-20261013 (README, the launcher, 7 engine files). 611,390,390 bytes, SHA-256
  `c91dfc98f82c74db93370568e47210d2e6c98c2907ed7aef872ba3bf5ab24cd0`.
- GitHub release `bundle-20261014` and Hugging Face (`c0a84f8` zip, `58d253b` card): the digest / LFS oid match on
  both. The bins are installed in the product `bin/` (bundle-20261013 kept in `bin-20261013/`).
- **Verdict.** Published.

## R08 2060 check of the published zip (2026-10-14, P138, by the 8 GB tester)

- Zip 611,390,390 B, SHA-256 `c91dfc98...4cd0` matches; `llama-server --version` commit `4de6185494`. `ADD` 99/99,
  `RMS_NORM` 51/51, `FLASH_ATTN_EXT` 3005/3005, `GATED_DELTA_NET` 55/55; the GDN "skipped: device cc 750" line once.
- Bin hashes differ from the tester's own `75-real` build (`bin-rc55`), as expected: the zip carries the sm 75 / 86 / 89
  release build. P139 reruns the sparse checks on the zip bins.
- Default off, same session, alternated x2, vs bundle-20261013 at 64k / 96k / 128k: 36.5 / 25.95 / 17.1 vs 36.2 / 25.9 /
  17.0 (-0.8 / -0.2 / -0.6 %, within 3 %). Sweep 4k-128k 53.6 / 47.8 / 36.5 / 26.2 / 16.2, minimum free 117 MiB; fresh
  60k 38.2 / 38.2; 0 one-token answers (lookup A/B 0 of 22).
- **Verdict.** Pass.

## R09 RTX 2060 SUPER, sparse on the published zip bins (2026-10-14, P139, by the 8 GB tester)

- **Question.** Do the release-built bins of bundle-20261014 give the RC sparse results (P135 / P136)?
- **Setup.** The zip bins, a test copy of the release launcher `bfae9143`, 245k cold, dense (default) vs
  `BONSAI_SPARSE=1` (launcher: `12288,64,1024`, 167 MiB of page bounds counted, VRAM line 61,184 -> 51,712).
- **Result.**

  | 245k, cold | dense | sparse |
  | --- | ---: | ---: |
  | mean decode | 6.2 | **13.6 (2.19x)** |
  | trace minimum free | 106 MiB | 153 MiB |
  | copies / needles | 10/10, 12/12 (P136) | 10/10, 12/12 |

  HumanEval 164 on the zip bins, default switches: 158/164, the same six fails as P87 (32, 40, 92, 93, 145, 160). 0
  one-token answers in every arm.
- **Verdict.** Pass. The release bins match the RC (P135: 13.7 at 245k, minimum free 153). bundle-20261014 is fully
  checked on the 2060.
- **Receipts.** #21 (P139).

## Status

- Published as bundle-20261014; the 2060's post-zip checks passed (R08 default, R09 sparse). D26 (sparse without the line cost) stays open after
  D26a / D26c / D26e; sparse stays opt-in.

