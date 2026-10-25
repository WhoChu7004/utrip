# Commits the merged travel data and pushes it to GitHub (GitHub Pages redeploys the map).
# Only places.json, data.js and inbox\ are committed; nothing happens when they are unchanged.
# Usage: powershell -ExecutionPolicy Bypass -File publish-data.ps1 [-Message "<commit message>"]
param([string]$Message)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "lib.ps1")
$repo = Split-Path -Parent $here

# Git may be installed after this shell started, so don't rely on PATH alone.
$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) { $git = Join-Path $env:ProgramFiles "Git\cmd\git.exe" }
if (-not (Test-Path $git)) { throw "git not found." }

function Invoke-Git {
    # Git writes progress to stderr; keep it from becoming a terminating error.
    $ErrorActionPreference = 'Continue'
    & $git -C $repo @args 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed (exit $LASTEXITCODE)." }
}

$paths = @("WWW/places.json", "WWW/data.js", "WWW/inbox")
Invoke-Git add -- @paths | Out-Null
$staged = Invoke-Git diff --cached --name-only -- @paths
if (-not $staged) { Write-Output "No data changes to publish."; return }

if (-not $Message) {
    $store = Read-Store (Join-Path $here "places.json")
    $Message = "Data update $(Get-Date -Format 'yyyy-MM-dd'): $($store.places.Count) places, $($store.videos.Count) videos"
}
Invoke-Git commit -q -m $Message -- @paths | Out-Null
# Pick up anything pushed from elsewhere (e.g. README edits on github.com) before pushing.
Invoke-Git pull -q --rebase --autostash origin main | Out-Null
Invoke-Git push -q origin main | Out-Null

$head = Invoke-Git log --oneline -1
Write-Output "Published: $head"
Write-Output "Files: $($staged -join ', ')"
