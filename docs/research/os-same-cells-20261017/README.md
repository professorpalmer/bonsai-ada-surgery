# Windows vs headless Linux at the same cells (RTX 3080 Ti, 12 GB), data by @kokuwhite

Source: issue #35 (comments of 2026-10-17 13:38Z and 14:07Z), measured and reported by **@kokuwhite**, cited here with
permission. Card: RTX 3080 Ti 12 GB (sm_86), Ryzen 7 5800, 46 GiB RAM.

**Build per column**
- Linux: `build/build_linux.sh` from `16b67a7` (bundle-20261017b, 66 patches), `BONSAI_CUDA_ARCH=86`, Ubuntu 24.04.5
  headless, driver 595.91.07.
- Windows: the released `bonsai-bundle-win-x64.zip` of bundle-20261017b (`16b67a7`), started with the flag line below
  (not the launcher).
- Both: `-c 262144 -np 1 --kv-vram-cells 117248 --cache-type-k q4_0 --cache-type-v q4_0 -ctkd q4_0 -ctvd q4_0 -ub 256
  --spec-type ngram-mod,draft-mtp --spec-draft-window 16384 --fa on`; weights
  `Ternary-Bonsai-2-27B-Abliterated-v2-PQ2_0-MTP.gguf` (not the bundle's default model file, so the absolute tok/s
  are for that file; the comparison holds because both sides used it).

## Decode, tok/s, 117,248 cells on both sides

| depth | probe | Linux run 1 | Linux run 2 | Windows | Linux vs Windows |
| --- | --- | --- | --- | --- | --- |
| 0 | list160 | 131.3 | 132.0 | 127.3 | +3.6 % |
| 0 | prose | 77.1 | 77.4 | 73.2 | +5.8 % |
| 0 | needle | 108.9 | 108.8 | 100.3 | +8.5 % |
| 120k | list160 | 105.8 | 105.9 | 96.4 | +9.8 % |
| 120k | prose | 52.0 | 52.0 | 47.7 | +8.9 % |
| 120k | needle | 67.9 | 67.7 | 62.0 | +9.1 % |
| 180k | list160 | 65.4 | 64.2 | 61.7 | +4.0 % |
| 180k | prose | 33.0 | 32.3 | 30.7 | +5.5 % |
| 180k | needle | 43.1 | 42.3 | 39.6 | +6.9 % |
| 240k | list160 | 37.8 | 37.0 | 36.3 | +1.8 % |
| 240k | prose | 20.8 | 20.3 | 19.8 | +2.7 % |
| 240k | needle | 24.4 | 23.9 | 23.4 | +1.8 % |

(Linux vs Windows uses Linux run 2.) Run-to-run spread on Linux: at most 2.2 %. Identity hashes identical on all three
runs (list `732be90e...`, needle `14c29ea8...`); needle 4/4 on every run.

## Full prefill (each depth's first request, no cache hit), tok/s

| depth | Linux | Windows | gap |
| --- | --- | --- | --- |
| 120k | 814 | 794 | +2.5 % |
| 180k | 645 | 630 | +2.4 % |
| 240k | 539 | 525 | +2.7 % |

## The old pair, for contrast (`adfffbe` + 49 patches, both at 117,248 cells)

| depth | probe | Windows (old) | Linux (old) | gap |
| --- | --- | --- | --- | --- |
| 180k | list160 | 50.3 | 69.8 | +38.8 % |
| 180k | prose | 20.4 | 28.8 | +41.0 % |
| 180k | needle | 28.4 | 38.6 | +36.3 % |
| 240k | list160 | 34.7 | 42.5 | +22.5 % |
| 240k | prose | 16.2 | 19.9 | +22.8 % |
| 240k | needle | 19.0 | 22.6 | +18.9 % |

(The old Windows numbers used that revision's launcher recipe; the new ones the explicit flag line.)

## Reading

On bundle-20261017b, at the same cells, the OS costs a few percent: 2-10 % in decode (largest at 120k, smallest at
240k) and 2.4-2.7 % in prefill. The 20-40 % gap of the old pair came from the engine, not from the OS: the likely main
cause is patch 0053 (CUDA graphs had blocked the tiered-cache prefetch; +26 % decode at 192k on an RTX 4070 under
Windows), which acts on the host-tail path that the old Windows column paid for at 180k / 240k. For sizing: a
headless Linux install keeps about 1 GiB more VRAM free than a Windows desktop on the same card (#35, first post),
which buys more cells; at equal cells the speed is close.
