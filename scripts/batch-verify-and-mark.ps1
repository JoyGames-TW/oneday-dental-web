param(
    [string]$BaseUrl = "https://dr-allon4.com.tw",
    [string]$SiteDir = "site",
    [string]$ChecklistPath = "site/parity-checklist.md"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$workspace = (Resolve-Path '.').Path
$checklist = Join-Path $workspace $ChecklistPath
$siteRoot = Join-Path $workspace $SiteDir
$reportPath = Join-Path $siteRoot "reports\bulk-content-parity.md"

$lines = Get-Content $checklist
$entries = New-Object System.Collections.Generic.List[Object]

for ($i=0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^- \[ \] (https://dr-allon4\.com\.tw(?<route>/[^ ]*)) \| (?<local>.+)$') {
        $route = $Matches['route']
        $local = $Matches['local']
        if ($route.StartsWith('/wp-json/') -or $route -eq '/wp-json/' -or $route.StartsWith('/feed/') -or $route -eq '/feed/' -or $route.StartsWith('/xmlrpc.php')) {
            continue
        }

        $entries.Add([pscustomobject]@{
            lineIndex = $i
            route = $route
            local = $local
            line = $line
        }) | Out-Null
    }
}

$passed = New-Object System.Collections.Generic.List[Object]
$failed = New-Object System.Collections.Generic.List[Object]

foreach ($e in $entries) {
    $localPath = Join-Path $workspace ($e.local -replace '/', '\\')
    if (-not (Test-Path $localPath)) {
        $failed.Add([pscustomobject]@{ route=$e.route; reason='local-missing' }) | Out-Null
        continue
    }

    $remoteHtml = ''
    try {
        $remoteHtml = (Invoke-WebRequest -UseBasicParsing -Uri ($BaseUrl + $e.route)).Content
    } catch {
        $failed.Add([pscustomobject]@{ route=$e.route; reason='remote-fetch-failed' }) | Out-Null
        continue
    }

    $localHtml = Get-Content $localPath -Raw

    $secR=([regex]::Matches($remoteHtml,'<section\b','IgnoreCase')).Count
    $secL=([regex]::Matches($localHtml,'<section\b','IgnoreCase')).Count
    $imgR=([regex]::Matches($remoteHtml,'<img\b','IgnoreCase')).Count
    $imgL=([regex]::Matches($localHtml,'<img\b','IgnoreCase')).Count
    $ifR=([regex]::Matches($remoteHtml,'<iframe\b','IgnoreCase')).Count
    $ifL=([regex]::Matches($localHtml,'<iframe\b','IgnoreCase')).Count
    $fR=([regex]::Matches($remoteHtml,'<form\b','IgnoreCase')).Count
    $fL=([regex]::Matches($localHtml,'<form\b','IgnoreCase')).Count

    $refs=[regex]::Matches($localHtml,'/wp-content/uploads/[^"''\s<\)]+') | ForEach-Object { $_.Value } | Sort-Object -Unique
    $miss=0
    foreach($u in $refs){
        $p=Join-Path $siteRoot ($u.TrimStart('/') -replace '/','\\')
        if(-not (Test-Path $p)){ $miss++ }
    }

    if ($secR -eq $secL -and $imgR -eq $imgL -and $ifR -eq $ifL -and $fR -eq $fL -and $miss -eq 0) {
        $passed.Add($e) | Out-Null
    } else {
        $failed.Add([pscustomobject]@{ route=$e.route; reason="mismatch sec:$secR/$secL img:$imgR/$imgL iframe:$ifR/$ifL form:$fR/$fL miss:$miss" }) | Out-Null
    }
}

foreach ($p in $passed) {
    $lines[$p.lineIndex] = $lines[$p.lineIndex].Replace('- [ ] ','- [x] ')
}

Set-Content -Path $checklist -Value $lines -Encoding UTF8

$report = New-Object System.Collections.Generic.List[string]
$report.Add('# Bulk Content Parity Batch') | Out-Null
$report.Add('') | Out-Null
$report.Add("- Total candidates: $($entries.Count)") | Out-Null
$report.Add("- Passed and marked: $($passed.Count)") | Out-Null
$report.Add("- Failed: $($failed.Count)") | Out-Null
$report.Add('') | Out-Null

if ($failed.Count -gt 0) {
    $report.Add('## Failed Routes') | Out-Null
    foreach ($f in $failed) {
        $report.Add("- $($f.route) | $($f.reason)") | Out-Null
    }
} else {
    $report.Add('## Failed Routes') | Out-Null
    $report.Add('- none') | Out-Null
}

Set-Content -Path $reportPath -Value $report -Encoding UTF8
Write-Host "bulk verify done: candidates=$($entries.Count), pass=$($passed.Count), fail=$($failed.Count)"
