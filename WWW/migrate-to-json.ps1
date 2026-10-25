# One-time: converts the legacy data.js (one row per video x place) into places.json,
# merging rows that describe the same place. Refuses to overwrite an existing places.json.
# Usage: powershell -ExecutionPolicy Bypass -File migrate-to-json.ps1 [-AddedAt 2026-10-25] [-Force]
param(
    [string]$AddedAt = "2026-10-25",
    [switch]$Force
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "lib.ps1")

$storePath = Join-Path $here "places.json"
if ((Test-Path -LiteralPath $storePath) -and -not $Force) { throw "places.json already exists (use -Force to overwrite)." }

$js = Read-Utf8 (Join-Path $here "data.js")
$json = ($js -replace '^\s*window\.TRAVEL_DATA\s*=\s*', '').TrimEnd().TrimEnd(';')
$rows = ConvertFrom-Json $json

# Group rows by video, keeping first-seen order.
$groups = [ordered]@{}
foreach ($r in $rows) {
    $vid = Get-VideoId ([string]$r.url)
    if (-not $vid) { throw "No video id in url of row id $($r.id): $($r.url)" }
    if (-not $groups.Contains($vid)) {
        $groups[$vid] = [pscustomobject]@{
            videoId = $vid; url = [string]$r.url; title = ''; channel = [string]$r.channel
            publishDate = ''; note = ''
            places = (New-Object 'System.Collections.Generic.List[object]')
        }
    }
    $groups[$vid].places.Add($r)
}

$store = @{
    videos = [ordered]@{}
    places = (New-Object 'System.Collections.Generic.List[object]')
}
$sum = Invoke-VideoMerge $store @($groups.Values) $AddedAt
Save-Store $store $storePath

Write-Output "Rows read:        $(@($rows).Count)"
Write-Output "Videos:           $($store.videos.Count)"
Write-Output "Places written:   $($store.places.Count)"
Write-Output "Merged rows:      $($sum.Merges.Count)"
foreach ($m in $sum.Merges) { Write-Output "  $m" }
