# Release bundle-20261105 (the turn cannot end inside the think block)

Plan written before the runs (2026-11-05 10:05). Engine: `serve/eog-think` (`21fd9beda`) = bundle-20261026's engine
`a38714c63d` + patch 0073. Launcher, layer and suite: unchanged.

Patch 0073 (`common/reasoning-budget.cpp`, 34 lines): while the reasoning-budget sampler has the think block open
(state COUNTING or WAITING_UTF8), every end-of-generation token gets logit -inf. The block closes when the model
writes `</think>` or when the budget forces it closed; after that, the end-of-generation tokens are free again.

Why: with thinking on and sampling at temperature > 0, a low-bit model puts a small probability on `<|im_end|>` at
each thinking step. Over thousands of thinking tokens it can get sampled. The turn then ends with reasoning only: no
answer and no tool call. An agent client takes that as the end of the task, often in the middle of a sentence. With
0073 the model cannot end the turn there; it must close the block first. The rate on Bonsai in normal use is not
measured; R3 forces the case with a logit bias.

Where it acts: the sampler exists for every request when `--reasoning-budget` is 0 or more. The launcher always passes
it (`BONSAI_THINK_BUDGET`, default 20,480), so every request with thinking on has the guard. With
`BONSAI_THINK_BUDGET=-1` only requests with tools (or a lazy grammar) have the sampler, so only they have the guard.
With thinking off the template closes the block in the prompt and the sampler stays idle: no change. Greedy decoding
changes only where the top token inside the think block is an end-of-generation token.

The zip ships the bundle-20261026 `bin/` files with one exception: `llama-common.dll` from the release build of
`21fd9beda` (the same build options as release-20261026: `gates/build_beog.cmd`). The patch changes only
`common/`, so `ggml*.dll`, `llama.dll`, `mtmd.dll` and the server files stay byte-identical to bundle-20261026 and
the CUDA kernels on every card are the ones the 1026 gates (R3 identity, R7 on the RTX 2060 SUPER) passed. For that
reason there is no rig gate in this release.

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | outside `docs/` the same entries as bundle-20261026; `bin/` files identical to 1026 except the files of the amendment below (before it: `llama-common.dll` only); changed outside `docs/` and `bin/`: none; 0 text files with control bytes; every relative link in the zip's `.md` files resolves inside the zip (the exemptions of release-20261019b); `llama-server --version` from the unzipped root reports `21fd9beda` |
| R2 launcher | as release-20261026 R2 (default 12 GB; `BONSAI_8GB=1`; `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`; `BONSAI_TOTAL_MIB=24576`): health ok, a short greedy answer, 0 CUDA errors |
| R3 fail-without / pass-with | default 12 GB launcher, layer off, thinking on, `"reasoning_format": "none"` (raw text), the train prompt, `logit_bias` on `<|im_end|>`, 5 tries per root, 1026 zip root first. Bias: +8; if the 1026 root ends with the block open in fewer than 3 of 5 tries, the next bias is +12, then +16 (the bias of the gate is the first one where 1026 fails 3 or more of 5; if none, the gate does not reach its trigger: no publish). PASS: the candidate root ends with the block open in 0 of 5 tries at that bias, and gives an answer after `</think>` in at least 4 of 5 |
| R4 saved conversations | as release-20261026 R4 (8 GB defaults, layer, slot folder, 3 turns, then two conversations that take turns); 0 CUDA errors |
| R5 no cost, 12 GB | default launcher, layer off, fresh server per depth, the 1026 zip root and the candidate root in turns: 4k and 32k mean decode (quick_tps, thinking off) at least 0.97x of 1026, texts identical; then thinking on, greedy, 6 prompts (`gates/think_texts.py`) at depth 0: texts (reasoning and answer) identical to 1026 |
| R6 HumanEval | HumanEval 164 at medium, greedy, raw server (layer off), candidate root, `bench/humaneval_run.py --arm medium --max-tokens 24576`: at least 158 / 164 (the RTX 4070 q4_0 card number) and 0 empty answers |

All pass: publish as the latest release. Any fail: no publish; log why.

## Amendment (10:11, before any gate run)

Build. The clean build of `gates/build_beog.cmd` was stopped (slow; it was not used). The engine was built as
`gates/build_beog_incr.cmd` says: the release-20261026 build folder (its CMake cache holds the 1026 release options),
its source worktree moved from `a38714c63d` to `21fd9beda`, configure again on the same cache (else `build-info.cpp`
keeps the old commit), then an incremental build. Against the 1026 build, `ggml-cuda.dll`, `ggml-cpu.dll`, `ggml.dll`
and `mtmd.dll` are byte-identical; the files that hold `common/` code or the commit string changed.

What ships. The commit string is in a static library (`llama-common-base`) that is linked into `llama-common.dll` and
`llama-server-impl.dll`, and `ggml-base.dll` holds the ggml commit. With only `llama-common.dll` new, `--version`
would say `21fd9beda` and `/props` and every `system_fingerprint` would say `a38714c63d` (peer review). So the zip
ships the rebuilt `ggml-base.dll`, `llama.dll`, `llama-common.dll`, `llama-server-impl.dll`, `llama-server.exe` and
`test-backend-ops.exe`; `ggml-cuda.dll`, `ggml-cpu.dll`, `ggml.dll`, `mtmd.dll` and the CUDA runtime stay the 1026
files. The kernels are unchanged, so there is still no rig gate. R1 now: those six `bin/` files changed, all others
identical to 1026; every unzipped `bin/` file equal to its zip entry (sha256); and R2 checks that `/props`
`build_info` names `21fd9beda`.

