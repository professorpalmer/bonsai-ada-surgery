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
