# GDN replay: one recurrent-state plane instead of one per draft token (2026-10-18)

## Problem

Bonsai 2 27B is hybrid: 48 gated-delta-net (GDN) layers and 16 attention layers. To undo rejected draft tokens, the
engine keeps one snapshot of the whole recurrent state per draft token (`n_rs_seq`). One snapshot is 149.6 MiB (S
144 MiB, conv 5.6 MiB). On the 8 GB preset (draft 1, so `n_rs_seq` = 1) the recurrent buffer is 299 MiB, and each extra
draft token past the VRAM line (`BONSAI_SPEC_DEEP`) costs another 150 MiB of VRAM, about 10,500 q3_0 KV cells
(14,336 bytes per cell). Earlier data: tail 2 gave +17 % decode at 200k but -10 % at 64k because its snapshot moved
the VRAM line from 58,112 to 49,664 cells (P80c); tail 4 was rejected on 8 GB for the same reason (P105).

## Idea (no kernel change)

Keep one S plane plus the inputs of the last P = `n_rs_seq` tokens of each GDN layer (k, v, raw gate, raw beta: 8,288
floats per token per layer, 1.6 MiB per token for all 48 layers). Each step puts these P tokens in front of the batch
and runs the existing fused GDN op over P + n tokens:

- A rejected token gets raw gate = raw beta = -inf. Then beta = sigmoid(-inf) = 0 and g = exp(a * softplus(-inf)) = 1,
  so the update S = g S + k (v - g S^T k) beta is exactly S: the token is skipped with no rounding.
- The op's snapshot slot P (the state P tokens before the end) goes to the one S plane; the last P tokens' inputs go
  to the pending buffer (rejected ones keep their -inf).
- The outputs of the P pending tokens are dropped.

Accepted tokens are replayed with the same kernel, the same inputs and the same order of operations as the step that
read them first, so the state is the same as the snapshot design's state (no replay error to bound). The conv state
(5.6 MiB a plane) keeps its snapshot planes. Slot files write the S plane, the pending inputs and the number of
rejected tokens (marked `s_trans` = 2, so an older engine refuses the file instead of misreading it).

Cost: the GDN op reads P more tokens per step (a few microseconds a layer at decode); a little more per prefill ubatch
(P of 512 more tokens plus the concatenation copies).

Saving: 8 GB preset with draft 1: 299 -> ~158 MiB (+~10,000 VRAM cells, the VRAM line 80,640 -> ~90,600). Each extra
tail token: 150 MiB -> 1.6 MiB.

Opt-in: `LLAMA_RS_REPLAY=1` (models whose GDN op takes raw gates; else the snapshot design).

## Plan and gates (declared before any run)

| Step | Check | Gate |
|---|---|---|
| R1 | build; `--version`; server starts with `LLAMA_RS_REPLAY=1`; log shows the smaller RS buffer | S buffer = one plane + pending |
| R2 | identity: greedy decode, spec on, 4k and 32k prompts, prose + code: replay vs snapshot engine (the same build, env off) | byte-identical text on every prompt; draft acceptance counts equal |
| R3 | slot save / restore with replay (incl. a save after a step with a rejected draft): restore then continue = no restore | byte-identical text |
| R4 | 8 GB preset, launcher `FixedMiB` lowered by the measured saving: VRAM line, decode tok/s at 4k / 64k / 128k / 200k, tail 1 vs replay tail 1 | line +8,000 cells or more; no depth slower by more than 3 %; 128k+ faster |
| R5 | replay with `BONSAI_SPEC_DEEP` 2 and 3 at the replay line: 64k / 128k / 200k | ship a tail > 1 default only if it beats replay tail 1 by 5 % at 128k and 200k and loses no more than 3 % at 64k |
| R6 | 8 GB release gate (the zip launcher with `BONSAI_8GB=1`, control-byte scan), 0 CUDA errors, soak 30 min | as for every release |

R1-R4 pass: replay ships on (launcher sets `LLAMA_RS_REPLAY=1` for the 8 GB preset, with the new line). R5 sets the
deep draft default. Any fail: not shipped; log why.

## Run log

