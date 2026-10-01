```text
BONSAI SERVING HANDOFF 1
Status: prepared
Active server changed: no (PID 3076, started 2026-09-27 07:42:14, slot idle at inspection; tunnel PID 10392 untouched)

Model alias and file SHA-256:
  bonsai-2-27b -> models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf, 6,397,970,272 B
  sha256 5f212d02ff57cb8eaad260fd7ff57bfaff87ae2bc9183a21dd2f127c27252505
  single file, no shards/adapters. arch qwen35, 65 blocks (64 trunk + 1 nextn/MTP), file_type 143 (PTQ1_0,
  1.75 bpw ternary, group 128). Tensors: 402 PTQ1_0, 96 BF16, 360 F32, 8 Q8_0 (the Q8_0 tensors are the
  ProCreations MTP head, blk.64 nextn, in the SAME file; no separate draft model).
  GGUF sampling metadata: temp 1.0, top_p 0.95, top_k 20.

Executable SHA-256 and reported build:
  reported build b10768-8ecc788d5 (MSVC 19.44.35228.0, x64). The exe is a 10 KB stub; code is in the DLLs.
  Modules loaded by PID 3076 (all built 2026-09-27 02:21-02:24):
    llama-server.exe       9e68473ccb675424a9495c57b479027aa9e0926c4757f846f7f113d269b4ab37
    llama-server-impl.dll  b5b3ac600b872267dff8b23bdb590b8a59d94214cbd0619a2f7db2bec7629ae5
    llama-common.dll       c083ee6359d806aeba2e927c88173e6623f1cbd1339b6a8b7c1d48e51822a67e
    llama.dll              8492d60e8792f0ac46ede3a35b032ee75eb983ecd06d314d8fb670b912eda4a2
    ggml.dll               1ddda108c832dfff3d104ddd3839e8281936429625c2200dba2216142f280894
    ggml-base.dll          bdf1eece9dfb55a304b596a211cadf240541cb4b710e803787f69f245f8fbaa1
    ggml-cpu.dll           bc2b44cec881e0def4d062cd303771002d15fba9595793a1ff2a78802c713206
    ggml-cuda.dll          cc0f56f13aa654adc0d5e7dfae3ffbf8a1591f4b479e3d22614b2237c069c594
    mtmd.dll               9655bd93cc2f58a1c85d9b10eebaf9f87df5c34e35bfaafe56d340261ba57679
    cublas64_13.dll        60bbba8868290311e9c1657b2193ddec667744eb555ff843f87acb7c039f9efa
    cublasLt64_13.dll      cad63434448e7141629e240ea093ad596a7ef6a0f67b468ba9bc1df6e1eeee33

Repository URL, full commit, dirty state, binary/source correspondence:
  Source: https://github.com/professorpalmer/llama.cpp-ada-ternary, branch bonsai-q8-product,
  local worktree %TEMP%\combo-src (clean now; HEAD c8b8993a6211db9edc4df9de9e1f8b1915d183df, build no. 10774).
  GAP: the binary reports 8ecc788d518725f99b2e6c65f18ef66ddadf6293 but was built DIRTY. The build (02:21-02:24)
  compiled uncommitted work that was committed 10 minutes later (02:34) as 6 commits,
  8ecc788d5..c8b8993a6 (tiered KV, quantized-KV MMA decode, BATCH_INVARIANT FA split, --spec-draft-window /
  -n-max-tail, harness-proofing flags, OP_TIMING). Evidence: the binary accepts options that exist only in
  those commits; every DLL in bin\ is byte-identical to %TEMP%\combo-build\bin. Not proven byte-for-byte
  against c8b8993 (no rebuild done). Best source for this binary: c8b8993a6 (also the head of fork branch
  bonsai-q8-product and of PrismML-Eng/llama.cpp#285). Serve repo professorpalmer/bonsai-ada-surgery main
  5158a8d, clean; launcher start-server.ps1 as in 2519e99 reproduces the live command exactly.

Template SHA-256 and tokenizer identity:
  chat template (from /props and GGUF tokenizer.chat_template, identical)
    ac4c9d7d9d7cee2ad2293821512633d12deced846a433b30aff0f02d9e3a312c (9,311 chars), --jinja
  tokenizer: gpt2 BPE, pre qwen35, 248,320 tokens, 247,587 merges, add_bos false
    digest sha256(tokens\n-joined \0 merges\n-joined \0 types,-joined) e084756cb7063062f6b66d09e1273627ce819e6714ad411b240d404d48a3af57
  bos/pad <|endoftext|> 248044, eos <|im_end|> 248046, <|im_start|> 248045,
  <think> 248068, </think> 248069, <tool_call> 248058, </tool_call> 248059

Context, KV-cache types, GPU/driver:
  -c 262144, -np 1 (1 slot, n_ctx 262144), -b 2048, -ub 512, -fa on, -ngl 99
  KV q8_0/q8_0, tiered: cells 0..113151 in VRAM, 113152..262143 in pinned system RAM (--kv-vram-cells 113152)
  RTX 4070 12 GB (12282 MiB; 11648 used under A), driver 610.88, display on iGPU (display_active Disabled),
  CUDA 13 cuBLAS from bin\. Memory clock offset +1500 MHz per repo notes: not re-verified here (unknown).

Current speculative method and relevant settings:
  --spec-type draft-mtp (MTP head inside the model GGUF), --spec-draft-n-max 2, --spec-draft-n-max-tail 4
  (from position 113152, the VRAM line), --spec-draft-window 16384, draft KV -ctkd/-ctvd q8_0,
  p_min 0.00 / p_split 0.10 (defaults), draft backend sampling on (default). /slots: speculative true.

Relevant attention/kernel overrides:
  env GGML_CUDA_BATCH_INVARIANT=1 (set by the launcher only when drafting; the only GGML/LLAMA var in the
  process). No other GGML_*/LLAMA_*/LLAMA_ARG_* in the process, user or machine environment.
  --backend-sampling on (grammar/tool requests fall back to CPU sampling). --prio 2, --poll 100.

Reasoning/stop/sampler (server side):
  --chat-template-kwargs {"reasoning_effort":"medium"}, --reasoning-budget 20480,
  --reasoning-budget-message "Now produce the complete answer." (injected before </think> when the budget trips),
  --reasoning-effort-allow medium, --reasoning-effort-fallback medium (any other effort word -> medium),
  --reasoning-max-tokens-floor 24576 (thinking-on requests with max_tokens below it are raised to it),
  -n 24576. Sampler defaults: temp 1.0, top_k 20, top_p 0.95, min_p 0.05, repeat/presence/frequency 1/0/0,
  dry 0, xtc 0, typical 1, mirostat 0, seed random, chain penalties>dry>top_n_sigma>top_k>typ_p>top_p>min_p>xtc>temp.
  Stop: EOS <|im_end|>; no extra server stop strings. Thinking close: </think> (248069) from the template.

Exact sanitized A launch/configuration:
  env GGML_CUDA_BATCH_INVARIANT=1
  llama-server.exe --kv-vram-cells 113152 --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0
    --spec-draft-window 16384 --spec-draft-n-max-tail 4 --backend-sampling
    --reasoning-budget-message "Now produce the complete answer." --reasoning-effort-allow medium
    --reasoning-effort-fallback medium --reasoning-max-tokens-floor 24576
    --chat-template-kwargs {\"reasoning_effort\":\"medium\"} --reasoning-budget 20480 -n 24576
    -m ...\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf -ngl 99 -fa on -c 262144 -np 1 -b 2048
    -ub 512 -ctk q8_0 -ctv q8_0 --host 0.0.0.0 --port 8080 --alias bonsai-2-27b --jinja --prio 2 --poll 100
    --metrics --api-key <REDACTED> --temp 1.0 --top-p 0.95 --top-k 20

Exact sanitized B launch/configuration:
  env GGML_CUDA_BATCH_INVARIANT=1   (kept deliberately, see below)
  identical to A with the six speculative options removed; --kv-vram-cells 113152 pinned.

A-to-B diff:
  - --spec-type draft-mtp
  - --spec-draft-n-max 2
  - -ctkd q8_0 -ctvd q8_0
  - --spec-draft-window 16384
  - --spec-draft-n-max-tail 4
  Nothing else. Unavoidable side effects of no speculation (not separately switchable):
   * no draft context (frees its 16k-row q8_0 draft KV + compute buffer, ~0.1-0.3 GB VRAM); the MTP weights
     stay loaded as part of the model
   * the target no longer exports pre-norm hidden states for the head (llama_set_embeddings_nextn off)
   * output buffer sized for 1 row per step instead of 1+4 (server_output_limits)
   * every decode step is 1 column instead of a verify batch; with BATCH_INVARIANT=1 the PTQ1_0 mat-vec
     arithmetic per column is the same, but FA attention is NOT batch-invariant (launcher comment,
     start-server.ps1:105-108), so rounding-level token differences between A and B are expected.
  Deliberately NOT done: using start-server.ps1 with BONSAI_SPEC=0. That would also unset
  GGML_CUDA_BATCH_INVARIANT and re-derive --kv-vram-cells without the draft cells (moving the VRAM line).

Why this disables every active speculative path (help/source references, fork c8b8993):
  - default types = { NONE }: common/common.h:387; --spec-type appends only when given: common/arg.cpp:4253-4259
  - GGUF auto-detect of draft-mtp runs only when a draft model path is set: common/arg.cpp:563-570
    (B sets no -md / --spec-draft-model); the HF-repo MTP sidecar discovery needs -hf (not used)
  - the server builds a spec context only when has_draft || spec_mtp: tools/server/server-context.cpp:998-1002;
    slot.can_speculate() == (spec != null): server-context.cpp:430-432; get_n_draft_max() returns 0 then
  - ngram / lookup types (-lcs/-lcd, ngram-*) are not requested in A or B; no LLAMA_ARG_SPEC_* env anywhere
  - per-request speculative.* fields are compiled out (#if 0): tools/server/server-schema.cpp:196-225,
    confirming the Mac audit: no request field changes speculation.

Rollback command/configuration (credentials redacted):
  powershell -NoProfile -ExecutionPolicy Bypass -File artifacts\experiments\spec-ab-20260928\switch.ps1 -Arm A
  (A = the exact live command; key read from artifacts\api_key.txt at launch.) switch.ps1 -Arm B restores A
  automatically if B misses /health within 300 s. Fallback: start-server.ps1 unchanged (it re-derives the
  VRAM line; with the same free VRAM it gives 113152).

Configuration-copy locations (gitignored, key never written):
  C:\Users\pwall\Projects\bonsai-2-27b-serve\artifacts\experiments\spec-ab-20260928\
    arms.ps1 (A/B definitions), run-arm.ps1 (-Arm A|B [-DryRun]), switch.ps1 (-Arm A|B),
    A.cmd.txt, B.cmd.txt, A.live-pid3076.cmd.txt (sanitized), RECEIPT.md

Endpoint unchanged: yes. Local http://<host>:8080 and the existing cloudflared quick tunnel (points at
  localhost:8080, survives a server restart; URL not reproduced here). Same key.

Other changes required or remaining unknowns:
  - binary is from a dirty tree (see above); byte-identity to c8b8993 unproven
  - GPU memory clock offset not re-verified
  - smoke check for "speculation off" in B: /slots speculative=false, server log lacks
    "speculative decoding enabled", responses carry no draft_n/draft_n_accepted, and /metrics
    llamacpp:spec_decode_num_draft_tokens_total stays flat across a request.
    Do NOT use /props default_generation_settings "speculative.types": it reads "none" under A too.
  - /props shows n_predict -1 although -n 24576 is set (display of per-request default; not investigated)

Ready for Codex to record baseline A: yes
```
