param(
    [string]$Model,
    [string]$Name,
    [string[]]$Extra = @()
)
$ErrorActionPreference = 'Stop'
$bin = 'C:\Users\pwall\Projects\bonsai-2-27b-serve\bin'
$out = "C:\Users\pwall\Projects\bonsai-2-27b-serve\artifacts\cli_$Name.out"
Set-Location $bin
$prompt = 'Write a detailed explanation of why memory bandwidth, not FLOPs, usually limits batch-1 LLM decode. Include a short numeric example with 7 GB weights and 500 GB/s bandwidth.'
$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = '{"enable_thinking":false}'
$args = @(
    '-m', $Model, '-ngl', '99', '-fa', 'on', '-n', '128',
    '-p', $prompt, '--no-display-prompt', '-st', '--temp', '0.7',
    '--log-disable'
) + $Extra
& .\llama-cli.exe @args 2>$null | Out-File -FilePath $out -Encoding utf8
$line = Select-String -Path $out -Pattern 'Prompt:|Generation:|error|failed' | ForEach-Object { $_.Line }
Write-Host "$Name :: $line"
