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

## R10 plan: a wider item set for the shipped sparse rule (written 2026-10-14 23:00, before the run)

- **Why.** On Mirai S (another model on the same engine), FRAC 1/16 with the 12,288 floor missed one needle digit at
  245k (the item at position 0.958; dense and a 1/8 budget were right). R04 / P136 / P139 on Bonsai used 10 copies and
  12 needles. Does the shipped Bonsai rule hold on more items?
- **Setup.** RTX 4070, the bundle-20261014 bins (product `bin/`), 12 GB recipe with the VRAM line pinned at 32,768
  cells (the R04 setup, most of the prompt in the host tail as on 8 GB), f16 mask; dense vs sparse forced by
  environment with the shipped values (`12288,64,1024`, FAST, STAGE_MIN_Q 9, MIN_HOST 32768, engine FRAC 1/16). 245k:
  `code_needle --n 20` and `needle_depth --n 24` (other positions than the n 10 / n 12 sets), one fresh server per arm.
- **Gate.** Sparse = dense on every item. If an item differs: rerun that arm with FRAC 1/8; if 1/8 matches dense, the
  8 GB launcher sets FRAC 1/8 (as Mirai) after a 2060 speed check.

## R10 Result: the shipped sparse rule on 20 copies + 24 needles at 245k (2026-10-14 22:57-23:42)

- Setup as the R10 plan; `docs/receipts/sparse_r10.log`, `sparse_r10.jsonl`. Sparse server log: "host tail 211712
  cells, keeps 206 of 3308 pages" (6.2 %).

  | 245k | copies (n 20) | needles (n 24) | items wrong |
  | --- | ---: | ---: | --- |
  | dense | 20/20 | 23/24 | vault 14 (0.562): `1968` for `8104` |
  | sparse, shipped rule (FRAC 1/16) | 19/20 | 22/24 | `_check_tzname` (0.128); vault 13 (0.521) `2542` for `2408`; vault 15 (0.604) `2144` for `7851` |

  Sparse gets vault 14 right, where dense is wrong.
- **Verdict: fail.** Item by item, sparse loses three items that dense gets right (one copy, two needles). The
  shipped opt-in rule is too thin at 245k on this item set. `_check_tzname` is the R04 200k miss again.
- **Next (as planned).** R10b: the same set with `GGML_CUDA_FA_SPARSE_FRAC=0.125`; P141 on the 2060 (another item set,
  a FRAC 1/8 arm with speed); PR #95 (launcher FRAC 1/8 for `BONSAI_SPARSE=1`) merges by its written rule.

## R10b The same set with FRAC 1/8 (2026-10-14 23:43 - 10-15 00:04), and what the copy miss is (00:10-00:25)

- One arm, the R10 sparse env + `GGML_CUDA_FA_SPARSE_FRAC=0.125` ("keeps 413 of 3308 pages", 12.5 %).

  | 245k | copies (n 20) | needles (n 24) | items wrong |
  | --- | ---: | ---: | --- |
  | dense (R10) | 20/20 | 23/24 | vault 14 |
  | sparse 1/16 (R10) | 19/20 | 22/24 | `_check_tzname`, vault 13, vault 15 |
  | **sparse 1/8** | 19/20 | 23/24 | `_check_tzname`, vault 14 |

  With 1/8 the needles are the same items as dense (vault 14 wrong in both); vaults 13 and 15 come back.
- **The `_check_tzname` miss is the scorer, not recall.** The function sits at cells 30,772-30,823, inside the VRAM
  line (32,768), so sparse reads all of it. A rerun of that one item on the sparse arm with a diff
  (`bench/code_needle_dump.py`, untracked copy of `code_needle.py` that prints the diff on a miss) shows the body
  exact, plus the comment line that stands just above the function in the file (`# Just raise TypeError if the arg
  isn't None or a string.`). The strict scorer counts that as a miss; dense left the comment out. The R04 200k miss
  is the same function (cells 30,639-30,690, also inside the line).
- **Verdict.** Strictly, R10b copies are 19/20 against 20/20. In substance, FRAC 1/8 equals dense on all 44 items: the
  only copy difference is an extra leading comment line from the source file. FRAC 1/16 loses two real needles.
- **Decision.** The FRAC 1/16 rule is too thin at 245k (R10); FRAC 1/8 is the candidate (PR #95, merge rule: P141 on
  the 2060). The copy scorer gets an option to accept comment lines directly above the function, reported next to
  the strict score (both, never only the lenient one).

## Status

- Published as bundle-20261014; the 2060's post-zip checks passed (R08 default, R09 sparse). D26 (sparse without the line cost) stays open after
  D26a / D26c / D26e; sparse stays opt-in.

