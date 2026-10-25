# Regenerates data.js from places.json (the source of truth).
# Usage: powershell -ExecutionPolicy Bypass -File build-data.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "lib.ps1")

$store = Read-Store (Join-Path $here "places.json")
$out = Join-Path $here "data.js"
$n = Build-DataJs $store $out
Write-Output "Wrote $n places to $out"
