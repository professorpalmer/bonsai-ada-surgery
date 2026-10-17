# Spill guard: results

## G1 offline (2026-10-17): PASS

The `$SpillGuard` block taken from the launcher by its AST and run in a runspace (scratch g1_spill.ps1, g1_live.ps1):

- Launcher parse: 0 errors.
- Fake samples (MiB): 2604 -> 2700 -> 2804 (+200): 0 lines. 2604 -> 2700 -> 2900 -> 3000 -> 3504: 2 spill lines
  (+296, +900), the NVIDIA hint once. 2604 -> 2500 -> 2805: the base follows the drop, 1 line (+305).
- Found while testing: a counter path with no match returns no samples (no exception), which would make a base of 0
  and a false line on the next sample. Fixed: a sample with no counter values is skipped.
- Real mode on a running llama-server (Mirai test root, 41aa200a0, :18080 health): 20 s at a 2 s period, threshold
  256: 0 lines, 0 errors; threshold -1 (to prove sampling): the line printed after the second sample, through the
  parent's stdout (so it also reaches a redirected log).

G2-G4 need the GPU (the 4070 is lent to the T4 work tonight) and the 2060.

## G2 / G3 (4070, 2026-10-17 01:53-02:26; `sg_gates.sh`, log `g2g3.log`)

Root: the bundle-20261017 zip (engine 96f6e49cdc) + this branch's launcher; layer off.

- **G2 PASS.** 8 GB preset, line 80,640, cold 128k + 400-token decode, alternated:
  guard on 756.8 / 45.2, off 756.0 / 45.1, on 756.3 / 45.5, off 756.4 / 45.5 (prefill / decode tok/s): no cost.
  Default 12 GB recipe, guard on: 737.4 / 77.4. 0 spill lines and 0 CUDA errors in all 5 runs.
- **G3 FAIL (the guard does not see this slowdown).** 8 GB preset, line 80,640; after `/health` a torch ballast took
  4,076 MiB (the card at 53 MiB free). The cold 64k read: **78.9 tok/s** prefill (757 normal; 853 s wall); decode
  normal (77.6). 0 spill lines. During the read the server's counters did not move: shared 2,790 MiB (the T1-g base
  2,604), local = dedicated = 7,810, non-local = shared; the ballast: 126 MiB shared. So this slowdown is not the
  T1-g shared-usage spill; the memory counters do not show it. 0 "growing ... failed" lines in the server log.

Next: a second signal for "the card became full after the start": the other processes' dedicated VRAM on the same
adapter grew by > 512 MiB since the base AND the adapter has < 512 MiB free. (G3 here: +4,187 MiB, 19-53 MiB free.)
New gates before it ships: G1 again (fake samples), G3 again (the line within 30 s of the ballast), G4 on the 2060
(defaults: no line during a cold 128k read, where the free VRAM falls to ~76 MiB but no other process grows).

## v2: two signals (2026-10-17 02:40), G1 again: PASS

The watcher now also reads the other processes' dedicated VRAM on the server's adapter (same luid) and the free VRAM
(nvidia-smi). Line (2): others > base + 512 MiB AND free < 512 MiB (again after each further 1024 MiB).
Fake samples (shared, others, free MiB): A (+200, +200, 300): 0 lines; B (shared +296 / +900): 2 lines + hint;
C (the G3 numbers: others +4,187, free 19): 1 line + hint; D (others +4,187, free 3,000): 0; E (the 2060 normal case:
free 76-113, others flat): 0; F (free unknown): 0. 0 runspace errors. Launcher parse 0 errors.
Live values from the code on the product server (12 GB default recipe): shared 4,550, others 4, free 438 MiB
(the 12 GB recipe runs with < 512 MiB free, so signal (2) depends on the others' growth, as designed).
Open: G3 again on the 4070 (needs a 3-min GPU gap), G4 on the 2060.

## G4 on the 2060 (P166, #138) and v3 of rule (2)

- G4a PASS: defaults, cold 128k 530.77 s (P163 529.28 s, +0.3 %), decode 23.5; 0 spill lines; min free 85 MiB.
- G4b not triggered, and it found a gap: with the server up the 2060 had only **282 MiB free**, so the ballast was
  182 MiB (below the 512 MiB rule); 0 lines, but the cold 16k read after it ran at **198.7 tok/s, about half** of the
  normal ~380-410. On 8 GB a small program already costs 2x.
- v3 (rule (2) scales with the free VRAM at the base, F0): others >= base + 128 MiB AND free < min(512, 0.6 x F0);
  again after each further 512 MiB. G1 again: P166 numbers (F0 282, others +182, free 87): 1 line; 4070 12 GB product
  (F0 438, others +150, free 288): 0; a 2060 cold read (F0 282 -> free 85, others +20): 0; the G3 numbers: 1 line;
  others +4,187 with 3,000 free: 0. Case A of v2 (others +200, free 300 of F0 4,000) now gives a line: under v3 that
  is a true warning (another program took 200 MiB and 300 MiB is left), so its expectation changes; recorded here.
- Open: G3 on the 4070 (3-min GPU gap), P166b on the 2060 (1,500 MiB ballast), and G4b again with v3.

## P166b (2060, v2 launcher) and v4

- P166b: a 1,500 MiB ballast after `/health` (free 305 -> 119 MiB): no spill line, then the next read **crashed the
  server** (`CUDA error: out of memory`, ggml-cuda.cu:110; the client saw a reset). Reading: the ballast cannot be
  resident on a card with 305 MiB free, so WDDM pages it out and its Dedicated Usage stays small; rule (2) summed the
  others' Dedicated Usage, so it never saw +1,500.
- v4: rule (2) sums the other processes' **Total Committed** on the server's adapter (resident or not). G1 cases
  unchanged (fake values); live: on the 4070 the dGPU adapter has only the server's committed memory (16,132 MiB,
  pinned host included), the other processes are on the iGPU adapter. A crash cannot be prevented by a warning, but
  with v4 the line should come first (15 s period). G3 (4070) and P167 (2060) to confirm.
