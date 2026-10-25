# Shared helpers for places.json handling (dot-source this file).
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }

$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)
$script:Inv = [Globalization.CultureInfo]::InvariantCulture

function Read-Utf8([string]$Path) { [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) }
function Write-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom) }

# ---- JSON writer -------------------------------------------------------
# ConvertTo-Json on PS 5.1 unrolls single-element arrays and truncates at depth 2,
# so serialize by hand: arrays stay arrays, key order is kept.
function ConvertTo-JsonString([string]$s) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            '"'  { [void]$sb.Append('\"') }
            '\'  { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default {
                if ([int]$ch -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    $sb.ToString()
}

function Test-JsonScalar($x) { ($null -eq $x) -or ($x -is [string]) -or ($x -is [ValueType]) }

function Write-JsonValue([Text.StringBuilder]$sb, $v, [int]$level) {
    $pad = '  ' * ($level + 1)
    $padEnd = '  ' * $level
    if ($null -eq $v) { [void]$sb.Append('null'); return }
    if ($v -is [string]) { [void]$sb.Append((ConvertTo-JsonString $v)); return }
    if ($v -is [bool]) { [void]$sb.Append($(if ($v) { 'true' } else { 'false' })); return }
    if ($v -is [double] -or $v -is [single]) { [void]$sb.Append($v.ToString('R', $script:Inv)); return }
    if ($v -is [ValueType]) { [void]$sb.Append(([IFormattable]$v).ToString($null, $script:Inv)); return }
    if ($v.GetType().FullName -eq 'System.Management.Automation.PSCustomObject') {
        $d = [ordered]@{}
        foreach ($pr in $v.PSObject.Properties) { $d[$pr.Name] = $pr.Value }
        $v = $d
    }
    if ($v -is [Collections.IDictionary]) {
        if ($v.Count -eq 0) { [void]$sb.Append('{}'); return }
        [void]$sb.Append("{`n")
        $first = $true
        foreach ($k in $v.Keys) {
            if (-not $first) { [void]$sb.Append(",`n") }
            $first = $false
            [void]$sb.Append($pad + (ConvertTo-JsonString ([string]$k)) + ': ')
            Write-JsonValue $sb $v[$k] ($level + 1)
        }
        [void]$sb.Append("`n" + $padEnd + '}')
        return
    }
    if ($v -is [Collections.IEnumerable]) {
        $arr = New-Object 'System.Collections.Generic.List[object]'; foreach ($e in $v) { $arr.Add($e) }
        if ($arr.Count -eq 0) { [void]$sb.Append('[]'); return }
        $allScalar = $true
        foreach ($x in $arr) { if (-not (Test-JsonScalar $x)) { $allScalar = $false; break } }
        if ($allScalar) {
            # Arrays of scalars (coordinate pairs, id lists) stay on one line.
            [void]$sb.Append('[')
            for ($i = 0; $i -lt $arr.Count; $i++) {
                if ($i -gt 0) { [void]$sb.Append(', ') }
                Write-JsonValue $sb $arr[$i] ($level + 1)
            }
            [void]$sb.Append(']')
            return
        }
        [void]$sb.Append("[`n")
        for ($i = 0; $i -lt $arr.Count; $i++) {
            if ($i -gt 0) { [void]$sb.Append(",`n") }
            [void]$sb.Append($pad)
            Write-JsonValue $sb $arr[$i] ($level + 1)
        }
        [void]$sb.Append("`n" + $padEnd + ']')
        return
    }
    [void]$sb.Append((ConvertTo-JsonString ([string]$v)))
}

function ConvertTo-PlainJson($Value) {
    $sb = New-Object Text.StringBuilder
    Write-JsonValue $sb $Value 0
    $sb.ToString()
}

# ---- Parsing helpers ---------------------------------------------------
function Get-Prop($o, [string]$name) {
    if ($null -eq $o) { return $null }
    $pp = $o.PSObject.Properties[$name]
    if ($pp -and $null -ne $pp.Value) { return $pp.Value }
    $null
}

function Get-Str($o, [string]$name) {
    $v = Get-Prop $o $name
    if ($null -eq $v) { '' } else { ([string]$v).Trim() }
}

function Get-VideoId([string]$s) {
    if (-not $s) { return $null }
    $s = $s.Trim()
    if ($s -match '^[\w-]{11}$') { return $s }
    if ($s -match '(?:youtu\.be/|[?&]v=|/shorts/|/embed/)([\w-]{11})') { return $matches[1] }
    $null
}

