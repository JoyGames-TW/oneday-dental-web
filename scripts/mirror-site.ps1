param(
    [string]$BaseUrl = "https://dr-allon4.com.tw",
    [string]$OutputDir = "site",
    [int]$MaxPages = 400,
    [int]$MaxAssetPasses = 3,
    [switch]$VerboseLog
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Normalize-Url([string]$Url) {
    try {
        $uri = [System.Uri]$Url
        $builder = [System.UriBuilder]::new($uri)
        $builder.Fragment = ""
        $normalized = $builder.Uri.AbsoluteUri
        if ($normalized.EndsWith("/")) {
            return $normalized
        }
        if ([System.IO.Path]::GetExtension($builder.Path) -eq "") {
            return "$normalized/"
        }
        return $normalized
    }
    catch {
        return $null
    }
}

function To-LocalPagePath([string]$RootDir, [System.Uri]$UriObj) {
    $path = $UriObj.AbsolutePath.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($path)) {
        return Join-Path $RootDir "index.html"
    }

    if ([System.IO.Path]::GetExtension($path)) {
        return Join-Path $RootDir $path
    }

    $folder = Join-Path $RootDir $path
    return Join-Path $folder "index.html"
}

function To-LocalAssetPath([string]$RootDir, [System.Uri]$UriObj) {
    $path = $UriObj.AbsolutePath.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($path)) {
        return Join-Path $RootDir "asset"
    }
    return Join-Path $RootDir $path
}

function Is-SameHost([System.Uri]$UriObj, [System.Uri]$RootUri) {
    return ($UriObj.Scheme -eq $RootUri.Scheme -and $UriObj.Host -eq $RootUri.Host)
}

function Get-Matches([string]$Content, [string]$Pattern) {
    return [regex]::Matches($Content, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function Resolve-SiteUri([string]$Raw, [System.Uri]$CurrentUri, [System.Uri]$RootUri) {
    if ($Raw.StartsWith("data:") -or $Raw.StartsWith("javascript:")) {
        return $null
    }

    try {
        $candidate = if ([System.Uri]::IsWellFormedUriString($Raw, [System.UriKind]::Absolute)) {
            [System.Uri]$Raw
        }
        else {
            [System.Uri]::new($CurrentUri, $Raw)
        }
    }
    catch {
        return $null
    }

    if (-not (Is-SameHost -UriObj $candidate -RootUri $RootUri)) {
        return $null
    }

    return $candidate
}

$rootUri = [System.Uri]$BaseUrl
$siteDir = Resolve-Path -LiteralPath "."
$outDir = Join-Path $siteDir $OutputDir
Ensure-Dir $outDir

$inventoryPath = Join-Path $outDir "inventory.csv"
$parityPath = Join-Path $outDir "parity-checklist.md"

$seedMaps = @("$BaseUrl/sitemap.xml", "$BaseUrl/post-sitemap.xml", "$BaseUrl/page-sitemap.xml")
$pagesToVisit = [System.Collections.Generic.Queue[string]]::new()
$visitedPages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$assetSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($map in $seedMaps) {
    try {
        $xml = (Invoke-WebRequest -UseBasicParsing -Uri $map).Content
        $locs = Get-Matches -Content $xml -Pattern "<loc>([^<]+)</loc>"
        foreach ($loc in $locs) {
            $norm = Normalize-Url $loc
            if ($norm -and -not $visitedPages.Contains($norm)) {
                $pagesToVisit.Enqueue($norm)
            }
        }
    }
    catch {
        Write-Host "[warn] 無法讀取 sitemap: $map"
    }
}

$homeUrl = Normalize-Url $BaseUrl
if ($homeUrl) { $pagesToVisit.Enqueue($homeUrl) }

$pageRows = New-Object System.Collections.Generic.List[Object]

while ($pagesToVisit.Count -gt 0 -and $visitedPages.Count -lt $MaxPages) {
    $url = $pagesToVisit.Dequeue()
    if ($visitedPages.Contains($url)) { continue }

    $visitedPages.Add($url) | Out-Null

    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $url
        $html = $resp.Content
        $uri = [System.Uri]$url

        $localPath = To-LocalPagePath -RootDir $outDir -UriObj $uri
        $localDir = Split-Path -Parent $localPath
        Ensure-Dir $localDir
        [System.IO.File]::WriteAllText($localPath, $html, [System.Text.Encoding]::UTF8)

        $title = ""
        $titleMatch = [regex]::Match($html, "<title>(.*?)</title>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($titleMatch.Success) {
            $title = ($titleMatch.Groups[1].Value -replace "\s+", " ").Trim()
        }

        $pageRows.Add([pscustomobject]@{
            url = $url
            status = [int]$resp.StatusCode
            title = $title
            local_path = $localPath.Replace((Resolve-Path ".").Path + "\\", "")
        }) | Out-Null

        $linkPatterns = @(
            'href\s*=\s*"([^"]+)"',
            "href\s*=\s*'([^']+)'",
            'src\s*=\s*"([^"]+)"',
            "src\s*=\s*'([^']+)'",
            'srcset\s*=\s*"([^"]+)"',
            "srcset\s*=\s*'([^']+)" + "'",
            'content\s*=\s*"(https?://[^\"]+)"',
            "content\s*=\s*'(https?://[^']+)'"
        )

        $rawUrls = New-Object System.Collections.Generic.List[string]
        foreach ($pattern in $linkPatterns) {
            (Get-Matches -Content $html -Pattern $pattern) | ForEach-Object { $rawUrls.Add($_) | Out-Null }
        }

        foreach ($raw in $rawUrls) {
            if ($raw -match ",") {
                $srcsetParts = $raw.Split(',')
                foreach ($part in $srcsetParts) {
                    $candidate = ($part.Trim() -split "\s+")[0]
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $resolved = Resolve-SiteUri -Raw $candidate -CurrentUri $uri -RootUri $rootUri
                        if ($null -eq $resolved) { continue }
                        $abs = $resolved.AbsoluteUri
                        $ext = [System.IO.Path]::GetExtension($resolved.AbsolutePath)
                        if ([string]::IsNullOrWhiteSpace($ext)) {
                            $normPage = Normalize-Url $abs
                            if ($normPage -and -not $visitedPages.Contains($normPage)) {
                                $pagesToVisit.Enqueue($normPage)
                            }
                        }
                        else {
                            $assetSet.Add($abs) | Out-Null
                        }
                    }
                }
                continue
            }

            $resolvedUri = Resolve-SiteUri -Raw $raw -CurrentUri $uri -RootUri $rootUri
            if ($null -eq $resolvedUri) { continue }

            $absolute = $resolvedUri.AbsoluteUri
            $ext = [System.IO.Path]::GetExtension($resolvedUri.AbsolutePath)

            if ([string]::IsNullOrWhiteSpace($ext)) {
                $normalizedPage = Normalize-Url $absolute
                if ($normalizedPage -and -not $visitedPages.Contains($normalizedPage)) {
                    $pagesToVisit.Enqueue($normalizedPage)
                }
            }
            else {
                $assetSet.Add($absolute) | Out-Null
            }
        }

        if ($VerboseLog) {
            Write-Host "[page] $url"
        }
    }
    catch {
        $pageRows.Add([pscustomobject]@{
            url = $url
            status = "error"
            title = ""
            local_path = ""
        }) | Out-Null
        Write-Host "[warn] 下載頁面失敗: $url"
    }
}

