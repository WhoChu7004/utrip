# Merges analysed videos (JSON array) into places.json, then regenerates data.js.
# Usage: powershell -ExecutionPolicy Bypass -File merge-videos.ps1 -InputPath inbox\today.json [-DryRun]
param(
    [Parameter(Mandatory)][string]$InputPath,
    [switch]$DryRun
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "lib.ps1")

$storePath = Join-Path $here "places.json"
$store = Read-Store $storePath

$parsed = ConvertFrom-Json (Read-Utf8 (Resolve-Path -LiteralPath $InputPath).Path)
$items = New-Object 'System.Collections.Generic.List[object]'
foreach ($x in $parsed) {
    if ($x -is [array]) { foreach ($y in $x) { $items.Add($y) } } else { $items.Add($x) }
}

$sum = Invoke-VideoMerge $store $items (Get-Date -Format "yyyy-MM-dd")

if (-not $DryRun) {
    Save-Store $store $storePath
    [void](Build-DataJs $store (Join-Path $here "data.js"))
}

Write-Output "New videos:        $($sum.NewVideos)"
Write-Output "Skipped duplicate: $($sum.SkippedVideos)"
Write-Output "New places:        $($sum.NewPlaces)"
Write-Output "Recommend +1 ($($sum.Raised.Count)):"
foreach ($m in $sum.Merges) { Write-Output "  $m" }
if ($DryRun) { Write-Output "(DryRun: nothing saved)" }