# Flatten whatever ConvertFrom-Json gave us for points into a list of [lat,lng] pairs.
function ConvertTo-PointList($raw) {
    $nums = New-Object 'System.Collections.Generic.List[double]'
    $walk = $null
    $walk = {
        param($x)
        if ($null -eq $x) { return }
        if ($x -is [string]) { return }
        if ($x -is [Collections.IEnumerable]) { foreach ($y in $x) { & $walk $y } }
        else { $nums.Add([double]$x) }
    }
    & $walk $raw
    $list = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i + 1 -lt $nums.Count; $i += 2) { $list.Add([double[]]@($nums[$i], $nums[$i + 1])) }
    , $list
}

# "lat, lng / lat, lng" -> list of [lat,lng]
function Convert-CoordsToPoints([string]$coords) {
    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($part in ($coords -split '/')) {
        if ($part -match '(-?\d+(\.\d+)?)\s*,\s*(-?\d+(\.\d+)?)') {
            $list.Add([double[]]@([double]::Parse($matches[1], $script:Inv), [double]::Parse($matches[3], $script:Inv)))
        }
    }
    , $list
}

# Drop (...) with contents, then everything except letters/digits; lower-case.
function Get-NormName([string]$name) {
    if (-not $name) { return '' }

    $open = [string][char]0xFF08; $close = [string][char]0xFF09  # full-width parentheses
    $s = [regex]::Replace($name, "[\($open][^\)$close]*[\)$close]", "")
    $s = [regex]::Replace($s, '[^\p{L}\p{N}]', '')
    $s.ToLowerInvariant()
}

function Get-DistanceMeters([double]$lat1, [double]$lng1, [double]$lat2, [double]$lng2) {
    $r = 6371000.0
    $p1 = $lat1 * [Math]::PI / 180; $p2 = $lat2 * [Math]::PI / 180
    $dp = ($lat2 - $lat1) * [Math]::PI / 180; $dl = ($lng2 - $lng1) * [Math]::PI / 180
    $a = [Math]::Sin($dp / 2) * [Math]::Sin($dp / 2) + [Math]::Cos($p1) * [Math]::Cos($p2) * [Math]::Sin($dl / 2) * [Math]::Sin($dl / 2)
    2 * $r * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1 - $a))
}

# ---- Store -------------------------------------------------------------
function Read-Store([string]$Path) {
    $store = @{
        videos = [ordered]@{}
        places = (New-Object 'System.Collections.Generic.List[object]')
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $store }
    $raw = ConvertFrom-Json (Read-Utf8 $Path)
    if ($raw.videos) {
        foreach ($pr in $raw.videos.PSObject.Properties) {
            $v = $pr.Value
            $store.videos[$pr.Name] = [ordered]@{
                url = Get-Str $v 'url'; title = Get-Str $v 'title'; channel = Get-Str $v 'channel'
                publishDate = Get-Str $v 'publishDate'; addedAt = Get-Str $v 'addedAt'
                placeCount = [int](Get-Prop $v 'placeCount'); note = Get-Str $v 'note'
            }
        }
    }
    foreach ($p in @($raw.places)) {
        if ($null -eq $p) { continue }
        $vids = New-Object 'System.Collections.Generic.List[string]'
        foreach ($x in @($p.videos)) { if ($x) { $vids.Add([string]$x) } }
        $chs = New-Object 'System.Collections.Generic.List[string]'
        foreach ($x in @($p.channels)) { if ($x) { $chs.Add([string]$x) } }
        $store.places.Add([ordered]@{
            id = [int]$p.id; name = Get-Str $p 'name'; location = Get-Str $p 'location'; coords = Get-Str $p 'coords'
            points = (ConvertTo-PointList $p.points)
            type = Get-Str $p 'type'; fee = Get-Str $p 'fee'; season = Get-Str $p 'season'; features = Get-Str $p 'features'
            videos = $vids; channels = $chs
        })
    }
    $store
}

function Save-Store($Store, [string]$Path) {
    Write-Utf8 $Path ((ConvertTo-PlainJson ([ordered]@{ videos = $Store.videos; places = $Store.places })) + "`n")
}

# One recommendation per channel: a channel's repeat videos add links, not count.
# Videos without a channel name each count once.
function Get-RecommendCount($Store, $Place) {
    $seen = @{}
    $n = 0
    foreach ($vid in $Place.videos) {
        $v = $Store.videos[$vid]
        $ch = if ($v) { $v.channel } else { '' }
        if (-not $ch) { $n++; continue }
        if (-not $seen.ContainsKey($ch)) { $seen[$ch] = $true; $n++ }
    }
    $n
}

