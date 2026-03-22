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

function To-LocalPagePath([string]$root, [System.Uri]$uri) {
    $path = $uri.AbsolutePath.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($path)) {
        return Join-Path $root "index.html"
    }
    if ([System.IO.Path]::GetExtension($path)) {
        return Join-Path $root $path
    }
    return Join-Path (Join-Path $root $path) "index.html"
}

$workspace = (Resolve-Path '.').Path
$siteRoot = Join-Path $workspace $SiteDir
Ensure-Dir $siteRoot

$maps = @(
    "$BaseUrl/page-sitemap.xml",
    "$BaseUrl/post-sitemap.xml"
)

$urls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$urls.Add("$BaseUrl/") | Out-Null

foreach ($map in $maps) {
    try {
        $xml = (Invoke-WebRequest -UseBasicParsing -Uri $map).Content
        [regex]::Matches($xml, '<loc>([^<]+)</loc>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) |
            ForEach-Object {
                $u = $_.Groups[1].Value.Trim()
                if ($u.StartsWith($BaseUrl)) {
                    $uri = [System.Uri]$u
                    if ([string]::IsNullOrWhiteSpace($uri.Query)) {
                        $urls.Add($uri.AbsoluteUri) | Out-Null
                    }
                }
            }
    } catch {
    }
}

foreach ($u in $urls) {
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $u
        $uri = [System.Uri]$u
        $localPath = To-LocalPagePath -root $siteRoot -uri $uri
        Ensure-Dir (Split-Path -Parent $localPath)
        [System.IO.File]::WriteAllText($localPath, $resp.Content, [System.Text.Encoding]::UTF8)
    } catch {
    }
}

Write-Host "refresh done: pages=$($urls.Count)"
