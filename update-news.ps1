<#
.SYNOPSIS
  Fetches the RSS/Atom feeds listed in feeds.json and writes data/news.js for index.html.
  Run manually, via "Update News.cmd", or daily via register-daily-task.ps1.
#>
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$ProgressPreference = 'SilentlyContinue'
$config = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'feeds.json') | ConvertFrom-Json

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 }
catch { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 }

$userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) NewsReport/1.0'
# Windows PowerShell aliases "curl" to Invoke-WebRequest, so ask for curl.exe there; on Linux (GitHub Actions) it's plain curl.
$curl = if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) { 'curl.exe' } else { 'curl' }
if (-not (Get-Command $curl -ErrorAction SilentlyContinue)) { throw "$curl not found (it ships with Windows 10 1803+)." }
$now = [DateTimeOffset]::UtcNow
$cutoff = $now.AddDays(-[double]$config.maxAgeDays)
$culture = [Globalization.CultureInfo]::InvariantCulture

function Get-Child($node, [string]$name) {
    $node.SelectSingleNode("*[local-name()='$name']")
}

function Get-Text($node, [string[]]$names) {
    foreach ($n in $names) {
        $c = Get-Child $node $n
        if ($c -and $c.InnerText.Trim()) { return $c.InnerText.Trim() }
    }
    return ''
}

function ConvertTo-PlainText([string]$html, [int]$max = 240) {
    if (-not $html) { return '' }
    $text = $html -replace '(?s)<(script|style)[^>]*>.*?</\1>', ' ' -replace '<[^>]+>', ' '
    $text = [Net.WebUtility]::HtmlDecode($text) -replace '\s+', ' '
    $text = $text.Trim()
    if ($text.Length -gt $max) { $text = $text.Substring(0, $max).TrimEnd() + [char]0x2026 }  # ellipsis; kept ASCII-safe for PS 5.1
    return $text
}

