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
