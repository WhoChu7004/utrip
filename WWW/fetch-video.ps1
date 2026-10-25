# Reads public YouTube pages with plain GET requests.
#   -Url <url|id>       -> JSON with video details
#   -Search "<query>"   -> JSON list of result videos (add -ExcludeKnown to drop ids already in places.json)
param(
    [string]$Url,
    [string]$Search,
    [switch]$ExcludeKnown
)
$ProgressPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "lib.ps1")

if (-not $Url -and -not $Search) { throw "Specify -Url <url|id> or -Search <query>." }

Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue
$ser.RecursionLimit = 2000

function Get-Page([string]$uri) {
    $res = Invoke-WebRequest -UseBasicParsing -Uri $uri
    # Decode as UTF-8 explicitly; PS 5.1 may guess a legacy code page.
    $ms = New-Object IO.MemoryStream
    $res.RawContentStream.CopyTo($ms)
    [Text.Encoding]::UTF8.GetString($ms.ToArray())
}

# Extract the JSON object that follows "<marker> =" by brace matching (string-aware).
function Get-EmbeddedJson([string]$html, [string]$marker) {
    $i = $html.IndexOf($marker)
    if ($i -lt 0) { throw "Marker '$marker' not found in page." }
    $start = $html.IndexOf('{', $i)
    $depth = 0; $inStr = $false; $esc = $false
    for ($k = $start; $k -lt $html.Length; $k++) {
        $c = $html[$k]
        if ($inStr) {
            if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false }
        } elseif ($c -eq '"') { $inStr = $true }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $ser.DeserializeObject($html.Substring($start, $k - $start + 1)) } }
    }
    throw "Unterminated JSON after '$marker'."
}

# Safe nested lookup on dictionaries/arrays: Get-At $obj 'a' 0 'b'
function Get-At($o, [object[]]$path) {
    foreach ($p in $path) {
        if ($null -eq $o) { return $null }
        if ($o -is [Collections.IDictionary]) { if (([Collections.IDictionary]$o).Contains($p)) { $o = $o[$p] } else { return $null } }
        elseif ($o -is [Collections.IList] -and $p -is [int]) { if ($p -lt $o.Count) { $o = $o[$p] } else { return $null } }
        else { return $null }
    }
    $o
}

function Find-Renderers($o, [string]$key, $acc) {
    if ($o -is [Collections.IDictionary]) {
        foreach ($k in @($o.Keys)) {
            if ($k -eq $key) { $acc.Add($o[$k]) } else { Find-Renderers $o[$k] $key $acc }
        }
    } elseif ($o -is [Collections.IList]) {
        foreach ($x in $o) { Find-Renderers $x $key $acc }
    }
}

try {
    if ($Url) {
        $id = Get-VideoId $Url
        if (-not $id) { throw "Cannot find an 11-character video id in '$Url'." }
        $html = Get-Page "https://www.youtube.com/watch?v=$id&hl=ko"
        $pr = Get-EmbeddedJson $html 'ytInitialPlayerResponse'
        $vd = Get-At $pr @('videoDetails')
        if (-not $vd) { throw "videoDetails missing (status: $(Get-At $pr @('playabilityStatus','status')))." }
        $len = 0; [void][int]::TryParse([string]$vd['lengthSeconds'], [ref]$len)
        $result = [ordered]@{
            videoId       = [string]$vd['videoId']
            url           = "https://youtu.be/$id"
            title         = [string]$vd['title']
            channel       = [string]$vd['author']
            publishDate   = [string](Get-At $pr @('microformat', 'playerMicroformatRenderer', 'publishDate'))
            lengthSeconds = $len
            description   = [string]$vd['shortDescription']
        }
        ConvertTo-PlainJson $result
    } else {
        $q = [Uri]::EscapeDataString($Search)
        $html = Get-Page "https://www.youtube.com/results?search_query=$q&hl=ko"
        $data = Get-EmbeddedJson $html 'ytInitialData'
        $found = New-Object 'System.Collections.Generic.List[object]'
        Find-Renderers $data 'videoRenderer' $found
        $known = @{}
        if ($ExcludeKnown) {
            $store = Read-Store (Join-Path $here "places.json")
            foreach ($k in $store.videos.Keys) { $known[$k] = $true }
        }
        $out = New-Object 'System.Collections.Generic.List[object]'
        $seen = @{}
        foreach ($v in $found) {
            $vid = [string]$v['videoId']
            if (-not $vid -or $seen.ContainsKey($vid) -or $known.ContainsKey($vid)) { continue }
            $seen[$vid] = $true
            $ch = Get-At $v @('ownerText', 'runs', 0, 'text')
            if (-not $ch) { $ch = Get-At $v @('longBylineText', 'runs', 0, 'text') }
            $out.Add([ordered]@{
                videoId       = $vid
                title         = [string](Get-At $v @('title', 'runs', 0, 'text'))
                channel       = [string]$ch
                publishedTime = [string](Get-At $v @('publishedTimeText', 'simpleText'))
                lengthText    = [string](Get-At $v @('lengthText', 'simpleText'))
            })
        }
        ConvertTo-PlainJson $out
    }
} catch {
    Write-Error "fetch-video failed: $($_.Exception.Message)"
    exit 1
}
