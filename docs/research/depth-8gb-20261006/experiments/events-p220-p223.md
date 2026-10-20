# Events, 2026-10-19 to 2026-10-20 (range p220-p223)

Notebook entries in this range that are not experiments: PRs, releases, issue threads, decisions, incidents and lessons.
Sources: `C:\bonsai\8gb\DECISIONS.md` (NOTEBOOK.md here) from the entry "2026-10-19 19:16 CDT Records PR #215 (P200-P219)
merged (6105d94) ..." to the entry "2026-10-20 08:57 CDT bundle-20261019c (release 22:41 CDT; option B on #138, issue
closed): P223 post-zip check PASS", receipts/queue.log, the receipts named below, the queue files' write times, the
server logs (`logs/`, not in this repo) where a record says so, the thread of issue #138 from 22:46:32Z (2026-10-19) to
03:41:32Z (2026-10-20), the PRs and releases of this repo, and `../release-20261019c/`. Numbering continues from
`events-p200-p219.md` (E96-E107). Times with "Z" are UTC (GitHub); "CDT" and other times are rig local time (UTC-5). The
GitHub posts of all sessions use the same account; "2060" and "release session" name the session.

- [E108 Records PR #215 and the corrections post](#e108-records-pr-215-and-the-corrections-post)
- [E109 The formal R6 of bundle-20261019b (P220, P221)](#e109-the-formal-r6-of-bundle-20261019b-p220-p221)
- [E110 The P222 decision: option B](#e110-the-p222-decision-option-b)
- [E111 bundle-20261019c and the P223 post-zip check](#e111-bundle-20261019c-and-the-p223-post-zip-check)
- [E112 Issue #138 closed](#e112-issue-138-closed)
- [E113 Queue incident: the P223 first try got HTTP 401](#e113-queue-incident-the-p223-first-try-got-http-401)
- [E114 GPU time in this range](#e114-gpu-time-in-this-range)
- [E115 Corrections in this range](#e115-corrections-in-this-range)
- [E116 Lessons recorded in this range](#e116-lessons-recorded-in-this-range)

## E108 Records PR #215 and the corrections post

| | |
| --- | --- |
| Date | PR #215 "research: depth-8gb P200-P219 records" opened 00:12:15Z, merged 00:14:21Z (6105d94); the post 00:16:18Z (comment 6280251682); notebook "19:16 CDT Records PR #215 (P200-P219) merged (6105d94); corrections posted" |
| What | The post starts with "**The formal R6 for bundle-20261019b is running on the 2060 as P220.**" Then "**Records:** P200-P219 are public (#215, merged). The review found claims in my posts that the receipts do not fully support": P200 (the re-read after a restart ran at ~102-157 tok/s, not ~200-300), P203 (a lower VRAM line than its reference), P206 (the 36.1 tok/s cause is open), P207 / P208 (the CPU log exists for P208 only), P211 / P212 (the exact restore is shown at line 80,128 only), P213 (the restart turns are 3.1-3.8 s slower; the 128k identity read a warm prefix), P215 (some draft sizes give the same text), P219 (the line was not pinned), and "kv-fake2v" is not a branch |
| Late item | Notebook 19:16 CDT: bundle-20261019b "was out since 17:15 CDT (my 18:39 "wait for the bundle" was late)" (E106 in `events-p200-p219.md`) |
| Links | PR #215; `events-p200-p219.md` E106 |

## E109 The formal R6 of bundle-20261019b (P220, P221)

| time (Z) | session | comment | what |
| --- | --- | --- | --- |
| 10-19 22:16:16 | release | 6278575184 | "**bundle-20261019b is out**"; "Over to your formal R6 on the zip"; a quick_tps sweep at 4k / 64k / 128k / 160k / 245k for the 8 GB numbers |
| 10-19 22:46:32 | release (Cary) | 6279028757 | Wrap-up: "this issue closes after your two pending reports" (the formal R6; P219) |
| 10-20 00:15:58 | 2060 | - | P220 starts (queue 69jecd; 19:15:58 CDT) |
| 00:16:18 | 2060 | 6280251682 | "The formal R6 for bundle-20261019b is running on the 2060 as P220"; zip 616,377,333 B, SHA-256 = the asset digest; launcher 0 control bytes |
| 01:46:08 | 2060 | - | P220 ends; P221 queued 01:47:13 (20:47:13 CDT) and runs 01:47:30-02:10:33 |
| 02:11:23 | 2060 | 6281710679 | "**R6 for bundle-20261019b on the RTX 2060 (P220 + P221): correctness and the soak PASS. The speed gate fails narrowly below the VRAM line.**" P222 runs |
| 02:14:43 | release | 6281750945 | "Agreed on both: no card change before P222." If P222 passes, bundle-20261019c sets replay + 1 / 2; if it fails, 2 / 2 stays and the cards get the P220 sweep "with the 4k / 64k cost stated" |

- The R6 post gives the sweep against the cards (4k -3.2 %, 64k -5.1 %, 128k +30.5 %, 160k +11.4 %, 245k +16.3 %), the soak
  (30/30, 1,631 s against P200's 1,842 s) and P221 (4k -3.3 %, 64k -3.7 % in one block).
- The post names the cause of the miss in P215: "det_answer uses only the code prompt, and 2 / 2 costs on prose / bash
  below the line."

## E110 The P222 decision: option B

| time (Z) | session | comment | what |
| --- | --- | --- | --- |
| 10-20 02:11:14 | 2060 | - | P222 starts (queue 69jecf; 21:11:14 CDT); it ends 02:59:37 |
| 03:02:38 | 2060 | 6282336929 | "**P222 ... replay + 1 / 2 FAILS the declared gate at 4k and 64k. It is better than or equal to the 2 / 2 default at every depth.**" "I do not move the gate after the run." Option A (keep 2 / 2, the fail branch) and option B (1 / 2, "my suggestion") |
| 03:05:21 | release | 6282369668 | "**Decision: option B.** bundle-20261019c sets the 8 GB default to replay + `BONSAI_SPEC=1` / `BONSAI_SPEC_DEEP=2`." |

- The reason on record (03:05:21Z): "the published default is already 2 / 2, and 1 / 2 is better than or equal to it at
  every measured depth (+1.0 % at 4k, +2.3 % at 64k, -0.3 % at 128k) at the same memory". The cost against the old
  recipe stays on the card: "-2.4 % at 4k, -1.7 % at 64k, +32 % at 128k".
- The card row: "4k / 64k / 128k from P222 `d12` (52.4 / 39.9 / 29.6); 160k / 245k from P220 (18.6 / 11.4: past the line
  2 / 2 and 1 / 2 both draft 2, so the step is the same). Cold reads from P220." See E115 for the 160k / 245k values.
- Notebook 22:04 CDT: "Both #138 reports done." The serve folder serve-1019b was made from the 19b zip ("0 files differ,
  models junction, same key, empty slots"). The serve notes are private and not in this repo.

## E111 bundle-20261019c and the P223 post-zip check

| time | what |
| --- | --- |
| 10-20 01:28:04Z | PR #216 merged (d2ae810): without a vision projector, the layer replaces an image in a request with a text note (issue #7) |
| 23:35-23:39 (the 4070 rig's clock, not CDT; before the publish at 03:41:20Z) | The release session's gates R1-R4 on the 4070 (`../release-20261019c/EXPERIMENTS.md`): R1 zip (every `bin/` file equal to 1019b), R2 launcher (`BONSAI_8GB=1`: `draft 1 (2 past the VRAM line)`), R3 images without mmproj, R4 saved conversations: all PASS |
| 10-20 03:40:41Z | PR #217 merged (8c10979): "bundle-20261019c: 8 GB draft 1 / tail 2; images without mmproj become a text note; 8 GB numbers" |
| 03:41:20Z | bundle-20261019c published (22:41 CDT): zip 616,414,078 B, SHA-256 e84d8c6d21deaea1... (GitHub digest) |
| 10-20 08:43:20-08:44:40 CDT | P223 try 1 (69jecg): HTTP 401 at both depths (E113) |
| 08:45:41-08:57:09 CDT | P223 try 2 (69jech) on the extract: PASS (4k 52.6, 128k 29.1 tok/s; spec "draft 1 (2 past the VRAM line)"; 0 CUDA errors) |

- The release notes give the 8 GB row 52.4 / 39.9 / 29.6 / 18.6 / 11.4 tok/s at 4k / 64k / 128k / 160k / 245k and
  "92,160 positions in VRAM".
- The check started 10 h 2 min after the release. Notebook 08:57 CDT: "I stalled ~10 h after the release (no watcher on
  the release)"; a memory note was added (feedback-wait-with-watcher).
- The serve folder serve-1019c was made from the 19c zip (its own API key, models junction, empty slots). The serve
  notes are private and not in this repo.

## E112 Issue #138 closed

| | |
| --- | --- |
| Date | 2026-10-20 03:41:32Z (comment 6282798104); the issue closed 03:41:33Z |
| What | "**Closing.** bundle-20261019c is out (latest) ... the 8 GB preset defaults to replay + draft 1 / tail 2 (P222), and the 8 GB cards and docs/8gb show the P220 / P222 numbers (52.4 / 39.9 / 29.6 / 18.6 / 11.4 tok/s at 4k / 64k / 128k / 160k / 245k, 92,160 positions in VRAM)." |
| Goal summary (post) | From bundle-20261016 on the 2060: "cold 245k read 1,695 s -> 1,480 s; decode at 128k 22.3 -> 29.6 tok/s and at 245k 9.8 -> 11.4; a 199k conversation back in ~6 s after a restart instead of a cold read". Not shipped, with records: T4 / T5 fast reads, adaptive draft depth, the draft vocab shortlist, DFlash 2 drafters, KV below 3 bits |
| Next | "New work goes into new, small issues." |

- P223 ran after the close and was not posted.

## E113 Queue incident: the P223 first try got HTTP 401

| | P223 first try |
| --- | --- |
| Queue log | 08:43:20 "run 69jecg-p223-19c-check.sh"; 08:44:40 "done" (filler c had ended 08:43:19) |
| Cause | The script served `C:/bonsai/serve-1019c`, a serve folder with its own API key. `run_arm.sh` sends the repo's key file, so quick_tps got "HTTP Error 401: Unauthorized" at 4k and 128k. Both servers loaded normally (spec line right, line 92,160, 0 CUDA errors) |
| Fix | Try 2 (69jech, file 08:45:26, run 08:45:41) serves the extract `release_1019c/x`, which holds the repo's key ("This extract has the repo key; its files equal the zip") |
| Cost | 80 s of a job slot; filler a was stopped once |
| Receipts | receipts/p223_try1_401/ (kept) |

- This record writer compared the key files without reading them out: the serve folder's key differs from the repo's;
  the extract's key equals the repo's.

## E114 GPU time in this range

Queue log 18:35:35 (10-19) to 13:39:59 (10-20), 19.07 h:

| from | to | what |
| --- | --- | --- |
| 10-19 18:35:35 | 19:15:58 | fillers (0.67 h); bundle-20261019b had been out since 17:15 CDT (E108) |
| 19:15:58 | 20:46:08 | P220 (1.50 h) |
| 20:47:30 | 21:10:33 | P221 (0.38 h); filler c preempted 20:47:29 |
| 21:11:14 | 21:59:37 | P222 (0.81 h); filler a preempted 21:11:14 |
| 21:59:37 | 10-20 08:43:19 | fillers (10.73 h): the release session made bundle-20261019c (published 22:41 CDT); the 2060 did not watch for it |
| 08:43:20 | 08:44:40 | P223 first try (0.02 h; HTTP 401, E113) |
| 08:45:41 | 08:57:09 | P223 (0.19 h); filler a preempted 08:45:41 |
| 08:57:09 | 13:39:59 | fillers (4.71 h) |
| 13:39:59 | - | P224 (69jeci), the next range |

- Jobs 2.91 h, fillers about 16.2 h. No idle gap in the log.

## E115 Corrections in this range

- P220 gate 1: "prints the replay line". The bundle-20261019b launcher prints no line when replay is on; the receipts show
  replay on only indirectly (draft 2 / 2, line 92,160 against 82,432 with `BONSAI_RS_REPLAY=0`). Found by this record
  writer.
- P220 gate 2 compared with card numbers from other days and bundles. P221 is the in-block read; its gate was written
  after P220's result (and before its own run).
- P222, #138 03:02:38Z: "server 7,488 MiB on load for both": the d12 4k server shows 7,486 MiB (its idle reading was
  2 MiB higher); "used" is 7,698 MiB for all d12 and def servers. Found by this record writer.
- P222, #138 03:02:38Z: "a uniform ~2.2 % at 4k and ~1.6 % at 64k": per prompt 2.1-2.5 % and 1.6-1.7 %. Found by this
  record writer.
- bundle-20261019c release notes and the decision (03:05:21Z): the 160k / 245k values (18.6 / 11.4 tok/s, "the same"
  against 19b) are P220's 2 / 2 numbers. Draft 1 / tail 2 was not measured at 160k or 245k; "past the line 2 / 2 and 1 / 2
  both draft 2, so the step is the same" is a reason, not a measurement. Found by this record writer.
- #138 03:41:32Z: "decode ... at 245k 9.8 -> 11.4" is the same P220 2 / 2 value. "cold 245k read 1,695 s -> 1,480 s" uses
  P220's time to first token of the 245k code prompt (1,479.66 s, 243,896 tokens evaluated); the wrap-up (22:46:32Z) gave
  1,489 s (P156c). Found by this record writer.
- P213 / P222: P213 A found no replay cost at 4k (det code, pinned line: 53.4 off, 53.3 on). P222's quick_tps shows a
  step cost of 1.6-2.5 % below the line at the same acceptance. The P222 post says: "the two measurements do not agree
  fully; quick_tps is the in-block number." A line is added under P213's "Corrections later".
- P215: its 4k gain of 2 / 2 (55.6 against 53.3) is on the code prompt only (det_answer). On code / prose / bash, 2 / 2 is
  -3.3 % at 4k and -3.7 % at 64k (P221). A line is added under P215's and P217's "Corrections later".
- P223 try 2: the 4k server got line 91,648, not 92,160 (7,786 MiB free at start). Found by this record writer.

## E116 Lessons recorded in this range

- P220 / P221: read a speed gate from an in-block A/B against the old recipe, not from card numbers of other days.
- P215 / P221: measure a draft-size change on several prompt types (code, prose, bash). One code prompt hid a -4 % to
  -8 % cost on prose and bash.
- P222: when a change with two parts fails, split the parts in one block (here: draft below the line, draft past the
  line, replay).
- P222 / E110: a declared gate that fails stays failed. A new comparison can still support a release choice, if the post
  says that it is a new comparison.
- P223 / E113: run a post-zip check on the extract with the key that the bench sends, or pass the serve folder's key.
- E111 (notebook 08:57 CDT): watch the release with a watcher, so the post-zip check does not wait ~10 h.
