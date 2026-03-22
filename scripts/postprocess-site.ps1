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

function Is-Asset([System.Uri]$UriObj) {
    $ext = [System.IO.Path]::GetExtension($UriObj.AbsolutePath).ToLowerInvariant()
    $assetExt = @(
        ".css", ".js", ".jpg", ".jpeg", ".png", ".webp", ".gif", ".svg", ".ico", ".woff", ".woff2", ".ttf", ".eot", ".otf", ".mp4", ".webm", ".mp3", ".wav", ".pdf", ".json", ".xml"
    )
    return $assetExt -contains $ext
}

function To-LocalPath([string]$RootDir, [System.Uri]$UriObj) {
    $cleanPath = $UriObj.AbsolutePath.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($cleanPath)) {
        return Join-Path $RootDir "index.html"
    }
    return Join-Path $RootDir $cleanPath
}

$workspace = (Resolve-Path ".").Path
$targetRoot = Join-Path $workspace $SiteDir
if (-not (Test-Path -LiteralPath $targetRoot)) {
    throw "Site directory not found: $targetRoot"
}

$rootUri = [System.Uri]$BaseUrl
$htmlFiles = Get-ChildItem -Path $targetRoot -Recurse -Filter "*.html" -File

$assetUrls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($file in $htmlFiles) {
    $html = [System.IO.File]::ReadAllText($file.FullName)

    $matches = [regex]::Matches($html, 'https?:\/\/dr-allon4\.com\.tw[^"''\s<)]+', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($m in $matches) {
        $raw = $m.Value -replace "&amp;", "&"
        try {
            $uri = [System.Uri]$raw
            if ($uri.Host -eq $rootUri.Host -and (Is-Asset -UriObj $uri)) {
                $assetUrls.Add($uri.AbsoluteUri) | Out-Null
            }
        }
        catch {
        }
    }

    $html = [regex]::Replace($html, 'https?:\/\/dr-allon4\.com\.tw\/', '/')
    $html = [regex]::Replace($html, '//dr-allon4\.com\.tw/', '/')
    $html = [regex]::Replace($html, 'https:\\/\\/dr-allon4\.com\.tw\\/', '\\/')

    [System.IO.File]::WriteAllText($file.FullName, $html, [System.Text.Encoding]::UTF8)
}

foreach ($url in $assetUrls) {
    try {
        $uri = [System.Uri]$url
        $local = To-LocalPath -RootDir $targetRoot -UriObj $uri
        Ensure-Dir (Split-Path -Parent $local)
        if (-not (Test-Path -LiteralPath $local)) {
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $local
        }
    }
    catch {
    }
}

$componentsDir = Join-Path $targetRoot "_components"
Ensure-Dir $componentsDir
$assetsJsDir = Join-Path $targetRoot "assets\js"
Ensure-Dir $assetsJsDir

$indexPath = Join-Path $targetRoot "index.html"
if (Test-Path -LiteralPath $indexPath) {
    $homeHtml = [System.IO.File]::ReadAllText($indexPath)

    $headerPattern = "<header[^>]*site-header[^>]*>.*?<\/header>"
    $footerPattern = "<footer[^>]*>.*?<\/footer>"

    $headerMatch = [regex]::Match($homeHtml, $headerPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $footerMatch = [regex]::Match($homeHtml, $footerPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    if ($headerMatch.Success) {
        [System.IO.File]::WriteAllText((Join-Path $componentsDir "header.html"), $headerMatch.Value, [System.Text.Encoding]::UTF8)
    }
    if ($footerMatch.Success) {
        [System.IO.File]::WriteAllText((Join-Path $componentsDir "footer.html"), $footerMatch.Value, [System.Text.Encoding]::UTF8)
    }

    $loaderJs = @'
(async function () {
  async function hydrate(placeholderSelector, fragmentPath) {
    var placeholder = document.querySelector(placeholderSelector);
    if (!placeholder) return;
    try {
      var res = await fetch(fragmentPath, { cache: "no-store" });
      if (!res.ok) return;
      var html = await res.text();
      var wrap = document.createElement("div");
      wrap.innerHTML = html;
      var node = wrap.firstElementChild;
      if (!node) return;
      placeholder.replaceWith(node);
    } catch (e) {
    }
  }

  await hydrate('[data-component="site-header"]', '/_components/header.html');
  await hydrate('[data-component="site-footer"]', '/_components/footer.html');
})();
'@
    [System.IO.File]::WriteAllText((Join-Path $assetsJsDir "components-loader.js"), $loaderJs, [System.Text.Encoding]::UTF8)

    foreach ($file in $htmlFiles) {
        $html = [System.IO.File]::ReadAllText($file.FullName)

        if ($headerMatch.Success) {
            $html = [regex]::Replace($html, $headerPattern, '<div data-component="site-header"></div>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        if ($footerMatch.Success) {
            $html = [regex]::Replace($html, $footerPattern, '<div data-component="site-footer"></div>', [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }

        $html = [regex]::Replace($html, '<script\s+src="/assets/js/components-loader\.js"></script>', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $html = $html -replace '</body>', '<script src="/assets/js/components-loader.js"></script></body>'

        [System.IO.File]::WriteAllText($file.FullName, $html, [System.Text.Encoding]::UTF8)
    }
}

$inventoryPath = Join-Path $targetRoot "inventory.csv"
$parityPath = Join-Path $targetRoot "parity-checklist.md"

$rows = New-Object System.Collections.Generic.List[Object]
foreach ($file in $htmlFiles) {
    $rel = $file.FullName.Substring($targetRoot.Length).TrimStart('\\') -replace "\\", "/"
    $urlPath = if ($rel -eq "index.html") { "/" } else { "/" + ($rel -replace "/index\.html$", "/") }

    $content = [System.IO.File]::ReadAllText($file.FullName)
    $title = ""
    $m = [regex]::Match($content, "<title>(.*?)<\/title>", [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) {
        $title = ($m.Groups[1].Value -replace "\s+", " ").Trim()
    }

    $rows.Add([pscustomobject]@{
        url = "$BaseUrl$urlPath"
        status = 200
        title = $title
        local_path = "$SiteDir/$rel"
        parity_status = "pending"
    }) | Out-Null
}

$rowsSorted = $rows | Sort-Object url -Unique
$rowsSorted | Export-Csv -Path $inventoryPath -NoTypeInformation -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Parity Checklist") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Source: $BaseUrl") | Out-Null
$lines.Add("- Generated: $(Get-Date -Format s)") | Out-Null
$lines.Add("- Total local pages: $($rowsSorted.Count)") | Out-Null
$lines.Add("- Total localized assets: $($assetUrls.Count)") | Out-Null
$lines.Add("") | Out-Null

foreach ($r in $rowsSorted) {
    $lines.Add("- [ ] $($r.url) | $($r.local_path)") | Out-Null
}

[System.IO.File]::WriteAllLines($parityPath, $lines, [System.Text.Encoding]::UTF8)

Write-Host "postprocess 完成: pages=$($rowsSorted.Count), assets=$($assetUrls.Count)"
