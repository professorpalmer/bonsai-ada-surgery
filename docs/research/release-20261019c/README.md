# Release bundle-20261019c (8 GB: draft 1 / tail 2; images without a vision projector)

Plan written before the runs. No engine change: every `bin/` file of bundle-20261019b (engine `810d93e5aa`). Changed:
the launcher (the 8 GB preset drafts 1 below the VRAM line and 2 past it, with replay; it was 2 / 2), the layer (#216:
without a vision projector, image parts become a text note), and the 8 GB numbers in the docs and cards (#138 P220 /
P222). The cards are rendered again before the zip is made.

Evidence for 1 / 2 (RTX 2060 SUPER, #138 P222, one block, a fresh server per arm and depth): against bundle-20261019b's
2 / 2, 4k +1.0 %, 64k +2.3 %, 128k -0.3 %, at the same memory; against the old 1 / 1, 4k -2.4 %, 64k -1.7 %, 128k +32 %.
P222's own declared gate (within 1 % of 1 / 1 at 4k / 64k) failed; the choice of 1 / 2 over the published 2 / 2 is
recorded on #138 (option B).

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | outside `docs/` the same entries as bundle-20261019b; every `bin/` file identical to 1019b; changed outside `docs/`: `start-server.ps1`, `layer/bonsai_layer.py` (and `README.md`); 0 control-byte files; 0 broken relative links (the 1019b rule) |
| R2 launcher | (8 GB arms with the 2060 line 90,112 pinned, so the launcher draws a line on the 4070) `BONSAI_8GB=1`: `spec draft 1 (2 past the VRAM line)`, the replay line; `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`: `draft 1 (1 past ...)`, no replay line; default (12 GB): `draft 2 (4 past ...)`, no replay line. Each: health ok, a short greedy answer, 0 CUDA errors |
| R3 images without mmproj | default 12 GB, layer on, no mmproj: a chat request whose tool message carries an `image_url` part answers 200 with text and `layer.images_removed` = 1; the same request sent straight to llama-server answers 500 (the control); 0 CUDA errors |
| R4 saved conversations | `BONSAI_8GB=1` (defaults), layer, slot folder: 3 turns of a 20k conversation, then two conversations that take turns (each turn 2 restores its own save); 0 CUDA errors |

R5 (slot files) and R6 (12 GB speed) carry over from release-20261019b: the engine and the 12 GB path are the same.
All pass: publish as the latest release. Any fail: no publish; log why.