R1 (2026-10-19, `r1/`, `r2_try1/`): the replay build starts with `LLAMA_RS_REPLAY=1` and reports the smaller buffer:
RS 156.77 MiB (R 11.25 + S 144.00 + P 1.52) against 299.25 MiB (the snapshot design, `n_rs_seq` 1): -142.5 MiB, as
planned. But the server faults at warm-up ("illegal memory access") when the CUDA state-gather fusion
(`ggml_cuda_try_gdn_gather_skip`, the GET_ROWS of the state folded into the GDN kernel) is on; with
`GGML_CUDA_GDN_GATHER_FUSION=0` it starts. Not the cause (tested): CUDA graphs, the Hadamard q8 fusion, the KV tier
(a 32k window without tier also faults), the kernel's row read (a temporary gather with the GET_ROWS still skipped also
faults). Open item; the snapshot design keeps the fusion.

R2 deviation (declared before its run): both arms (snapshot and replay, the same build) run with
`GGML_CUDA_GDN_GATHER_FUSION=0`, so the identity test compares only the rollback design. The fusion's speed share is
measured in R4.

### R2 result: FAIL — not shipped (`r2/`)

Both arms with the gather fusion off; 4k / 32k / 100k, story / code / quote, T 0 and 0.8 (seeded), 300 tokens, 0 CUDA
errors. Identical text in 3 of 18 requests (both 4k quote, 32k quote T 0); draft counts differ by a few in most. Speed:
replay 1-7 % slower (4k code 82.3 -> 78.9, 32k story 70.5 -> 65.4, 100k code 47.8 -> 47.4).

Why (hypothesis, tested next as R2b): the CUDA GDN op runs a prefill ubatch in 64-token MMA chunks and only its last K
tokens in the per-token kernel. Putting the P pending tokens in front of the batch moves every chunk boundary by P, so
the prefill rounding differs and greedy text diverges later. The per-token replay of accepted tokens is exact by
construction. The speed loss is the graph form: about 13 small kernels per GDN layer (concats, adds, copies), ~600
more launches per step.

R2b (declared before its run): the same build and requests at 4k and 32k with `GGML_CUDA_GDN_MMA_DISABLE=1` in both
arms (every token through the per-token kernel). If the text is byte-identical in all 12, the hypothesis holds and the
next design is in-kernel replay: the GDN kernel reads and skips the pending tokens itself before the batch (the MMA
chunks then stay where they were) and writes the new pending inputs, with no extra launches. Any difference: replay
itself is not exact; find why before any further design.

### R2b result: the hypothesis holds (`r2b/`)