for ($pass = 1; $pass -le $MaxAssetPasses; $pass++) {
    $newFromCss = New-Object System.Collections.Generic.List[string]
    $assets = @($assetSet)

    foreach ($asset in $assets) {
        try {
            $assetUri = [System.Uri]$asset
            $localAssetPath = To-LocalAssetPath -RootDir $outDir -UriObj $assetUri
            $assetDir = Split-Path -Parent $localAssetPath
            Ensure-Dir $assetDir

            if (Test-Path -LiteralPath $localAssetPath) {
                continue
            }

            Invoke-WebRequest -UseBasicParsing -Uri $asset -OutFile $localAssetPath

            if ($localAssetPath.ToLower().EndsWith(".css")) {
                $css = [System.IO.File]::ReadAllText($localAssetPath)
                $cssUrls = Get-Matches -Content $css -Pattern 'url\((?:"|\x27)?([^\)"\x27]+)(?:"|\x27)?\)'
                foreach ($cu in $cssUrls) {
                    $cssResolved = Resolve-SiteUri -Raw $cu -CurrentUri $assetUri -RootUri $rootUri
                    if ($cssResolved -and $assetSet.Add($cssResolved.AbsoluteUri)) {
                        $newFromCss.Add($cssResolved.AbsoluteUri) | Out-Null
                    }
                }
            }
        }
        catch {
            if ($VerboseLog) {
                Write-Host "[warn] 下載資源失敗: $asset"
            }
        }
    }

    if ($newFromCss.Count -eq 0) {
        break
    }
}

$rowsSorted = $pageRows | Sort-Object url -Unique
$rowsSorted | Export-Csv -Path $inventoryPath -NoTypeInformation -Encoding UTF8

$parityLines = New-Object System.Collections.Generic.List[string]
$parityLines.Add("# Parity Checklist") | Out-Null
$parityLines.Add("") | Out-Null
$parityLines.Add("- Source: $BaseUrl") | Out-Null
$parityLines.Add("- Generated: $(Get-Date -Format s)") | Out-Null
$parityLines.Add("- Total pages discovered: $($rowsSorted.Count)") | Out-Null
$parityLines.Add("- Total assets discovered: $($assetSet.Count)") | Out-Null
$parityLines.Add("") | Out-Null

foreach ($row in $rowsSorted) {
    $ok = if ($row.status -eq 200) { "[ ]" } else { "[!]" }
    $line = "$ok URL: $($row.url) | status: $($row.status) | local: $($row.local_path)"
    $parityLines.Add($line) | Out-Null
}

[System.IO.File]::WriteAllLines($parityPath, $parityLines, [System.Text.Encoding]::UTF8)

Write-Host "完成: pages=$($rowsSorted.Count), assets=$($assetSet.Count), inventory=$inventoryPath, parity=$parityPath"
