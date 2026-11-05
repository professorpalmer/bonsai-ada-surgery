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
| R1 zip | outside `docs/` the same entries as bundle-20261026; `bin/` files identical to 1026 except `llama-common.dll`; changed outside `docs/` and `bin/`: none; 0 text files with control bytes; every relative link in the zip's `.md` files resolves inside the zip (the exemptions of release-20261019b); `llama-server --version` from the unzipped root reports `21fd9beda` |
| R2 launcher | as release-20261026 R2 (default 12 GB; `BONSAI_8GB=1`; `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`; `BONSAI_TOTAL_MIB=24576`): health ok, a short greedy answer, 0 CUDA errors |
| R3 fail-without / pass-with | default 12 GB launcher, layer off, thinking on, `"reasoning_format": "none"` (raw text), the train prompt, `logit_bias` on `<|im_end|>`, 5 tries per root, 1026 zip root first. Bias: +8; if the 1026 root ends with the block open in fewer than 3 of 5 tries, the next bias is +12, then +16 (the bias of the gate is the first one where 1026 fails 3 or more of 5; if none, the gate does not reach its trigger: no publish). PASS: the candidate root ends with the block open in 0 of 5 tries at that bias, and gives an answer after `</think>` in at least 4 of 5 |
| R4 saved conversations | as release-20261026 R4 (8 GB defaults, layer, slot folder, 3 turns, then two conversations that take turns); 0 CUDA errors |
| R5 no cost, 12 GB | default launcher, layer off, fresh server per depth, the 1026 zip root and the candidate root in turns: 4k and 32k mean decode (quick_tps, thinking off) at least 0.97x of 1026, texts identical; then thinking on, greedy, 6 prompts (`gates/think_texts.py`, 4,096-token cap) at depth 0: texts (reasoning and answer) identical to 1026 |
| R6 HumanEval | HumanEval 164 at medium, greedy, raw server (layer off), candidate root, `bench/humaneval_run.py --arm medium --max-tokens 24576`: at least 158 / 164 (the RTX 4070 q4_0 card number) and 0 empty answers |

All pass: publish as the latest release. Any fail: no publish; log why.
