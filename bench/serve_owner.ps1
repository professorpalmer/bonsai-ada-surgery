# Exit 0 when the process that listens on the port runs from <Root>\bin (the serve under test answers, not a serve
# left by an earlier step). Exit 1 otherwise, and print the path that was found.
#   powershell -File bench\serve_owner.ps1 -Root <serve root> [-Port 8080]
param([Parameter(Mandatory)][string]$Root, [int]$Port = 8080)
$c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
$path = if ($c) { (Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue).Path } else { '' }
$bin = [IO.Path]::GetFullPath((Join-Path $Root 'bin')).TrimEnd('\') + '\'
if ($path -and $path.StartsWith($bin, [StringComparison]::OrdinalIgnoreCase)) { exit 0 }
"port $Port is served by '$path', not from $bin"
exit 1