With `GGML_CUDA_GDN_MMA_DISABLE=1` in both arms: identical text in 12 of 12 requests (4k and 32k, story / code / quote,
T 0 and 0.8), and identical draft counts in all 12. The replay arithmetic is exact; the R2 differences came only from
the MMA chunk boundaries. Speed in this mode: replay 3-7 % slower (the graph form's extra launches).

## Design 2 (declared before its runs): in-kernel replay

The graph keeps the production form (state gather -> GDN op -> state copy). The GDN op gets the pending inputs as an
extra source and the rows / skip counts as an extra input; the CUDA kernel:

1. runs the P pending tokens first from the S plane (a rejected token is skipped, not computed), no outputs;
2. runs the batch as today (MMA chunks over the first n - (P + 1) tokens, the per-token kernel over the last P + 1,
   the same boundaries as the snapshot design), writing outputs;
3. writes the state after the first batch token of that per-token tail (the commit point: P tokens before the end)
   instead of P + 1 snapshot slots, and the last P tokens' inputs to a pending tail of its output, which one copy per
   layer moves into the pending buffer.

Gates: R2' = R2 (4k / 32k / 100k, MMA on, the gather fusion on in both arms): identical text and draft counts in all 18;
R2'' speed: no request slower than the snapshot design by more than 3 %; then R3-R6 as declared above.

### R2' result (design 2): PASS (`r2p/`)

The in-kernel replay build (`serve/gdn-replay`), both arms with production settings (MMA chunks on, the CUDA state-
gather fusion on: design 2 keeps the production graph form, so the fusion fault of the graph form does not arise):
identical text and identical draft counts in 18 of 18 requests (4k / 32k / 100k, story / code / quote, T 0 and 0.8).
Speed at the same VRAM line (80,640): replay -0.8 % to +1.3 % (worst 4k quote T 0.8, 139.1 -> 137.9); R2'' PASS. The
recurrent buffer is 157 MiB instead of 299 MiB; this run does not yet use the freed VRAM.

## R4 / R5 (declared before the runs)

The 142 MiB buys 142 MiB / 14,336 B = 10,386 q3_0 cells: the replay VRAM line is 80,640 + 10,240 = 90,880 (whole 256
blocks). Arms on the 8 GB preset (`BONSAI_8GB=1`, layer off, `BONSAI_KV_VRAM_CELLS` pinned so that the split matches
the 8 GB card): S1 snapshot design, line 80,640, tail 1 (today's default); R1 replay, line 90,880, tail 1; R2t replay,
line 90,624, tail 2; R3t replay, line 90,624, tail 3. Decode of a 300-token greedy story (no prompt cache) at 4k, 64k,
128k and 200k; tok/s from the server timings.

| Gate | Condition |
|---|---|
| R4 | R1 vs S1: no depth slower by more than 3 %; 128k and 200k faster |
| R5 | a tail > 1 default only if R2t or R3t beats R1 by 5 % at 128k and at 200k and loses no more than 3 % at 4k and 64k |

The VRAM accounting on a real 8 GB card (the launcher's sizing with `BONSAI_RS_REPLAY=1`) is checked in R6 on the
RTX 2060 path before any default change.

### R3 result: PASS (`r3/`)

Turn 1 (a 20k or 60k log + a 150-word story, greedy, drafting on), a full slot save, turn 2 in memory; restart,
restore, turn 2 again. Replay: the restored turn 2 equals the in-memory turn 2 at 20k (27,404 tokens restored, 30
read) and at 60k (83,682 restored, 31 read). The snapshot design gives the same text in all four runs (the two designs
match each other too). 0 CUDA errors. The replay slot file (`s_trans` 2) holds the S plane, the pending rows with their
valid count, and the rejected count of the save.

### Peer review of design 2 (2026-10-19)

No blocker for one sequence per context (the server's one slot): no race in the kernel's pending writes; P > 1,
n < P, L < P, fresh cells, save/restore with several cells, the cache and gather fusions and the MMA tail all check
out. Found and fixed: (1) blocker for several sequences: when find_slot relocates cells, only their S rows move, not
their pending rows -> replay now turns on only with one sequence per context (`n_seq_max == 1`); (2) partial offload:
the op is CUDA only -> replay turns on only when every recurrent layer sits on a GPU device; (3) unused pending slots
(fewer than P combined tokens) held old memory -> the kernel writes zeros there. Kept as is: a rollback deeper than
the valid pending count clamps to 0 (the snapshot design reads stale planes in the same case).

R4 first try (`r45_try1/`, void): the depth prompts were mis-sized (20.6 tokens a record, not 15): the "64k" request
held 87,681 tokens, "128k" 176,337, and "200k" was over the window (HTTP 400). Stopped; the review fixes were built
first. R4/R5 run again on the fixed build with calibrated prompts (same arms and gates). Partial data from the void
try: S1 / R1 at 5.3k 80.2 / 81.0 tok/s; S1 at 88k 58.5, at 176k 23.7.

Default path check: the snapshot arm of R2' (design-2 kernel, `LLAMA_RS_REPLAY` unset) and the snapshot arm of the
first R2 try (the production kernel; both with the gather fusion on) give identical text and draft counts in 18 of 18
requests. The kernel change does not touch the default path.

### R4 / R5 results (`r45/`): R4 PASS; R5: tail 1 stays

Decode tok/s, 300-token greedy story, prompts of 3,874 / 63,579 / 128,119 / 200,758 tokens; 0 CUDA errors.

| depth | S1 snapshot, line 80,640 | R1 replay, line 90,880 | R2t replay tail 2 | R3t replay tail 3 |
|---|---|---|---|---|
| 4k | 80.8 | 81.8 (+1.3 %) | 81.0 | 77.6 |
| 64k | 70.1 | 70.5 (+0.6 %) | 70.3 | 70.8 |
| 128k | 42.4 | **46.7 (+10.3 %)** | 48.5 (+3.8 % vs R1) | 44.9 |
| 200k | 20.1 | **21.3 (+6.0 %)** | 21.2 (-0.5 % vs R1) | 21.4 (+0.7 % vs R1) |

R4 PASS: no depth slower, 128k and 200k faster. R5: no tail beats R1 by 5 % at both 128k and 200k (tail 3 also loses
5.2 % at 4k), so tail 1 stays. One run per cell (about +-1 % between runs). Text: identical across all arms at 4k and
64k (inside both lines; tail 2/3 change the MMA chunking at 4k, so those texts differ, as with the snapshot design);
past the line the arms differ because the sparse host-tail reads depend on where the line sits.

Decision: replay ships as an opt-in (`BONSAI_RS_REPLAY=1`, engine + launcher) in the next bundle; it becomes the 8 GB
default only after R6 on the RTX 2060 (the launcher's own sizing on a real 8 GB card, soak, release gate), since this
machine has only the RTX 4070.
