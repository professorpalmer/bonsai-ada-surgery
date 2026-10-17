# Spill guard: tell the user when VRAM spills to system RAM (2026-10-17)

## Problem

On Windows the NVIDIA driver's default "sysmem fallback" moves GPU memory to system RAM when the card is full. The
server does not fail; it becomes 10-20x slower with no message. Measured (coldread-20261016 T1-g, RTX 4070, the 8 GB
preset with the VRAM line pinned at 80,640 and 7.06 GB free): a cold read at ~40 tok/s instead of 757, and the
server's "GPU Process Memory \ Shared Usage" ~950 MiB above its start value. A browser, a game or a second model
that takes VRAM after the server starts puts an 8 GB card in this state.

## Change

(v1 below; the code is now v5: two rules, two samples in a row for rule (2), see EXPERIMENTS.md "v5".)


The launcher starts a small background watcher (a PowerShell runspace in the launcher process, so its message goes to
the same console or log). It finds the llama-server process, waits for `/health`, takes the server's Shared Usage
then as the base value (the pinned host part of the tiered cache is in it), and samples it every 15 s. When Shared
Usage is more than 256 MiB above the base, it prints one warning line (again only after a further 512 MiB):
`spill  VRAM spilled to system RAM (+N MiB): the server is much slower now. Close other GPU programs, or set
BONSAI_KV_VRAM_CELLS lower, then restart. (NVIDIA Control Panel > Manage 3D settings > CUDA - Sysmem Fallback
Policy: Prefer No Sysmem Fallback makes it fail at start instead.)`
`BONSAI_SPILL_GUARD=0` turns it off. Without the performance counters (other OS language, no permission) it does
nothing. README: one row and the NVIDIA setting.

## Gates (declared before the runs)

- G1 offline: the launcher parses; the watcher function with fake samples prints exactly one line at +300 MiB, none
  at +200 MiB, a second line at +900 MiB; counters missing -> no output, no error.
- G2 4070, no squeeze (the 8 GB preset, line 80,640, then the default 12 GB recipe): cold 128k read + decode sweep:
  0 spill lines; cold read speed and decode within 2% of the same run with `BONSAI_SPILL_GUARD=0` (the watcher cost).
- G3 4070, squeezed (ballast: a second process takes VRAM after the server start, as T1-g): the spill line appears
  within 30 s of the slowdown.
- G4 2060 (8 GB, the 2060 agent): the zip launcher with defaults, a cold 128k read: 0 spill lines; and one squeezed
  arm: the line appears.

## Amendment (before the GPU runs)

- Limit: the base is the server's shared usage at the first good `/health`, so a spill that happens at load (a VRAM
  line pinned above the free VRAM, as in T1-g) is in the base and gives no line. The launcher's own line is sized
  from the free VRAM at start, so this needs a pinned line or a program that grows between the check and the load.
  The guard covers the case the README names: VRAM taken after the start.
- G2 arms alternate guard on / off / on / off (8 GB preset, line 80,640, layer off, cold 128k + decode via
  quick_tps), then one default 12 GB arm with the guard on.
- G3: the 8 GB preset, line 80,640; after `/health` a torch ballast takes all but ~100 MiB of the free VRAM, then a
  cold 64k read (the compute pool grows into a full card). PASS: if the read is slower than G2 by > 3x, the spill line
  is in the launcher log; if the read is not slow (the ballast spilled, not the server), G3 is inconclusive and is
  reported as such.
