# RAM guard for heavy test runs. Every 2 s: when free commit (RAM + page file) falls below MinFreeCommitGB or free RAM
# below MinFreeRamGB, stop every process named in -Names and log it. Exits when -StopFile exists or after -MaxHours.
# Started by a job script at its start and stopped (stop file) at its end, so it never outlives the job.
#   powershell -File tools\ramguard.ps1 -Names llama-perplexity,llama-server -StopFile logs\ramguard.stop
# Why: a 64k-context llama-perplexity KL run held ~32 GB of logits (248k vocab) and froze the machine twice (2026-10-10).
param(
    [string[]]$Names = @('llama-perplexity', 'llama-server'),
    [double]$MinFreeCommitGB = 6,
    [double]$MinFreeRamGB = 1.5,
    [string]$StopFile = 'logs\ramguard.stop',
    [string]$Log = 'logs\ramguard.log',
    [double]$MaxHours = 8
)
$deadline = (Get-Date).AddHours($MaxHours)
"$(Get-Date -Format 'HH:mm:ss') guard on: names=$($Names -join ',') minCommit=$MinFreeCommitGB GB minRam=$MinFreeRamGB GB" | Add-Content $Log
while (-not (Test-Path $StopFile) -and (Get-Date) -lt $deadline) {
    $os = Get-CimInstance Win32_OperatingSystem
    $freeCommit = $os.FreeVirtualMemory / 1MB
    $freeRam = $os.FreePhysicalMemory / 1MB
    if ($freeCommit -lt $MinFreeCommitGB -or $freeRam -lt $MinFreeRamGB) {
        $procs = Get-Process -Name $Names -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            $ws = [int]($p.WorkingSet64 / 1MB); $priv = [int]($p.PrivateMemorySize64 / 1MB)
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            "$(Get-Date -Format 'HH:mm:ss') KILLED $($p.ProcessName) $($p.Id) (ws $ws MiB, private $priv MiB): free commit {0:N1} GB, free RAM {1:N1} GB" -f $freeCommit, $freeRam | Add-Content $Log
        }
        Start-Sleep -Seconds 5
    }
    Start-Sleep -Seconds 2
}
"$(Get-Date -Format 'HH:mm:ss') guard off" | Add-Content $Log
