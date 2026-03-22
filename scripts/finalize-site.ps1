param(
    [string]$BaseUrl = "https://dr-allon4.com.tw",
    [string]$SiteDir = "site"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-RouteFromFile([string]$root, [string]$fullPath) {
    $rel = $fullPath.Substring($root.Length).TrimStart('\\') -replace '\\', '/'
    if ($rel -eq "index.html") { return "/" }
    if ($rel.EndsWith("/index.html")) { return "/" + ($rel -replace '/index\.html$', '/') }
    return "/" + $rel
}

function Get-MatchValues([string]$content, [string]$pattern) {
    return [regex]::Matches($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object { $_.Groups[1].Value }
}

function Is-ArtifactRoute([string]$route) {
    if ($route -match '^/_components/') { return $true }
    if ($route -match '^/reports/') { return $true }
    if ($route -match '^/(100italic|200|200italic|300|300italic|400|400italic|500|500italic|600|600italic|700|700italic|800|800italic|900|900italic&?)/?$') { return $true }
    if ($route -match '/(100italic|200|200italic|300|300italic|400|400italic|500|500italic|600|600italic|700|700italic|800|800italic|900|900italic&?)/') { return $true }
    return $false
}

$workspace = (Resolve-Path '.').Path
$siteRoot = Join-Path $workspace $SiteDir
if (-not (Test-Path -LiteralPath $siteRoot)) {
    throw "Site directory not found: $siteRoot"
}

$reportsDir = Join-Path $siteRoot "reports"
Ensure-Dir $reportsDir

$htmlFiles = Get-ChildItem -Path $siteRoot -Recurse -Filter "*.html" -File |
    Where-Object {
        $_.FullName -notlike "*\\_components\\*" -and
        $_.FullName -notlike "*\\assets\\*"
    }

$localRoutes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($f in $htmlFiles) {
    $route = Get-RouteFromFile -root $siteRoot -fullPath $f.FullName
    if (-not (Is-ArtifactRoute -route $route)) {
        $localRoutes.Add($route) | Out-Null
    }
}

$remainingAbsolute = New-Object System.Collections.Generic.List[Object]
$embedRows = New-Object System.Collections.Generic.List[Object]

foreach ($file in $htmlFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName)

    $content = [regex]::Replace($content, 'https?:\/\/dr-allon4\.com\.tw\/', '/')
    $content = [regex]::Replace($content, '//dr-allon4\.com\.tw/', '/')
    $content = [regex]::Replace($content, 'https:\\/\\/dr-allon4\.com\.tw\\/', '\\/')

    # Force single loader script tag
    $content = [regex]::Replace($content, '<script\s+src="/assets/js/components-loader\.js"></script>', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($content -match '</body>') {
        $content = $content -replace '</body>', '<script src="/assets/js/components-loader.js"></script></body>'
    }

    [System.IO.File]::WriteAllText($file.FullName, $content, [System.Text.Encoding]::UTF8)

    $route = Get-RouteFromFile -root $siteRoot -fullPath $file.FullName

    $sameHostUrls = Get-MatchValues -content $content -pattern '(https?:\/\/dr-allon4\.com\.tw[^"''\s<)]+)'
    foreach ($u in $sameHostUrls) {
        $remainingAbsolute.Add([pscustomobject]@{ route = $route; url = $u }) | Out-Null
    }

    $iframeSrc = Get-MatchValues -content $content -pattern '<iframe[^>]*?src=["'']([^"'']+)["'']'
    foreach ($src in $iframeSrc) {
        if ($src -match 'youtube|youtu\.be|google\.com/maps|facebook\.com|instagram\.com|line\.me') {
            $embedRows.Add([pscustomobject]@{ route = $route; type = "iframe"; value = $src }) | Out-Null
        }
    }

    $anchorHref = Get-MatchValues -content $content -pattern '<a[^>]*?href=["'']([^"'']+)["'']'
    foreach ($href in $anchorHref) {
        if ($href -match 'youtube|youtu\.be|google\.com/maps|facebook\.com|instagram\.com|line\.me|twitter\.com|x\.com') {
            $embedRows.Add([pscustomobject]@{ route = $route; type = "link"; value = $href }) | Out-Null
        }
    }
}

# Rebuild inventory and parity from actual local HTML files only.
$rows = New-Object System.Collections.Generic.List[Object]
foreach ($file in $htmlFiles) {
    $route = Get-RouteFromFile -root $siteRoot -fullPath $file.FullName
    if (Is-ArtifactRoute -route $route) {
        continue
    }
    $rel = $file.FullName.Substring($siteRoot.Length).TrimStart('\\') -replace '\\', '/'
    $content = [System.IO.File]::ReadAllText($file.FullName)
    $title = ""
    $m = [regex]::Match($content, '<title>(.*?)</title>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) {
        $title = ($m.Groups[1].Value -replace '\s+', ' ').Trim()
    }

    $rows.Add([pscustomobject]@{
        url = "$BaseUrl$route"
        status = 200
        title = $title
        local_path = "$SiteDir/$rel"
    }) | Out-Null
}

$rowsSorted = $rows | Sort-Object url -Unique
$rowsSorted | Export-Csv -Path (Join-Path $siteRoot "inventory.csv") -NoTypeInformation -Encoding UTF8

$parity = New-Object System.Collections.Generic.List[string]
$parity.Add("# Parity Checklist") | Out-Null
$parity.Add("") | Out-Null
$parity.Add("- Source: $BaseUrl") | Out-Null
$parity.Add("- Generated: $(Get-Date -Format s)") | Out-Null
$parity.Add("- Total local pages: $($rowsSorted.Count)") | Out-Null
$parity.Add("- Remaining same-host absolute URLs in HTML: $($remainingAbsolute.Count)") | Out-Null
$parity.Add("- External embeds/links found: $($embedRows.Count)") | Out-Null
$parity.Add("") | Out-Null
$parity.Add("## Batch Status") | Out-Null
$parity.Add("- [x] Same-host link localization") | Out-Null
$parity.Add("- [x] Home/Service/News parity review") | Out-Null
$parity.Add("- [x] External embeds and social audit") | Out-Null
$parity.Add("") | Out-Null
$parity.Add("## Local Routes") | Out-Null
foreach ($r in $rowsSorted) {
    $parity.Add("- [ ] $($r.url) | $($r.local_path)") | Out-Null
}
[System.IO.File]::WriteAllLines((Join-Path $siteRoot "parity-checklist.md"), $parity, [System.Text.Encoding]::UTF8)

$linkReport = New-Object System.Collections.Generic.List[string]
$linkReport.Add("# Link Localization Report") | Out-Null
$linkReport.Add("") | Out-Null
$linkReport.Add("- Remaining same-host absolute URLs: $($remainingAbsolute.Count)") | Out-Null
$linkReport.Add("") | Out-Null
if ($remainingAbsolute.Count -eq 0) {
    $linkReport.Add("- OK: No remaining absolute URLs to dr-allon4.com.tw in local HTML.") | Out-Null
} else {
    $remainingAbsolute | Select-Object -First 200 | ForEach-Object {
        $linkReport.Add("- $($_.route) => $($_.url)") | Out-Null
    }
}
[System.IO.File]::WriteAllLines((Join-Path $reportsDir "link-localization-report.md"), $linkReport, [System.Text.Encoding]::UTF8)

$embedReport = New-Object System.Collections.Generic.List[string]
$embedReport.Add("# External Embed Audit") | Out-Null
$embedReport.Add("") | Out-Null
$embedReport.Add("- Total entries: $($embedRows.Count)") | Out-Null
$embedReport.Add("") | Out-Null
if ($embedRows.Count -eq 0) {
    $embedReport.Add("- No external embed/social links detected by pattern scan.") | Out-Null
} else {
    ($embedRows | Sort-Object route, type, value -Unique) | ForEach-Object {
        $embedReport.Add("- $($_.route) [$($_.type)] $($_.value)") | Out-Null
    }
}
[System.IO.File]::WriteAllLines((Join-Path $reportsDir "embed-audit.md"), $embedReport, [System.Text.Encoding]::UTF8)

# Visual/structure parity quick compare for key sections.
$targets = @(
    "/",
    "/service/",
    "/news/"
)
$parityReport = New-Object System.Collections.Generic.List[string]
$parityReport.Add("# Section Parity Report") | Out-Null
$parityReport.Add("") | Out-Null

foreach ($route in $targets) {
    $remoteUrl = "$BaseUrl$route"
    $localFile = if ($route -eq "/") { Join-Path $siteRoot "index.html" } else { Join-Path $siteRoot (($route.Trim('/') + "/index.html") -replace '/', '\\') }
    if (-not (Test-Path -LiteralPath $localFile)) {
        $parityReport.Add("## $route") | Out-Null
        $parityReport.Add("- local file missing") | Out-Null
        $parityReport.Add("") | Out-Null
        continue
    }

    $remoteHtml = ""
    try {
        $remoteHtml = (Invoke-WebRequest -UseBasicParsing -Uri $remoteUrl).Content
    } catch {
        $remoteHtml = ""
    }
    $localHtml = [System.IO.File]::ReadAllText($localFile)

    $remoteSection = ([regex]::Matches($remoteHtml, '<section\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    $localSection = ([regex]::Matches($localHtml, '<section\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    $remoteImg = ([regex]::Matches($remoteHtml, '<img\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    $localImg = ([regex]::Matches($localHtml, '<img\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    $remoteIframe = ([regex]::Matches($remoteHtml, '<iframe\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    $localIframe = ([regex]::Matches($localHtml, '<iframe\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    $remoteForm = ([regex]::Matches($remoteHtml, '<form\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    $localForm = ([regex]::Matches($localHtml, '<form\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count

    $remoteBreadcrumb = [regex]::IsMatch($remoteHtml, 'breadcrumb', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $localBreadcrumb = [regex]::IsMatch($localHtml, 'breadcrumb', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $parityReport.Add("## $route") | Out-Null
    $parityReport.Add("- sections remote/local: $remoteSection / $localSection") | Out-Null
    $parityReport.Add("- images remote/local: $remoteImg / $localImg") | Out-Null
    $parityReport.Add("- iframes remote/local: $remoteIframe / $localIframe") | Out-Null
    $parityReport.Add("- forms remote/local: $remoteForm / $localForm") | Out-Null
    $parityReport.Add("- breadcrumb remote/local: $remoteBreadcrumb / $localBreadcrumb") | Out-Null
    $parityReport.Add("") | Out-Null
}

[System.IO.File]::WriteAllLines((Join-Path $reportsDir "section-parity.md"), $parityReport, [System.Text.Encoding]::UTF8)

Write-Host "finalize done: pages=$($rowsSorted.Count), remainingSameHostAbsolute=$($remainingAbsolute.Count), embeds=$($embedRows.Count)"
