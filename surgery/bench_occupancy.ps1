$ErrorActionPreference = 'Stop'
$env:PATH = "C:\Users\pwall\Projects\bonsai-2-27b-serve\tooling\ada-bin;" + $env:PATH
$bench = 'C:\Users\pwall\Projects\bonsai-2-27b-serve\tooling\ada-bin\llama-bench.exe'
$model = 'C:\Users\pwall\Projects\bonsai-2-27b-serve\models\Ternary-Bonsai-2-27B-PTQ1_0.gguf'
$art = 'C:\Users\pwall\Projects\bonsai-2-27b-serve\artifacts'
Set-Location 'C:\Users\pwall\Projects\bonsai-2-27b-serve\tooling\ada-bin'
Remove-Item Env:GGML_CUDA_PTQ1_FORCE_MMQ -ErrorAction SilentlyContinue
& $bench -m $model -ngl 99 -fa on -p 512 -n 128 -r 3 -o json | Set-Content -Encoding utf8 (Join-Path $art 'bench_ptq1_mmvq1warp.json')
$env:GGML_CUDA_PTQ1_FORCE_MMQ = '1'
& $bench -m $model -ngl 99 -fa on -p 512 -n 128 -r 3 -o json | Set-Content -Encoding utf8 (Join-Path $art 'bench_ptq1_forcemmq.json')
Remove-Item Env:GGML_CUDA_PTQ1_FORCE_MMQ -ErrorAction SilentlyContinue
Write-Host 'benches done'