function ConvertTo-Date([string]$s) {
    if (-not $s) { return $null }
    $s = $s.Trim() -replace '\s+(GMT|UTC|UT|Z)$', ' +00:00' `
                   -replace '\s+EDT$', ' -04:00' -replace '\s+EST$', ' -05:00' `
                   -replace '\s+CDT$', ' -05:00' -replace '\s+CST$', ' -06:00' `
                   -replace '\s+PDT$', ' -07:00' -replace '\s+PST$', ' -08:00' `
                   -replace '([+-]\d{2})(\d{2})$', '$1:$2'
    $d = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($s, $culture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { return $d.ToUniversalTime() }
    return $null
}

function Get-Image($item, [string]$rawHtml) {
    foreach ($n in 'thumbnail', 'content') {
        foreach ($m in $item.SelectNodes("*[local-name()='$n' and @url]")) {
            $type = $m.GetAttribute('type'); $medium = $m.GetAttribute('medium')
            if (-not $type -or $type -like 'image*' -or $medium -eq 'image') { return $m.GetAttribute('url') }
        }
        $group = Get-Child $item 'group'
        if ($group) {
            $m = $group.SelectSingleNode("*[local-name()='$n' and @url]")
            if ($m) { return $m.GetAttribute('url') }
        }
    }
    $enc = $item.SelectSingleNode("*[local-name()='enclosure' and starts-with(@type,'image')]")
    if ($enc) { return $enc.GetAttribute('url') }
    if ($rawHtml -match '<img[^>]+src=["'']([^"'']+)["'']') { return [Net.WebUtility]::HtmlDecode($Matches[1]) }
    return $null
}

function Get-FeedItems($feed) {
    # curl.exe ships with Windows 10+ and is far more reliable than Invoke-WebRequest on PS 5.1.
    $tmp = [IO.Path]::GetTempFileName()
    try {
        $status = & $curl -s -L --compressed -m 25 -A $userAgent -o $tmp -w '%{http_code}' $feed.url
        if ($LASTEXITCODE -ne 0) { throw "curl exit code $LASTEXITCODE" }
        if ($status -ne '200') { throw "HTTP $status" }
        $settings = New-Object Xml.XmlReaderSettings
        $settings.DtdProcessing = [Xml.DtdProcessing]::Ignore
        $settings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create($tmp, $settings)
        $doc = New-Object Xml.XmlDocument
        try { $doc.Load($reader) } finally { $reader.Close() }
    }
    finally { Remove-Item $tmp -ErrorAction SilentlyContinue }

    foreach ($item in $doc.SelectNodes("//*[local-name()='item' or local-name()='entry']")) {
        $title = ConvertTo-PlainText (Get-Text $item 'title') 300
        if (-not $title) { continue }

        $link = ''
        $linkNode = $item.SelectSingleNode("*[local-name()='link' and (@rel='alternate' or not(@rel))]")
        if ($linkNode) {
            $link = if ($linkNode.GetAttribute('href')) { $linkNode.GetAttribute('href') } else { $linkNode.InnerText.Trim() }
        }
        if (-not $link) { $link = Get-Text $item 'guid' }
        if ($link -notmatch '^https?://') { continue }

        $rawHtml = Get-Text $item 'encoded', 'content', 'description', 'summary'
        $summarySrc = Get-Text $item 'description', 'summary', 'encoded', 'content'
        $date = ConvertTo-Date (Get-Text $item 'pubDate', 'published', 'updated', 'date')

        [pscustomobject]@{
            title   = $title
            link    = $link
            source  = $feed.name
            date    = $date
            summary = ConvertTo-PlainText $summarySrc
            image   = Get-Image $item $rawHtml
        }
    }
}

$categories = @()
$sources = @()
$total = 0

foreach ($cat in $config.categories) {
    $all = @()
    foreach ($feed in $cat.feeds) {
        try {
            $items = @(Get-FeedItems $feed | Where-Object { -not $_.date -or $_.date -ge $cutoff })
            # Undated items get the fetch time so they still sort sensibly.
            foreach ($i in $items) { if (-not $i.date) { $i.date = $now } }
            $items = @($items | Sort-Object date -Descending | Select-Object -First $config.maxPerSource)
            $all += $items
            $sources += [ordered]@{ category = $cat.id; name = $feed.name; ok = $true; count = $items.Count }
            Write-Host ("  [ok]   {0,-14} {1,-20} {2} items" -f $cat.name, $feed.name, $items.Count)
        }
        catch {
            $sources += [ordered]@{ category = $cat.id; name = $feed.name; ok = $false; error = $_.Exception.Message }
            Write-Host ("  [fail] {0,-14} {1,-20} {2}" -f $cat.name, $feed.name, $_.Exception.Message) -ForegroundColor Yellow
        }
    }

    $seen = @{}
    $articles = @()
    foreach ($a in ($all | Sort-Object date -Descending)) {
        $key = ($a.title.ToLowerInvariant() -replace '[^a-z0-9]', '')
        if ($seen.ContainsKey($a.link) -or $seen.ContainsKey($key)) { continue }
        $seen[$a.link] = $true; $seen[$key] = $true
        $articles += [ordered]@{
            title   = $a.title
            link    = $a.link
            source  = $a.source
            date    = $a.date.ToString('o')
            summary = $a.summary
            image   = $a.image
        }
        if ($articles.Count -ge $config.maxPerCategory) { break }
    }
    $total += $articles.Count
    $categories += [ordered]@{ id = $cat.id; name = $cat.name; articles = $articles }
}

$outDir = Join-Path $root 'data'
$outFile = Join-Path $outDir 'news.js'
if ($total -eq 0) {
    Write-Host 'No articles fetched (offline?). Keeping the previous data file.' -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force $outDir | Out-Null
$payload = [ordered]@{ generated = $now.ToString('o'); categories = $categories; sources = $sources }
$json = ConvertTo-Json -InputObject $payload -Depth 6 -Compress
$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText($outFile, "window.NEWS_DATA = $json;`n", $utf8)

# Keep a dated snapshot so past days can be reopened; prune after 30 days.
$archiveDir = Join-Path $outDir 'archive'
New-Item -ItemType Directory -Force $archiveDir | Out-Null
[IO.File]::WriteAllText((Join-Path $archiveDir ("{0:yyyy-MM-dd}.js" -f (Get-Date))), "window.NEWS_DATA = $json;`n", $utf8)
# Prune by the date in the file name: a fresh git checkout resets every file's LastWriteTime.
$keepFrom = (Get-Date).Date.AddDays(-30)
Get-ChildItem $archiveDir -Filter *.js | Where-Object {
    $d = [datetime]::MinValue
    [datetime]::TryParseExact($_.BaseName, 'yyyy-MM-dd', $culture, [Globalization.DateTimeStyles]::None, [ref]$d) -and $d -lt $keepFrom
} | Remove-Item -Confirm:$false

Write-Host "Wrote $total articles to $outFile"
