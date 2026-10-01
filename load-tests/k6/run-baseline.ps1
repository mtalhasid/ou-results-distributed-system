param(
    [int[]]$Vus = @(25, 50, 100),
    [ValidateRange(1, 100)][int]$Runs = 3,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*$')][string]$Label = "baseline",
    [string]$BaseUrl = "http://localhost:8082"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$manifestPath = Join-Path $repoRoot "load-tests\seed\out\seed-manifest.json"
$scriptPath = Join-Path $repoRoot "load-tests\k6\read-baseline.js"
$resultsDir = Join-Path $repoRoot "load-tests\results"
$htmlDir = Join-Path $resultsDir "html"

if (-not (Get-Command k6 -ErrorAction SilentlyContinue)) {
    throw "k6 was not found on PATH. Install k6 and open a new PowerShell window."
}
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Seed manifest not found: $manifestPath"
}
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "k6 script not found: $scriptPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$warmupRolls = @{}
foreach ($shard in @("shard1", "shard2")) {
    $group = $manifest.groups | Where-Object { $_.shard -eq $shard } | Select-Object -First 1
    if ($null -eq $group) {
        throw "The seed manifest has no group assigned to $shard."
    }
    $warmupRolls[$shard] = "{0}{1:D2}{2}{3:D3}" -f `
        $group.college_code, [int]$group.batch_year, $group.dept_code, [int]$group.roll_min
}

function Get-MetricValue($Json, [string]$Metric, [string]$ValueName) {
    $metricProperty = $Json.metrics.PSObject.Properties[$Metric]
    if ($null -eq $metricProperty) {
        throw "Expected metric '$Metric' value '$ValueName' was missing from the k6 summary."
    }
    $valueProperty = $metricProperty.Value.PSObject.Properties[$ValueName]
    if ($null -eq $valueProperty) {
        throw "Expected metric '$Metric' value '$ValueName' was missing from the k6 summary."
    }
    return [double]$valueProperty.Value
}

function Get-Median([double[]]$Values) {
    $sorted = @($Values | Sort-Object)
    $middle = [int][math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) {
        return [double]$sorted[$middle]
    }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2
}

New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
New-Item -ItemType Directory -Path $htmlDir -Force | Out-Null
$runResults = @()
$previousDashboard = [Environment]::GetEnvironmentVariable("K6_WEB_DASHBOARD", "Process")
$previousDashboardExport = [Environment]::GetEnvironmentVariable("K6_WEB_DASHBOARD_EXPORT", "Process")
try {
foreach ($vusCount in $Vus) {
    if ($vusCount -lt 1) {
        throw "Every VUS value must be at least 1."
    }

    for ($run = 1; $run -le $Runs; $run++) {
        foreach ($shard in @("shard1", "shard2")) {
            $warmupUrl = "$($BaseUrl.TrimEnd('/'))/api/results/$($warmupRolls[$shard])"
            for ($request = 1; $request -le 5; $request++) {
                $null = Invoke-RestMethod -Uri $warmupUrl -Method Get -TimeoutSec 30
            }
        }

        $fileStem = "$Label-$vusCount-run$run"
        $summaryPath = Join-Path $resultsDir "$fileStem.json"
        $env:K6_WEB_DASHBOARD = "true"
        $env:K6_WEB_DASHBOARD_EXPORT = "load-tests/results/html/$fileStem.html"
        Write-Host "Starting $Label baseline: VUS=$vusCount, run=$run/$Runs"
        Push-Location $repoRoot
        try {
            & k6 run `
                -e "VUS=$vusCount" `
                -e "BASE_URL=$BaseUrl" `
                "--summary-export=$summaryPath" `
                $scriptPath
        }
        finally {
            Pop-Location
        }
        if ($LASTEXITCODE -ne 0) {
            throw "k6 failed for VUS=$vusCount, run=$run (exit code $LASTEXITCODE)."
        }
        if (-not (Test-Path -LiteralPath $summaryPath)) {
            throw "k6 did not create the expected summary file: $summaryPath"
        }

        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $runResults += [PSCustomObject]@{
            Vus = $vusCount
            Run = $run
            P95Ms = Get-MetricValue $summary "http_req_duration" "p(95)"
            P90Ms = Get-MetricValue $summary "http_req_duration" "p(90)"
            AvgMs = Get-MetricValue $summary "http_req_duration" "avg"
            RequestsPerSecond = Get-MetricValue $summary "http_reqs" "rate"
            ErrorRate = Get-MetricValue $summary "http_req_failed" "value"
            File = "$fileStem.json"
        }

        if ($run -lt $Runs) {
            Write-Host "Waiting 20 seconds before the next run."
            Start-Sleep -Seconds 20
        }
    }
    }
}
finally {
    if ($null -eq $previousDashboard) {
        Remove-Item Env:K6_WEB_DASHBOARD -ErrorAction SilentlyContinue
    } else {
        $env:K6_WEB_DASHBOARD = $previousDashboard
    }
    if ($null -eq $previousDashboardExport) {
        Remove-Item Env:K6_WEB_DASHBOARD_EXPORT -ErrorAction SilentlyContinue
    } else {
        $env:K6_WEB_DASHBOARD_EXPORT = $previousDashboardExport
    }
}

$markdown = [System.Collections.Generic.List[string]]::new()
$markdown.Add("# Naive Read Baseline Summary")
$markdown.Add("")
$markdown.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
$markdown.Add("")
$markdown.Add("Values are medians across the runs performed by this invocation. Latencies are milliseconds; error rate is percent.")
$markdown.Add("")
$markdown.Add("| VUs | Median p95 (ms) | Median p90 (ms) | Median avg (ms) | Median req/s | Median errors |")
$markdown.Add("|---:|---:|---:|---:|---:|---:|")
foreach ($vusCount in $Vus) {
    $groupRuns = @($runResults | Where-Object { $_.Vus -eq $vusCount })
    $p95 = Get-Median ([double[]]@($groupRuns | ForEach-Object { $_.P95Ms }))
    $p90 = Get-Median ([double[]]@($groupRuns | ForEach-Object { $_.P90Ms }))
    $avg = Get-Median ([double[]]@($groupRuns | ForEach-Object { $_.AvgMs }))
    $rps = Get-Median ([double[]]@($groupRuns | ForEach-Object { $_.RequestsPerSecond }))
    $errors = 100 * (Get-Median ([double[]]@($groupRuns | ForEach-Object { $_.ErrorRate })))
    $markdown.Add(("| $vusCount | {0:N2} | {1:N2} | {2:N2} | {3:N2} | {4:N3}% |" -f $p95, $p90, $avg, $rps, $errors))
}
$markdown.Add("")
$markdown.Add("## Individual runs")
$markdown.Add("")
$markdown.Add("| VUs | Run | p95 (ms) | p90 (ms) | Average (ms) | Requests/s | Errors | Summary file |")
$markdown.Add("|---:|---:|---:|---:|---:|---:|---:|---|")
foreach ($runResult in $runResults) {
    $markdown.Add(("| $($runResult.Vus) | $($runResult.Run) | {0:N2} | {1:N2} | {2:N2} | {3:N2} | {4:N3}% | $($runResult.File) |" -f `
        $runResult.P95Ms, $runResult.P90Ms, $runResult.AvgMs, $runResult.RequestsPerSecond, (100 * $runResult.ErrorRate))
    )
}
$markdown.Add("")
$markdown.Add("This report uses only the unwarmed rerun files listed above. Historical `baseline-25.json`, `baseline-50.json`, and `baseline-100.json` files are not read or modified.")
$markdown.Add("")
[System.IO.File]::WriteAllLines(
    (Join-Path $resultsDir "baseline-summary.md"),
    $markdown,
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host "Wrote $resultsDir\baseline-summary.md"

$reportScript = Join-Path $repoRoot "load-tests\report\make_report.py"
if (Get-Command python -ErrorAction SilentlyContinue) {
    & python $reportScript
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    & py -3 $reportScript
} else {
    throw "Python 3 was not found on PATH; run load-tests\report\make_report.py to regenerate summaries."
}
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Report generation failed with exit code $LASTEXITCODE."
}
