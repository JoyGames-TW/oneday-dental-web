param(
    [string]$BaseUrl = "https://dr-allon4.com.tw",
    [string]$SiteDir = "site"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$workspace = (Resolve-Path '.').Path
$siteRoot = Join-Path $workspace $SiteDir

function Ensure-Dir([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

# 1) Download Orionicon font files expected by local CSS.
$orionFontsDir = Join-Path $siteRoot "wp-content\themes\dentalia\libs\orionicon\fonts"
Ensure-Dir $orionFontsDir
$orionFiles = @("Orionicon.eot", "Orionicon.woff2", "Orionicon.woff", "Orionicon.ttf", "Orionicon.svg")
foreach ($name in $orionFiles) {
    $outFile = Join-Path $orionFontsDir $name
    if (-not (Test-Path -LiteralPath $outFile)) {
        $url = "$BaseUrl/wp-content/themes/dentalia/libs/orionicon/fonts/$name"
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $outFile
        }
        catch {
            Write-Host "[warn] failed to download Orionicon font: $name"
        }
    }
}

# 2) Download Font Awesome locally.
$faCssDir = Join-Path $siteRoot "assets\vendor\fontawesome\css"
$faWebfontsDir = Join-Path $siteRoot "assets\vendor\fontawesome\webfonts"
Ensure-Dir $faCssDir
Ensure-Dir $faWebfontsDir

$faCssPath = Join-Path $faCssDir "all.min.css"
$faCssUrl = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.4/css/all.min.css"
Invoke-WebRequest -UseBasicParsing -Uri $faCssUrl -OutFile $faCssPath

# Download required webfont files explicitly.
# Avoid parsing CSS url() values because legacy refs may include query/hash fragments.
$faWebfontFiles = @(
    "fa-brands-400.woff2",
    "fa-brands-400.woff",
    "fa-regular-400.woff2",
    "fa-regular-400.woff",
    "fa-solid-900.woff2",
    "fa-solid-900.woff"
)
$faWebfontBases = @(
    "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.4/webfonts",
    "https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@5.15.4/webfonts"
)
foreach ($fileName in $faWebfontFiles) {
    $dest = Join-Path $faWebfontsDir $fileName
    $ok = $false
    foreach ($base in $faWebfontBases) {
        try {
            $source = "$base/$fileName"
            Invoke-WebRequest -UseBasicParsing -Uri $source -OutFile $dest
            if ((Get-Item -LiteralPath $dest).Length -gt 1000) {
                $ok = $true
                break
            }
        }
        catch {
        }
    }
    if (-not $ok) {
        Write-Host "[warn] failed to download Font Awesome webfont: $fileName"
    }
}

# Normalize CSS font URL prefix to local folder.
$faCssContent = Get-Content $faCssPath -Raw
$faCssContent = $faCssContent.Replace('../webfonts/', '../webfonts/')
Set-Content -Path $faCssPath -Value $faCssContent -Encoding UTF8

# 3) Replace external Font Awesome stylesheet URL in all HTML files.
$htmlFiles = Get-ChildItem -Path $siteRoot -Recurse -Filter '*.html' -File
foreach ($file in $htmlFiles) {
    $html = Get-Content $file.FullName -Raw
    $updated = $html

    $updated = [regex]::Replace(
        $updated,
        '<link\s+rel="stylesheet"\s+href="https://use\.fontawesome\.com/releases/v5\.0\.9/css/all\.css"[^>]*>\s*</link>',
        '<link rel="stylesheet" href="/assets/vendor/fontawesome/css/all.min.css">',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $updated = [regex]::Replace(
        $updated,
        '<link\s+rel="stylesheet"\s+href="https://use\.fontawesome\.com/releases/v5\.0\.9/css/all\.css"[^>]*>',
        '<link rel="stylesheet" href="/assets/vendor/fontawesome/css/all.min.css">',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($updated -ne $html) {
        Set-Content -Path $file.FullName -Value $updated -Encoding UTF8
    }
}

Write-Host "icon-font fix done"
