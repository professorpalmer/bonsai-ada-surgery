# Bonsai 2 27B: where it fails, with traces and reproduction

For PrismML. Model: `Ternary-Bonsai-2-27B-PTQ1_0` (+ ProCreations MTP head), served by the llama.cpp fork in this
repo on one RTX 4070 12 GB (q8_0 KV, 262k window, medium reasoning effort, temperature 1.0 / top-p 0.95 /
top-k 20 / min-p 0.05, reasoning budget 20480). Everything below is direct API calls to that server. Paired
runs, plans and pass gates frozen before results. Full log: `DECISIONS.md`. Summary by round: `REPORT.md`.
Raw requests, responses and trajectories: `results-raw.zip` (paths below are inside it).

Scope and limits: one model, small synthetic and semi-real task sets (6 to 16 pairs per experiment), one
machine. These are development results, not population estimates. Model-written code ran only inside a WASI
sandbox.

## 1. The short version

Reasoning is intact. The failures are in long, exact work, and they come in two kinds:

1. **API knowledge.** On a real coding task the model invents names and keyword arguments in the Python standard
   library, hand-rolls binary formats instead of using the library, and never recovers within its turn limit.
2. **Long bookkeeping.** On computations that need 20k to 40k tokens of working (dynamic programming over a
   table), it slips somewhere in its own notes. Answers at 40k thinking tokens are usually near-misses.

What did not cause it: the tokenizer, the tool-call parser, the sampler path, the q8_0 KV cache (exact recall
720/720 up to 21k tokens), or arithmetic (written arithmetic in the traces is essentially error-free).

## 2. Failure class A: invented and misremembered APIs

Task: the frozen "compressed bundle" contract (write `solution.py` that builds a gzip-compressed POSIX ustar
archive in memory from a JSON request; tools `write_file` and `run_python`; 12 model responses; graded by the
original output-only oracle on a hidden request). A 15-line reference using `tarfile` and `gzip` passes
(`bench/ref_bundle_solution.py`), so the task is easy with correct API use.

Baseline (no help), 30 attempts across five experiments: **1 functionally correct, 30 of 30 ran to the
12-response cap**. Final verdicts: invalid base64 or oversize 10, invalid tar 10, no solution file 4, gzip not
bounded 2, invalid gzip 1, unparseable output 1, digest mismatch 1.

Names that do not exist, found by checking every Python file the model wrote against the real runtime
(10 of 30 attempts contain at least one):

| Invented | Count | Example (file inside results-raw.zip) |
| --- | ---: | --- |
| `tarfile.USTAR` | 5 | `E8/dev-bundle-01-136-B20.json` `explore1.py`: `tarfile.open(fileobj=buf, mode='w:', format=tarfile.USTAR)` |
| `gzip.GzipFile(name=...)` | 4 | `E6/dev-bundle-01-122-R12.json` `dev1.py`: `gzip.GzipFile(mode='wb', mtime=0, name=b'', extra=b'')` |
| `tarfile.ustar` | 3 | `H10/dev-bundle-01-116-B20.json` `solution.py`: `tarfile.open(fileobj=buf, mode="wb", format=tarfile.ustar)` |
| `tarfile.FORMAT_USTAR` | 3 | `E8/dev-bundle-01-131-B20.json` `solution.py` |
| `zlib.DEFLATE` | 3 | `E8/dev-bundle-01-132-B20.json` `solution.py`: `zlib.compressobj(level=9, method=zlib.DEFLATE, wbits=-15)` |
| `zlib.GzipFile` | 3 | `E8R/dev-bundle-02-141-B20.json` `verify.py` |
| `tarfile.STATREG` | 2 | `E2/dev-bundle-01-103-B20.json` `dev_test.py`: `ti.typestat = tarfile.STATREG` |
| `gzip.GzipFile(extra=...)` | 2 | `E6/dev-bundle-01-122-R12.json` |
| `io.TextIO`, `tarfile.FORMAT_ustar`, `tarfile.default`, `tarfile.TarFile(mtime=...)`, `zlib.FINISH`, `zlib.FT_WHOLE` | 1-2 each | `E2/...103-B20.json`, `E6/...126-R12.json`, `E8/...136-B20.json`, `E8R/...141-B20.json` |

The real names are `tarfile.USTAR_FORMAT`, `tarfile.REGTYPE`, `gzip.compress(data, compresslevel=9, *, mtime=None)`,
`zlib.DEFLATED`, `zlib.Z_FINISH`.

More common than invented names is avoiding the library: the model builds tar headers and deflate streams by
hand and gets the bytes wrong (the invalid tar / invalid gzip / base64 verdicts).

Also seen: **14 of 30 attempts contain a syntax error in a file the model wrote** (unclosed brackets,
mismatched braces). Not investigated further; it may be the model, or long code passing through the tool-call
argument format.

**Shallow repair turns.** In those 30 attempts the first turn reasons a median of 59,500 characters; later
turns a median of 304 characters, and 49% of later turns reason under 300 characters, including turns right
after a failing test. The model debugs one small probe at a time and runs out of turns.

**What fixes it.** Adding one page of accurate `tarfile` / `gzip` facts to the prompt
(`bench/api_notes_tar_gzip.md`, every claim verified in the sandbox Python):

