param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("naive", "optimized")]
    [string]$Profile,
    [int[]]$Peaks = @(25, 50, 75),
    [ValidateRange(1, 100)][int]$Runs = 3,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*$')][string]$Label = "baseline",
    [ValidateSet("uniform", "hot")][string]$Mode = "uniform",
    [string]$BaseUrl = "http://localhost:8082",
    [switch]$StopOnBreak,
    [ValidateRange(1, 100000)][int]$MaxVus = 300,
    [ValidateRange(1, 3600)][int]$Timeout = 30
)

$ErrorActionPreference = "Stop"
$Profile = $Profile.ToLowerInvariant()
$Mode = $Mode.ToLowerInvariant()
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$manifestPath = Join-Path $repoRoot "load-tests\seed\out\seed-manifest.json"
$scriptPath = Join-Path $repoRoot "load-tests\k6\read-arrival.js"
$resultsDir = Join-Path $repoRoot "load-tests\results\$Profile"
$htmlDir = Join-Path $resultsDir "html"

if (-not (Get-Command k6 -ErrorAction SilentlyContinue)) {
    throw "k6 was not found on PATH. Install k6 and open a new PowerShell window."
}
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Seed manifest not found: $manifestPath"
}
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Arrival k6 script not found: $scriptPath"
}
if ($Peaks.Count -eq 0 -or @($Peaks | Where-Object { $_ -lt 1 }).Count -gt 0) {
    throw "Peaks must contain positive integer request rates."
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
        return $null
    }
    $valueProperty = $metricProperty.Value.PSObject.Properties[$ValueName]
    if ($null -eq $valueProperty) {
        return $null
    }
    return [double]$valueProperty.Value
}

function Get-ExpectedIterations([int]$Peak) {
    $quarterRate = [math]::Ceiling($Peak * 0.25)
    return ((5 + $quarterRate) / 2 * 20) +
        (($quarterRate + $Peak) / 2 * 5) +
        ($Peak * 30) +
        ($Peak / 2 * 5)
}

New-Item -ItemType Directory -Path $resultsDir, $htmlDir -Force | Out-Null
$runResults = @()
$stopReason = $null
$previousDashboard = [Environment]::GetEnvironmentVariable("K6_WEB_DASHBOARD", "Process")
$previousDashboardExport = [Environment]::GetEnvironmentVariable("K6_WEB_DASHBOARD_EXPORT", "Process")

try {
    foreach ($peak in $Peaks) {
        $stopAtThisPeak = $false
        for ($run = 1; $run -le $Runs; $run++) {
            foreach ($shard in @("shard1", "shard2")) {
                $warmupUrl = "$($BaseUrl.TrimEnd('/'))/api/results/$($warmupRolls[$shard])"
                for ($request = 1; $request -le 5; $request++) {
                    $null = Invoke-RestMethod -Uri $warmupUrl -Method Get -TimeoutSec 30
                }
            }

            $fileStem = "$Label-$Mode-arrival-$peak-run$run"
            $summaryPath = Join-Path $resultsDir "$fileStem.json"
            $dashboardPath = "load-tests/results/$Profile/html/$fileStem.html"
            $env:K6_WEB_DASHBOARD = "true"
            $env:K6_WEB_DASHBOARD_EXPORT = $dashboardPath

            Write-Host "Starting arrival run: label=$Label, mode=$Mode, peak=$peak req/s, timeout=${Timeout}s, run=$run/$Runs"
            Push-Location $repoRoot
            try {
                & k6 run `
                    -e "PEAK=$peak" `
                    -e "BASE_URL=$BaseUrl" `
                    -e "MAXVUS=$MaxVus" `
                    -e "MODE=$Mode" `
                    -e "TIMEOUT=$Timeout" `
                    "--summary-export=$summaryPath" `
                    $scriptPath
            }
            finally {
                Pop-Location
            }
            if ($LASTEXITCODE -ne 0) {
                throw "k6 failed for peak=$peak, run=$run (exit code $LASTEXITCODE)."
            }
            if (-not (Test-Path -LiteralPath $summaryPath)) {
                throw "k6 did not create the expected summary file: $summaryPath"
            }

            $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
            $dropped = Get-MetricValue $summary "dropped_iterations" "count"
            if ($null -eq $dropped) {
                $dropped = Get-MetricValue $summary "dropped_iterations" "value"
            }
            if ($null -eq $dropped) {
                $dropped = 0.0
            }
            $expected = Get-ExpectedIterations $peak
            $runResult = [PSCustomObject]@{
                Label = $Label
                Peak = $peak
                Run = $run
                P95Ms = Get-MetricValue $summary "http_req_duration" "p(95)"
                P90Ms = Get-MetricValue $summary "http_req_duration" "p(90)"
                AvgMs = Get-MetricValue $summary "http_req_duration" "avg"
                ErrorRate = Get-MetricValue $summary "http_req_failed" "value"
                Dropped = [double]$dropped
                Expected = [double]$expected
                DroppedRate = if ($expected -gt 0) { [double]$dropped / $expected } else { 0.0 }
                MaxVusUsed = Get-MetricValue $summary "vus_max" "max"
                HttpRequests = Get-MetricValue $summary "http_reqs" "count"
                SummaryFile = "$fileStem.json"
            }
            foreach ($required in @("P95Ms", "P90Ms", "AvgMs", "ErrorRate", "MaxVusUsed", "HttpRequests")) {
                if ($null -eq $runResult.$required) {
                    throw "Required metric '$required' was missing in $summaryPath."
                }
            }
            $runResults += $runResult

            if ($StopOnBreak) {
                $conditions = @()
                if ($runResult.ErrorRate -gt 0.05) {
                    $conditions += "error rate $([math]::Round($runResult.ErrorRate * 100, 2))% > 5%"
                }
                if ($runResult.DroppedRate -gt 0.05) {
                    $conditions += "dropped iterations $([math]::Round($runResult.DroppedRate * 100, 2))% > 5%"
                }
                if ($runResult.P95Ms -gt 10000) {
                    $conditions += "p95 $([math]::Round($runResult.P95Ms, 2)) ms > 10000 ms"
                }
                if ($conditions.Count -gt 0) {
                    $stopReason = "StopOnBreak at $peak req/s, run $run/$Runs`: " + ($conditions -join "; ")
                    Write-Warning $stopReason
                    $stopAtThisPeak = $true
                    break
                }
            }

            if ($run -lt $Runs) {
                Write-Host "Waiting 20 seconds before the next run."
                Start-Sleep -Seconds 20
            }
        }
        if ($stopAtThisPeak) {
            break
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

if ($runResults.Count -gt 0) {
    $reportScript = Join-Path $repoRoot "load-tests\report\make_report.py"
    if (Get-Command python -ErrorAction SilentlyContinue) {
        & python $reportScript --profile $Profile
    } elseif (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3 $reportScript --profile $Profile
    } else {
        throw "Python 3 was not found on PATH; run load-tests\report\make_report.py to regenerate summaries."
    }
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Report generation failed with exit code $LASTEXITCODE."
    }
}
if ($null -ne $stopReason) {
    Write-Host $stopReason
}
