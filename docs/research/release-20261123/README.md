# Release bundle-20261123 (the tiered K/V cache is exact at every window size)

Plan written before the runs (2026-11-23 02:20). Engine: `serve/tier-fix` = bundle-20261105's engine `21fd9beda` and
five commits:

| Commit | What |
|---|---|
| tier write-back fix | `cuda: tiered K/V: write back all host runs of a redirected set_rows` (+ `tests/test-kv-tier.cpp`) |
| F1 switch | `cuda: fattn-mma: optional fp32 V accumulation (GGML_CUDA_FA_VKQ_F32=1, off by default)` |
| MUL_MAT_ID test | `tests: MUL_MAT_ID one token, short K, rows not a multiple of the row block, for every type` |
| MMID row bound | `cuda: bound the one-column mat-vec rows by the row count, not by stride_col_dst` |
| host-memory fallback | `cuda: tiered buffers fall back to CU_MEM_LOCATION_TYPE_HOST_NUMA when the driver refuses HOST` and the same fallback for the page demotion of the sparse late reserve |

Launcher: one guard. With the tiered K/V cache on, `BONSAI_CTX` is rounded up to a multiple of 32,768.

## The fault that this release fixes

One tiered buffer per attention layer holds K, then V, in 2 MiB pages. When the K part is not a whole number of
pages, the last host page of K also holds the first cells of V. On the prompt-read path (no CUDA graph) the rows go
through a VRAM staging alias, and a kernel copies them back to the host pages. That kernel got only the first host run
of the tensor. For V that is the shared page, not the V tail. So the V rows past the VRAM line kept old bytes after a
prompt read. K was correct. Decode steps (CUDA graph, written in place) were correct.