| | Functional | |
| --- | ---: | --- |
| frozen prompt | 0 / 12 | E8 (`dev-bundle-01`, seeds 131-136) + E8R (`dev-bundle-02`, seeds 141-146) |
| same + API notes | 11 / 12 | 11 rescues, 0 losses; E8 p = 0.016, E8R p = 0.031 |

Update (E9, seeds 161-166): the notes again 5/6, cumulative 16/18. Automatically generated API listings
(signatures and docstrings introspected from the runtime) did not reproduce it (1/6 and 2/6): with a listing
the model still builds the archive by hand; the notes work because they steer it to use the library. Placed at the end of
the user message with one generic sentence ("use the library functions listed above instead of implementing
these formats by hand"), the automatic listing matched the notes: 6/6 vs 6/6 (E9b, seeds 171-176).

**What does not fix it** (same task): 2x thinking budget (E2: 3/9 vs 4/9), 2x turns (E6: 1/6 vs 0/6), a tool
that runs the real grader on the public example (H10: 0/6 vs 0/6; the model called it 0 to 1 times).

## 3. Failure class B: long bookkeeping

Tasks: generated problems with brute-force integer answers (`bench/puzzles.py`): 0/1 knapsack with 13 items;
count integers up to N with a digit-sum and no-equal-adjacent-digits condition; LCS length and count of distinct
LCS strings for two 26-character strings.

| Condition | Result |
| --- | --- |
| thinking budget 20480 (default) vs 40960, knapsack + digits | 8/16 vs 13/16 (H2); did not replicate on fresh seeds (4/8 vs 4/8); all budget comparisons together: 7 rescues, 0 losses in 44 pairs |
| one 40960-budget answer vs a vote of three 12288-budget answers | 9/12 vs 6/12 (H5): short attempts are almost never right (digits 1/18) |
| with a sandboxed Python tool vs without | 10/12 vs 5/12 (E1), 11/12 vs 6/12 on unseen families (E1T), 12/12 vs 8/12 on table questions (E5) |

Typical misses at 40k thinking tokens: 39536 for 39626, 23438 for 23440, 53984 for 53953
(`H2/`, `H5/`, `H6/`). With code the model writes a short DP, runs it, often cross-checks by brute force, and
uses about 8x fewer tokens.

**Mid-computation cutoff.** When the reasoning budget trips, the server forces the close on the next token.
Example (`pz-pilot/digits-1-B20.json`): reasoning ends `...Sum: 932+938=1870+940=281Now produce the complete
answer.` and the model then answers 42847 (truth 54305). In Codex's earlier 58-response baseline, the only two
force-closed responses were the first turns of the only two functionally failed tasks. Softer closures and
telling the model its budget did not help (H7, H8).

## 4. Failure class C: exact copying

Task: copy one field to another byte for byte through a tool call (`bench/envs.py`, kind `copy`). 0 of 5
attempts correct. Examples (`pilot/attempts/copy-1-P0.jsonl`, `copy-3-P0.jsonl`): `dollar $HOME and %PATH%`
copied as `$HOME and %PATH%`; U+2028 copied as a space. The tokenizer round-trips these strings and the
tool-argument parser passes values through verbatim, so this is the model.

## 5. Comparison points

- **Teacher, same prompts.** Qwen3.8-27B (UD-Q4_K_M) with Bonsai's chat template, so prompt tokens are
  identical (`C1/`). Budget 20480, 8 problems: teacher 6/8, Bonsai 5/8. On knapsack the teacher finished three
  of four on its own in 4.3k to 8.7k tokens; Bonsai hit the 20480 cap on all four. On digits both hit the cap
  on all four and both scored 2/4.
- **Public agentic benchmark** (alesha-pro/qwen38-27b-bench-4x3090, commit dcac4a1, not reproduced here):
  AppWorld BF16 95.8, Mirai S (2.4 bpw, 8.45 GB) 89.9, Bonsai 2 PQ2_0 (2.13 bpw, 7.21 GB) 64.3; single-turn
  80.3 / 78.4 / 78.0. Single-turn parity holds; the agentic gap is specific and large.

## 6. What this suggests for a release

1. **Validate on long, exact work, not only single-turn.** The gap is invisible on reasoning benchmarks. A
   small gate that catches it: this bundle contract (oracle-graded), the three computation families, the copy
   task. All are in `bench/`, with deterministic graders and frozen plans.
2. **Calibrate / distill on API-dense code and long tool trajectories.** The lost material looks like
   rarely-used exact facts (constant names, keyword arguments) and long-chain reliability.
3. **Serving-side mitigations that measurably help today:** accurate API facts in the prompt for coding
   tasks; a code-execution tool for computation. Both are being built into this repo's server
   (`layer/` on a branch) and benchmarked end to end; that result is not in yet.

## 7. Reproduce

`README.md` in this folder has the layout and commands. In short: start the server, copy `bench/` next to an
API key, run `tooling/wasi-python/fetch_runtime.ps1` once for the sandbox, then for example
`python agent_contract.py --plan E8-plan.json --out E8` or `python run_puzzles.py --plan H2-plan.json --out H2`.
The agentic contract tasks need the frozen prompts and oracles from the original evidence bundle
(not in this repo; available on request).
