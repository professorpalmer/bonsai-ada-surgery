# Release bundle-20261123 (the tiered K/V cache is exact at every window size)

Plan written before the runs (2026-11-23 02:40). Engine: `serve/tier-fix` = bundle-20261105's engine `21fd9beda` and
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