Other changes from the peer review:
- R2 / R4 owner check: with the layer on, `llama-server` listens on 18080 (the layer on 8080); the check uses that port.
- The roots are unzipped again at every run, and the log folder is cleared, so no file of an earlier run can count.
  A server that does not start is a FAIL line, not a skipped cell; R5 needs 6 / 6 files on each side.
- R3: a try counts as "open" only when it stops (`finish` = `stop`) with no `</think>` (a length cut is "other"). The
  first try on each root runs at bias 0 and must close the block and answer. The bias stays on after `</think>`, so
  at +12 / +16 a high `<|im_end|>` bias can end the answer at once; that is not what 0073 changes. PASS is now: at the
  gate's bias, the candidate ends with the block open in 0 of 5 tries and closes it in 5 of 5; at +8 also an answer
  in at least 4 of 5.
- `max_tokens` 4,096 in R3 / R5 is raised by the launcher's floor to 24,576 (think budget + 4,096); the texts are
  compared at that cap.
- New R3c, the agent path (greedy, thinking on, `gates/agent_path.py`), on both roots: one request with a tool
  (`get_weather`, the tool grammar is lazy) and one with `response_format` `json_schema` (a strict grammar that also
  acts while the block is open). PASS: the candidate gives a parsed `get_weather` call for Paris and JSON with the
  schema's keys, and no case that passes on 1026 fails on the candidate.
- Known, not gated: each request's sampler init scans the vocabulary for end-of-generation tokens (~250k lookups,
  a few ms of time to first token); a model that never closes the block now thinks until the budget closes it.

## Results (2026-11-05 10:12-11:27, RTX 4070)

Log: [`data/release_1105.log`](data/release_1105.log). Zip sha256 `bce9a0d0b136f2ae...`, engine `21fd9beda`. Memory
clock 11,751 MHz in R5.

| Gate | Result | Verdict |
|---|---|---|
| R1 zip | outside `docs/`: no new or removed entries; changed: the six planned `bin/` files only (`ggml-base.dll`, `llama-common.dll`, `llama-server-impl.dll`, `llama-server.exe`, `llama.dll`, `test-backend-ops.exe`); docs changed: `12gb/README.md`, `8gb/README.md` (the public-repo audit after 1026), `build/PATCHES.md`, `build/UPGRADING.md`; 0 control-byte files; 0 broken links; every unzipped `bin/` file equal to its zip entry; `--version` `21fd9beda` | PASS |
| R2 launcher | default, `BONSAI_8GB=1`, `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`, `BONSAI_TOTAL_MIB=24576`: health=1, a correct short answer, 0 CUDA errors each; the replay line on the 8 GB arm only; `/props` `build_info` `b10816-21fd9beda` | PASS |
| R3 fail-without / pass-with | bias 0: both roots close the block and answer. 1026 at +8: open 2 / 5 (below the trigger), at +12: open 5 / 5, 0 answers, so the gate's bias is +12. Candidate at +12: open 0 / 5, closed 5 / 5 (and 3 of 5 still answer although `<|im_end|>` keeps +12 after the block); 0 CUDA errors on both | PASS |
| R3c agent path | 1026 and candidate the same: `get_weather` `{"city": "Paris"}` (`tool_calls`), JSON `{"city": "Tokyo", "population_millions": 14.0}`; the reasoning lengths are equal too (113 and 2,118 characters) | PASS |
| R4 saved conversations | 3 turns (18.8 / 8.4 / 8.8 s; slot files 1, 2, 3); conversations A and B take turns, turn 2 of each reads its own save (25,971 / 25,985 cells, 25 / 24 new tokens); 7 index entries, 4 deltas; 0 CUDA errors | PASS |
| R5 no cost | mean decode 4k 96.2 -> 96.9 (1.007x), 32k 87.8 -> 88.0 (1.002x); thinking off texts 6 / 6 identical; thinking on, greedy, 6 prompts: 6 / 6 identical (reasoning and answer); 0 CUDA errors | PASS (see note 1) |
| R6 HumanEval | 159 / 164 (fails: 47, 93, 116, 132, 145), 0 empty answers, 3,580 s | PASS (see note 2) |

R3 tries (finish, kind, completion tokens): [`data/r3_old.jsonl`](data/r3_old.jsonl),
[`data/r3_new.jsonl`](data/r3_new.jsonl). On 1026 at +12 the turns end after 10-149 tokens, all inside the block.

Note 1, a script fault in R5 (the measurements are not affected). The script's count and compare lines used
`$TEMP/r1105-logs/...` in a glob; `$TEMP` holds backslashes, which a glob reads as escapes, so they found 0 files and
the log says "0 / 0" and "0 / 1 identical". The files were there (both servers ran, the log shows each reply). The
compare was done again at 10:26 on the same files with a POSIX path: thinking off 6 / 6 and thinking on 6 / 6
identical; the files are in [`data/texts_r5_old`](data/texts_r5_old), [`data/texts_r5_new`](data/texts_r5_new),
[`data/think_old`](data/think_old), [`data/think_new`](data/think_new). The script now uses a POSIX path.

Note 2, R6 ran twice. The first start (10:25:37) stopped at once: the HumanEval data file was not in `%TEMP%`; it was
put back from a local copy (164 tasks, sha256 `b796127e...`) and R6 was started alone (10:27:14). That run's server
passed the health and owner checks (the process on port 8080 ran from the candidate root's `bin\`), but its launcher
and server log files were not found after the run, so the R6 CUDA error count is not known. It is not part of the
R6 condition; R2-R5 show 0 CUDA errors on the same files.

Published zip: the tested zip with `docs/build/UPGRADING.md` updated to these results (the only entry that differs;
checked entry by entry), sha256 `d3ebf3a604bb82b50b81be52dcba98c014702d90b7ebf945c7446c646795040e`.

**All gates pass: bundle-20261105 is published as the latest release.**