# places.json -> data.js (window.TRAVEL_DATA)
function Build-DataJs($Store, [string]$OutPath) {
    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $Store.places) {
        $vids = New-Object 'System.Collections.Generic.List[object]'
        foreach ($vid in $p.videos) {
            $v = $Store.videos[$vid]
            if ($v) { $vids.Add([ordered]@{ url = $v.url; title = $v.title; channel = $v.channel }) }
            else { $vids.Add([ordered]@{ url = "https://youtu.be/$vid"; title = ''; channel = '' }) }
        }
        $items.Add([ordered]@{
            id = $p.id; name = $p.name; location = $p.location; coords = $p.coords; points = $p.points
            type = $p.type; fee = $p.fee; season = $p.season; features = $p.features
            recommend = (Get-RecommendCount $Store $p)
            channels = $p.channels
            channel = ($p.channels -join ', ')
            videos = $vids
            url = $(if ($vids.Count) { $vids[0].url } else { '' })
        })
    }
    Write-Utf8 $OutPath ("window.TRAVEL_DATA = " + (ConvertTo-PlainJson $items) + ";`n")
    $items.Count
}

# ---- Merge -------------------------------------------------------------
function Find-MatchingPlace($Places, [string]$name, $points, [double]$radiusM = 700) {
    $nn = Get-NormName $name
    foreach ($pl in $Places) {
        if ($nn -and (Get-NormName $pl.name) -eq $nn) { return $pl }
        foreach ($np in $points) {
            foreach ($ep in $pl.points) {
                if ((Get-DistanceMeters $np[0] $np[1] $ep[0] $ep[1]) -le $radiusM) { return $pl }
            }
        }
    }
    $null
}

# Merge video records into the store (in memory). Returns a summary object.
function Invoke-VideoMerge($Store, $VideoItems, [string]$AddedAt) {
    $sum = [pscustomobject]@{
        NewVideos = 0; SkippedVideos = 0; NewPlaces = 0
        Raised = (New-Object 'System.Collections.Generic.List[string]')
        Merges = (New-Object 'System.Collections.Generic.List[string]')
    }
    foreach ($it in $VideoItems) {
        $vid = Get-VideoId (Get-Str $it 'videoId')
        if (-not $vid) { $vid = Get-VideoId (Get-Str $it 'url') }
        if (-not $vid) { Write-Warning "Skipping an item without a valid videoId/url."; continue }
        if ($Store.videos.Contains($vid)) { $sum.SkippedVideos++; continue }

        $channel = Get-Str $it 'channel'
        $placesIn = @(Get-Prop $it 'places')
        $url = Get-Str $it 'url'
        if (-not $url) { $url = "https://youtu.be/$vid" }
        $Store.videos[$vid] = [ordered]@{
            url = $url; title = Get-Str $it 'title'; channel = $channel
            publishDate = Get-Str $it 'publishDate'; addedAt = $AddedAt
            placeCount = $placesIn.Count; note = Get-Str $it 'note'
        }
        $sum.NewVideos++

        foreach ($pin in $placesIn) {
            $name = Get-Str $pin 'name'
            if (-not $name) { continue }
            $coords = Get-Str $pin 'coords'
            $rawPts = Get-Prop $pin 'points'
            $pts = if ($null -ne $rawPts) { ConvertTo-PointList $rawPts } else { Convert-CoordsToPoints $coords }

            $hit = Find-MatchingPlace $Store.places $name $pts
            if ($hit) {
                if (-not $hit.videos.Contains($vid)) {
                    $hit.videos.Add($vid)
                    if ($channel -and $hit.channels.Contains($channel)) {
                        $sum.Merges.Add("$name  ->  $($hit.name) (id $($hit.id), same channel: link only)")
                    } else {
                        if ($channel) { $hit.channels.Add($channel) }
                        if (-not $sum.Raised.Contains($hit.name)) { $sum.Raised.Add($hit.name) }
                        $sum.Merges.Add("$name  ->  $($hit.name) (id $($hit.id))")
                    }
                }
                continue
            }

            $id = Get-Prop $pin 'id'
            if ($null -eq $id) {
                $id = 0
                foreach ($pl in $Store.places) { if ($pl.id -gt $id) { $id = $pl.id } }
                $id++
            }
            $vl = New-Object 'System.Collections.Generic.List[string]'; $vl.Add($vid)
            $cl = New-Object 'System.Collections.Generic.List[string]'; if ($channel) { $cl.Add($channel) }
            $Store.places.Add([ordered]@{
                id = [int]$id; name = $name; location = Get-Str $pin 'location'; coords = $coords; points = $pts
                type = Get-Str $pin 'type'; fee = Get-Str $pin 'fee'; season = Get-Str $pin 'season'; features = Get-Str $pin 'features'
                videos = $vl; channels = $cl
            })
            $sum.NewPlaces++
        }
    }
    $sum
}
