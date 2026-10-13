# Experiments

One entry per experiment, in run order. Times are local (CDT). HumanEval lines come from
`docs/receipts/he_template_ab.log`; "over 4k" is the number of tasks with more than 4096 completion tokens. GPU hours
are wall time on the RTX 4070.

Baseline for every HumanEval entry (the template as served, work rules in the system turn): **160/164, mean 2312
tokens, median 576, 18 over 4k** (TH04).

## TH01: community "terse" template, first attempt (VOID)

- When: 2026-10-10 18:50-18:55, 0.08 GPU-h.
- Arms: terse on / terse off.
- Result: VOID. A speed run started on the same port and stopped the server; the run logged 0/164 after 11.8 s
  (`ConnectionResetError`). Cause: two queue waiters fired on one marker. See TH02 for the rerun.

## TH02: community "terse" template (rerun)

- When: 2026-10-10 20:23-21:43, 1.33 GPU-h.
- Question: does a third-party template with a "be terse" system block cut thinking?
- Gate (declared in chat): same score, fewer tokens than the served template.
- Result: terse on 160/164, mean 2454, median 594, 21 over 4k; terse off (no system turn) 159/164, mean 932, median 710.
- Verdict: rejected. The terse block makes thinking longer than the served template; removing the system turn is what
  cuts it. This gave the question for TH03-TH07.

## TH03: no system turn (GGUF template without the work rules)

- When: 2026-10-10 22:45-23:07, 0.37 GPU-h.
- Result: 159/164, mean 932, median 710, 3 over 4k (the same outputs as TH02 "off").
- Verdict: the long tail comes with the system turn. Score is in the noise (-1).

## TH04: baseline, the served template (from the 0053 smoke run)

- When: 2026-10-11 01:23-02:15. GPU time is counted in `../release-20261011/` (the same run was the 0053 HumanEval
  gate); 0 here.
- Result: 160/164, mean 2312, median 576, 18 over 4k.

## TH05: work rules in the first user turn (A)

- When: 2026-10-11 03:50-04:15, 0.42 GPU-h.
- Arms: GGUF template without rules + `--prefix-file tmp/templates-sharp/work_rules.txt` (the rules text in front of
  the user message).
- Gate: same score, fewer tokens.
- Result: 160/164, mean 956, median 676, 3 over 4k.
- Verdict: passes on HumanEval. Agent side not checked here; see TH10-TH12.

## TH06: effort sentence + rules in the system turn (C)

- When: 2026-10-11 04:15-05:10, 0.92 GPU-h.
- Result: 161/164, mean 2327, median 599, 19 over 4k.
- Verdict: no change. The text of the system turn does not matter; its presence does.

## TH07: rules + `reasoning_effort: low` (B, INVALID)

- When: 2026-10-11 05:10-06:03, 0.88 GPU-h.
- Result: 160/164, mean 2312, 18 over 4k: the same as TH04 to the token.
- Verdict: invalid test. The launcher maps every effort word except `medium` to `medium` (`BONSAI_EFFORT_ALLOWED`
  unset), so `low` never reached the template.

## TH08: thinking budget 4096 (HumanEval)

- When: 2026-10-11 06:56-07:29, 0.55 GPU-h.
- Result: 160/164, mean 1178, median 589, 18 over 4k (the budget cuts thinking, the answer after it can still run
  long).
- Verdict: passes the HumanEval gate; agent side in TH13-TH14.

## TH09: thinking budget 2048 (HumanEval)

- When: 2026-10-11 07:29-07:55, 0.43 GPU-h.
- Result: 160/164, mean 913, median 606, 0 over 4k.
- Verdict: passes the HumanEval gate; agent side in TH13-TH14.

## TH10: client system prompt, served template (T1a)

- When: 2026-10-11 10:21-11:12, 0.85 GPU-h.
- Question: what a coding client sees. `--system-file bench/prompts/agent_system.txt` with the served template.
- Result: 158/164, mean 2209, median 557, 20 over 4k.
- Verdict: the reference for TH11.

## TH11: client system prompt, user-prefix template variant (T1b)

- When: 2026-10-13 11:27-12:07, 0.67 GPU-h. A first attempt on 2026-10-11 11:13-11:50 stopped at 154/164 at the
  shutdown (0.62 GPU-h, VOID, not counted in the verdict).
- Arms: `served_template_userprefix.jinja`: the template puts the system text (rules and the client's prompt) in front
  of the first user message.
- Gate: same score as TH10, fewer tokens.
- Result: 158/164, mean 1476, median 635, 10 over 4k.
- Verdict: passes on HumanEval (-33 % mean tokens). Agent side in TH12.

## TH12: workspace tools, served template vs user-prefix variant (T2)

- When: 2026-10-13 12:07-13:40, 1.55 GPU-h. Receipt: `docs/receipts/tool_template_ab.log`.
- Gate: same workspace score as the served template.
- Result: served 13/15 at 126,183 completion tokens; variant 11/15 at 119,991. Stress test (native grammar, 18
  calls): served 11 payloads OK, variant 14.
- Verdict: rejected. The variant loses 2 workspace tasks and saves only 5 % tokens on agent work.

## TH13: thinking budget on agent work, three arms (VOID)

- When: 2026-10-13 13:40-16:31, 2.85 GPU-h. Receipt: `docs/receipts/budget_agent_ab.log` (VOID note at 16:01).
- Arms: server budget default / 4096 / 2048.
- Result: VOID. All three arms gave 13/15 at 126,183 tokens. `suite/run_suite.py` sent
  `reasoning_budget_tokens=20480` with every request, and the per-request value overrides the server's
  `BONSAI_THINK_BUDGET`, so all three arms ran at 20480.
- Fix: `SUITE_REASONING_BUDGET` in `suite/run_suite.py`; `bench/budget_agent_ab.sh` sets it per arm (6932b40).

## TH14: thinking budget 2048 on agent work, budget applied (b2048_req)

- When: 2026-10-13 17:02-17:44, 0.70 GPU-h (workspace tasks, then the stress test).
- Gate: same workspace score as the product (13/15).
- Result: 6/15 at 64,975 completion tokens. Stress test (native grammar, 18 calls): 10 payloads OK. The runs at the
  20480 budget gave 10-16 on the same test (TH12, TH13), so the stress test does not separate the arms.
- Verdict: rejected. A 2048 budget halves the tokens and loses 7 of 15 workspace tasks. The 20480 default stays.
