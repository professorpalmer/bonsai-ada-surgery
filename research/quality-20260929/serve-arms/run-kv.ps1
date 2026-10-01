# H4: KV precision arms. Identical to pinned A except: no tier (-c 49152 all in VRAM) and target KV type.
#   powershell -NoExit -NoProfile -ExecutionPolicy Bypass -File run-kv.ps1 -Kv q8_0|f16
param([Parameter(Mandatory)][ValidateSet('q8_0', 'f16')][string]$Kv)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'arms.ps1')
$Key = (Get-Content -Path (Join-Path $Root 'artifacts\api_key.txt') -Raw).Trim()
[string[]]$A = Get-ArmArgs 'A' $Key
# drop the tier option, set context 49152 and the target KV type (draft KV stays q8_0 in both arms)
$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $A.Count; $i++) {
    switch ($A[$i]) {
        '--kv-vram-cells' { $i++; continue }
        '--spec-draft-n-max-tail' { $i++; continue }   # only meaningful with a tier
        '-c' { $out.Add('-c'); $out.Add('49152'); $i++; continue }
        '-ctk' { $out.Add('-ctk'); $out.Add($Kv); $i++; continue }
        '-ctv' { $out.Add('-ctv'); $out.Add($Kv); $i++; continue }
        default { $out.Add($A[$i]) }
    }
}
foreach ($k in $ArmEnv.Keys) { Set-Item -Path "env:$k" -Value $ArmEnv[$k] }
Write-Host ("kv arm {0}: {1}" -f $Kv, (($out -join ' ').Replace($Key, '<REDACTED>')))
Set-Location $Bin
& .\llama-server.exe @out
