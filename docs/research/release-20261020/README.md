# Release bundle-20261020 (the layer says why a conversation is read again; the layer log is kept)

Plan written before the runs. No engine change: every `bin/` file of bundle-20261019c (engine `810d93e5aa`). Changed
outside `docs/`: `layer/bonsai_layer.py` and `start-server.ps1` (#224, issue #7). The layer writes one line when a chat
request does not repeat the previous one up to its end (the tool list with the tool names, a message, or its
reasoning), and a failed vision probe keeps the last answer. The launcher sends the layer's log to `logs\layer.log`
(UTF-8; the last run's log becomes `logs\layer.prev.log`). Before, the hidden layer process had no console and its log
lines were lost. The zip is made so that a user does not have to copy files from `main` (issue #7).

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | outside `docs/` the same entries as bundle-20261019c; every `bin/` file identical to 1019c; changed outside `docs/`: `start-server.ps1` and `layer/bonsai_layer.py` only (plus `README.md` if it changed); 0 control-byte files; 0 broken relative links (the 1019b rule) |
| R2 launcher | three arms on the zip root, the layer on: default (12 GB): `spec draft 2 (4 past ...)`; `BONSAI_8GB=1` with the 2060 line 90,112 pinned: `spec draft 1 (2 past the VRAM line)` and the replay line; `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`: `draft 1 (1 past ...)`, no replay line. Each: health ok, the `layer log:` line, `logs\layer.log` exists, a short greedy answer through the layer, 0 CUDA errors |
| R3 layer log | default 12 GB, layer on, no mmproj, through the layer: a turn added at the end gives no prefix line; one tool removed gives the tool-list line with that tool's name; an edited earlier message gives the message line; an image answers 200 and gives the note line. All lines in `logs\layer.log`; after the next launcher start the old log is `logs\layer.prev.log`; 0 CUDA errors |
| R4 saved conversations | `BONSAI_8GB=1` (defaults), layer, slot folder: 3 turns of a 20k conversation, then two conversations that take turns (each turn 2 restores its own save); 0 CUDA errors (the layer changed, so this runs again) |

R5 (slot files) and R6 (speed) carry over from release-20261019c and 20261019b: the engine and the draft settings are
the same. All pass: publish as the latest release. Any fail: no publish; log why.

## Results (2026-10-20 20:54-20:57, RTX 4070, `release_1020.log`)

Zip sha256 `ef7ba67035fab930...`, engine `810d93e5aa`. Scripts: `rel1020.sh` (the gates), `e2e_req.py` (the R3
requests), `make_bundle_1020.py` (the zip). The layer log of R3: `r3_layer.log`.

| Gate | Result |
|---|---|
| R1 zip | PASS: outside `docs/` the same entries as 1019c, every `bin/` file identical; changed: `README.md`, `layer/bonsai_layer.py`, `start-server.ps1`; new in `docs/`: the fixed and week cards (4 files); 0 control-byte files; 0 broken relative links |
| R2 launcher | PASS: 8 GB `draft 1 (2 past the VRAM line)` with the replay line; 8 GB replay off `draft 1 (1 past ...)`, no replay line; default `draft 2 (4 past ...)`, no replay line. Each: health ok, the `layer log:` line, `logs\layer.log` exists, the answer, 0 CUDA errors |
| R3 layer log | PASS: the turn added at the end gave no line; one tool removed gave "the tool list changed (removed x64dbg_list)" (the server's f_keep 0.144 on that request); the edited first user message gave "message 1 (user) changed"; the image answered 200 and gave the note line; after the next start `layer.prev.log` holds the 3 prefix lines; 0 CUDA errors |
| R4 saved conversations | PASS: 3 turns of a 20k conversation (18.8 / 8.3 / 8.8 s, 1-3 slot files); two conversations that take turns: turn 2 restored its own save (25 and 24 new tokens); index 6 entries, 3 deltas; 0 CUDA errors |

All gates pass: publish as the latest release.