Condition: a VRAM line (`--kv-vram-cells`, or the launcher's tier) and a window that is not a multiple of 32,768 cells
for q8_0 / q4_0 / q3_0 rows (1,024 for f16). The launcher defaults (262,144 / 131,072 / 98,304) are not affected. A
`BONSAI_CTX` that the user set (for example 100,000) with the tier on is affected. Symptom: answers that ignore the
middle of a long prompt; nothing in the log.

The other changes do not change output with their defaults:
- F1 (`GGML_CUDA_FA_VKQ_F32=1`) sums V x softmax in fp32 tiles in the FA MMA kernel. Off by default. On Bonsai it is a
  switch for tests only.
- The MMID row bound fixes a race in the one-token `MUL_MAT_ID` mat-vec (expert models). Bonsai is dense and does not
  build `MUL_MAT_ID`; the dense mat-vec gets the same row count as before (the row count equals the column stride).
- The host-memory fallback: drivers of the 570 family refuse `CU_MEM_LOCATION_TYPE_HOST`, and the tiered cache then
  did not load. Now the engine takes `HOST_NUMA` there. On this rig (driver 610.88) the `HOST` path stays in use.

Build: from neutral paths (`gates/build_tier.cmd`: the compiler sees `Y:\bonsai` and `Y:\build`), the release-20261026
build options (`75-real;86-real;89-real;89-virtual`, CUDA 13.4). Thus the asserts in the DLLs hold no local user or
folder name. The web UI is the pinned build of the same `tools/ui` source (no npm step); its licence list ships as
`licenses/web-ui-THIRD-PARTY.txt`.

## Gates (declared before the runs)

All runs on the RTX 4070 (12 GB, driver 610.88), one job at a time. Speed runs: memory clock checked under load
(11,751 MHz = the usual profile).

| Gate | Condition |
|---|---|
| B0 build | `llama-server --version` reports the `serve/tier-fix` head; 0 files in `bin/` that hold the local user name or a `Users\` source path |
| B1 tier test | `test-kv-tier` (no model file): every case OK, exit 0 |
| B2 op tests | `test-backend-ops -o FLASH_ATTN_EXT`: 0 failed with F1 off and 0 failed with `GGML_CUDA_FA_VKQ_F32=1`; `-o MUL_MAT_ID` and `-o MUL_MAT`: 0 failed (each run has a time limit; a run that does not finish is a FAIL) |
| B3 identity | the bundle-20261105 engine against the candidate engine (F1 off), the Bonsai model, 50 reference prompts (`/completion`, greedy, 96 tokens), q8_0 K/V, 16k window, no drafting: 50 / 50 token-identical |
| B4 fail-without / pass-with | KL scorer (llama API, a port of the public Qwen3.8-27B quantization-challenge `llama_kld.cpp`) on one 64,321-token document of the challenge's public BF16 reference set, q8_0 K/V, window 64,512 (not a multiple of 32,768). Arms: bundle-20261105 engine all cells in VRAM (A0) and 16,384 cells in VRAM (A1); candidate all cells in VRAM (C0) and 16,384 cells in VRAM (C1). Fail-without: A1 - A0 >= 0.05 (the fault shows). Pass-with: abs(C1 - C0) <= 0.0005 and C0 within 0.0005 of A0. Printed only: C1 with F1 on, and the same-top-token rates |
| R1 zip | outside `docs/` and `licenses/`: the same entries as bundle-20261105; new: `licenses/web-ui-THIRD-PARTY.txt`; changed outside `docs/`: the rebuilt engine files in `bin/` and `start-server.ps1` only; 0 text files with control bytes; every relative link in the zip's `.md` files resolves inside the zip; 0 zip entries that hold the local user name; every unzipped `bin/` file equal to its zip entry; `llama-server --version` from the unzipped root reports the candidate commit |
| R2 launcher | as release-20261105 R2 (default 12 GB; `BONSAI_8GB=1` with `BONSAI_KV_VRAM_CELLS=90112`; `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`; `BONSAI_TOTAL_MIB=24576`): health ok, a correct short answer, 0 CUDA errors; `/props` `build_info` names the candidate commit. Plus R2g: `BONSAI_CTX=100000` with the tier on: the launcher prints "rounded up to 131072" and the server window is 131,072 |
| R3c agent path | as release-20261105 R3c (tool call and `json_schema` on both roots): no case that passes on 1105 fails on the candidate. (R3 itself tested patch 0073, which is in both engines: not repeated.) |
| R4 saved conversations | as release-20261105 R4 (8 GB defaults, layer, slot folder, 3 turns, then two conversations that take turns): turn 2 of each reads its own save; 0 CUDA errors |
| R5 no cost, 12 GB | as release-20261105 R5: fresh server per depth, the 1105 root and the candidate root in turns, layer off: 4k and 32k mean decode; texts thinking off 6 / 6 and thinking on 6 / 6 identical. Speed line (A/B noise is about 5 %): candidate at least 0.92x of 1105 at each depth. Between 0.92x and 0.97x: one repeat of that depth on both roots, and the mean of the two runs decides |
| R6 HumanEval | HumanEval 164 at medium, greedy, raw server, candidate root: at least 158 / 164 and 0 empty answers |

Not a gate here: R7 (the RTX 2060 SUPER rig). The changed code is arch independent (a host-side launch loop, a switch
that is off, a row bound that equals the old one for dense models, a driver fallback), and B2 / B3 check the kernels on
sm_89. A check on the 2060 after the release is welcome.

All pass: publish as the latest release. Any fail: no publish; the reason goes into this file.

## Results (2026-11-23 02:39-02:59, RTX 4070, memory clock 11,751 MHz) - NOT PUBLISHED

Logs: [`data/release_1123_b.log`](data/release_1123_b.log).

| Gate | Result | Verdict |
|---|---|---|
| B0 build | `--version`: build 10822, commit `e6dda24c9` (the branch head); 0 of the candidate `bin/` files hold the local user name (the bundle-20261105 `bin/` has 9 such files) | PASS |
| B1 tier test | `test-kv-tier`: K and V rows 0 of 10,240 differ, attention output equal at 6 of 6 steps, ALL OK | PASS |
| B2 op tests | `FLASH_ATTN_EXT` F1 off 3,115 / 3,115, F1 on 3,115 / 3,115; `MUL_MAT_ID` 1,085 / 1,085; `MUL_MAT` (`n=1`) 699 / 699 | PASS |
| B3 identity | 50 / 50 token-identical (decode 66.2 / 66.0 tok/s) | PASS |
| B4 fail-without / pass-with | KL (21,356 scored positions): A0 0.0386127827, A1 0.0386127827, C0 0.0386127827, C1 0.0386127827 (top-1 96.231 % in all four); F1 on: 0.0386187021. Pass-with holds. Fail-without does NOT: the bundle-20261105 engine is exact at this window with a VRAM line | **FAIL (the gate does not reach its trigger)** |

The R gates were not run.

**Why the fault does not show on Bonsai.** The fault needs a write-back that copies only the FIRST host run of a
tensor. In this engine, `ggml_cuda_tier_host_part` returns the span from the first host run to the last one. That
change came with the sparse late reserve (2026-10-15, `ab9481005`: demoted chunks join the host runs). So since
bundle-20261015 the write-back covers the V tail too, and the published bundle-20261105 is exact at every window.
The engines that copied the tier code before that change kept the first-run form; there the fault is real, and patch
0074 is the fix. Bonsai bundles from 2026-10-08 to 2026-10-14 had the first-run form; with a window that the user set
(not the default) and the tier on, they were affected. The latest bundle is not.

**Decision.** No release from this branch: its main reason (a user-visible fault) does not exist in the latest
bundle, and the gate plan says no publish when a gate fails or does not reach its trigger. The other changes stay
here for the next engine rebuild: 0074 (the write-back per host run, exact and narrower than the span: it does not
copy the VRAM head), 0075 (F1, off), 0076 / 0077 (expert models only), 0078 / 0079 (570 drivers), neutral build
paths (the published DLLs hold a local user name in assert paths), the licence list in the zip, and the launcher
guard (it keeps an older engine safe). The entry for `bundle-20261123` in `docs/build/UPGRADING.md` on this branch
is a draft for that rebuild; its fault text must say that bundles since 2026-10-15 were not affected.

## Plan 2 (written 2026-11-23 03:05, before its runs): an optional update without build paths

New purpose. The published bundle-20261105 binaries hold local build paths (with a local user name) in the source
paths of their asserts: 9 files in its `bin/`. The build above (`e6dda24c9`, neutral paths) holds none (B0). This
release ships that build. It also ships the host-memory fallback for 570 drivers (0078, 0079) and the licence list of
the web chat page. Patches 0074 (write-back per host run), 0075 (F1, off) and 0076 / 0077 (expert models) come along
as hygiene: they change no output on Bonsai. Bundles since 2026-10-15 were not affected by the tier write-back fault
(see Results above); this release does not change answers. The launcher guard (window rounded up to a multiple of
32,768 with the tier on) stays: it changes nothing at the defaults.

Gates. B0-B3 above passed on this exact build and count for Plan 2 (B4 is not a Plan 2 gate). Then, on the zip:

| Gate | Condition |
|---|---|
| R1 zip | as in the table above (entries, changed files, control bytes, links, unzipped `bin/` = zip entries, `--version` = `e6dda24c9`) |
| P1 private strings | 0 zip entries that hold the local user name, a `Users\<name>` or `Users/<name>` path, or the names of the private local folders of the build machine (scan list in `gates/rel1123.sh`); the bundle-20261105 zip is scanned the same way and must show hits (the scan works) |
| R2 launcher + 8 GB path | as above: default 12 GB, `BONSAI_8GB=1` (+ `BONSAI_KV_VRAM_CELLS=90112`), `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`, `BONSAI_TOTAL_MIB=24576`, `BONSAI_CTX=100000` (guard): health ok, a correct short answer, 0 CUDA errors, `/props` names `e6dda24c9`; the 8 GB arms print the 8 GB window / kv lines |
| R3c agent path | as above |
| R4 saved conversations | as above |
| R5 no cost | as above, texts 6 / 6 + 6 / 6 identical; decode at 4k and 32k at least 0.92x of bundle-20261105, both roots on the same memory clock (11,751 MHz under load, read in each cell) |
| R6 HumanEval | at least 158 / 164, 0 empty answers |

All pass: publish as the latest release, merge `release/20261123`; the UPGRADING entry reads "optional update:
removes build paths from the binaries; no change to answers". Any fail: no publish; the reason goes into this file.

## Plan 2 results (2026-11-23 03:05-04:22, RTX 4070, memory clock 11,751 MHz under load in every R5 cell)

Log: [`data/release_1123.log`](data/release_1123.log) (local paths replaced by `<home>`). Zip sha256
`defff9296644847a4f801aace5bc81f745e1f8057e4e795addc761cbd214a2d9`, engine `e6dda24c9` (build 10822).

| Gate | Result | Verdict |
|---|---|---|
| B0-B3 | see the first results table (this exact build) | PASS |
| R1 zip | outside `docs/`: new `licenses/web-ui-THIRD-PARTY.txt`, none removed; changed: the 10 rebuilt engine files in `bin/` and `start-server.ps1`; docs changed: `CREDITS.md`, `build/PATCHES.md`, `build/UPGRADING.md`; 0 control-byte files; 0 broken relative links; unzipped `bin/` = zip entries; `--version` `e6dda24c9` | PASS |
| P1 private strings | candidate zip: 0 entries with hits; bundle-20261105 zip: 9 entries with hits (its engine DLLs and `test-backend-ops.exe`), so the scan works | PASS |
| R2 launcher + 8 GB path | default, `BONSAI_8GB=1`, `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`, `BONSAI_TOTAL_MIB=24576`: health 1, a correct short answer, 0 CUDA errors each; the 8 GB arms print `window 262144 / q3_0 (8 GB default)` and the 90,112-cell line, the replay arm `pending inputs of 2 tokens`; `/props` `b10822-e6dda24c9`. `BONSAI_CTX=100000`: `note window 100000 rounded up to 131072`, `/props` n_ctx 131,072 | PASS |
| R3c agent path | 1105 and candidate the same: `get_weather` `{"city": "Paris"}`, JSON `{"city": "Tokyo", "population_millions": 14.0}`, reasoning 113 / 2,118 characters on both | PASS |
| R4 saved conversations | 3 turns (19.1 / 27.3 / 18.1 s; slot files 1, 2, 3); A and B take turns, turn 2 of each reads its own save (25,971 / 25,985 cells, 25 / 24 new tokens); 6 index entries, 3 deltas; 0 CUDA errors | PASS |
| R5 no cost | mean decode 4k 96.7 -> 95.4 (0.987x), 32k 88.0 -> 87.8 (0.998x); thinking off texts 6 / 6 identical, thinking on 6 / 6 identical; 0 CUDA errors | PASS |
| R6 HumanEval | 159 / 164 (fails 47, 93, 116, 132, 145: the same five as bundle-20261105), 0 empty answers, 0 CUDA errors, 3,558 s | PASS |

Note, a script fault in R6 (no effect on the result). The first R6 start stopped before any task: the scorer's child
process inherited an invalid stdin handle in the headless console (`WinError 6`). The script now gives the runner
stdin from NUL, and R6 ran again on a fresh server (03:22-04:22). The R1-R5 server logs were in the folder that the
R6 start cleared; their gate lines are in the log above.

**All Plan 2 gates pass: bundle-20261123 is published as the latest release (optional update).**
