# Handoff 1: speculation A/B. Frozen copies of the running server's launch (PID 3076, started 2026-09-27 07:42:14
# by start-server.ps1 @ 2519e99). Nothing here is sized at launch: every value is pinned to what A runs with.
# The API key is read from artifacts\api_key.txt at launch time and never written anywhere else.
$Root = 'C:\Users\pwall\Projects\bonsai-2-27b-serve'
$Bin  = Join-Path $Root 'bin'
$Model = Join-Path $Root 'models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf'

# The only process environment variable A's launcher sets. Kept in B so single-token decode runs the same
# (batch-invariant) PTQ1_0 mat-vec and FA split arithmetic as A's verify batches.
$ArmEnv = @{ GGML_CUDA_BATCH_INVARIANT = '1' }

# A's command, in A's order. --kv-vram-cells is pinned (the launcher would re-derive it from free VRAM).
$Pre = @('--kv-vram-cells', '113152')
$Spec = @('--spec-type', 'draft-mtp', '--spec-draft-n-max', '2', '-ctkd', 'q8_0', '-ctvd', 'q8_0',
          '--spec-draft-window', '16384', '--spec-draft-n-max-tail', '4')
$Post = @('--backend-sampling',
          '--reasoning-budget-message', 'Now produce the complete answer.',
          '--reasoning-effort-allow', 'medium', '--reasoning-effort-fallback', 'medium',
          '--reasoning-max-tokens-floor', '24576',
          '--chat-template-kwargs', '{\"reasoning_effort\":\"medium\"}',
          '--reasoning-budget', '20480', '-n', '24576',
          '-m', $Model, '-ngl', '99', '-fa', 'on', '-c', '262144', '-np', '1', '-b', '2048', '-ub', '512',
          '-ctk', 'q8_0', '-ctv', 'q8_0', '--host', '0.0.0.0', '--port', '8080', '--alias', 'bonsai-2-27b',
          '--jinja', '--prio', '2', '--poll', '100', '--metrics')
$Tail = @('--temp', '1.0', '--top-p', '0.95', '--top-k', '20')   # after --api-key <key>, as in A

function Get-ArmArgs([string]$Arm, [string]$Key) {
    switch ($Arm) {
        'A' { return $Pre + $Spec + $Post + @('--api-key', $Key) + $Tail }
        'B' { return $Pre +         $Post + @('--api-key', $Key) + $Tail }   # B = A minus the six speculative options
        default { throw "arm must be A or B" }
    }
}
