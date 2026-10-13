# Report

## Bottom line

- **Any system turn makes Bonsai think long on part of the tasks.** HumanEval 164 at medium: with the work rules in
  the system turn (the template as served) 2312 mean tokens and 18 tasks past 4k tokens; without a system turn 932 and
  3. The score stays 159-161/164 either way. The text of the system turn hardly matters (rules, a "terse" block, an
  effort sentence: all 2300-2450).
- **The two fixes that cut it on HumanEval do not hold on agent work:**
  - the work rules (and the client's system prompt) moved into the first user turn: HumanEval 2209 -> 1476 mean with
    a client system prompt, but the workspace tasks drop 13/15 -> 11/15;
  - a 2048-token thinking budget: HumanEval 2312 -> 913 mean at 160/164, but the workspace tasks drop 13/15 -> 6/15.
- **Nothing shipped.** The template and the 20480 budget stay as they are.

## Rejected

- Moving the system text into the user turn (prefix or template variant): TH05, TH11, TH12.
- A 2048 (or 4096) default thinking budget: TH08, TH09, TH14.
- The community "terse" system block: TH02.
- Effort words other than `medium` (cannot reach the template through the launcher): TH07.

## Lessons

- **Check what the client sends.** The first agent-side budget run (TH13) was void: `suite/run_suite.py` sent
  `reasoning_budget_tokens=20480` with every request, and the per-request value overrides the server's. Identical
  numbers in all arms were the sign (the HumanEval runner was not affected: it sets no budget unless `--budget` is
  given). Fixed: `SUITE_REASONING_BUDGET`.
- **The launcher maps effort words.** Every `reasoning_effort` except `medium` becomes `medium`
  (`BONSAI_EFFORT_ALLOWED`), so a request's `low` never reaches the template (TH07).
- **HumanEval alone is not a gate for thinking changes.** Both fixes looked free on HumanEval and cost agent tasks.

## GPU time

About 11.6 RTX 4070 GPU-h in all (`runs.jsonl`). Of that, 3.8 h was void or invalid (TH01, TH07, TH13). The void
first attempt of TH11 (0.62 h) is not in the total.
