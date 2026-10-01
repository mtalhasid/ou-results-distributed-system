param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("naive", "optimized")]
    [string]$Profile,
    [int[]]$Vus = @(25, 50, 100),
    [ValidateRange(1, 100)][int]$Runs = 3,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*$')][string]$Label = "baseline",
    [string]$BaseUrl = "http://localhost:8082"
)

$ErrorActionPreference = "Stop"
$Profile = $Profile.ToLowerInvariant()
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$manifestPath = Join-Path $repoRoot "load-tests\seed\out\seed-manifest.json"
$scriptPath = Join-Path $repoRoot "load-tests\k6\read-baseline.js"
$resultsDir = Join-Path $repoRoot "load-tests\results\$Profile"
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

New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
New-Item -ItemType Directory -Path $htmlDir -Force | Out-Null
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
        $env:K6_WEB_DASHBOARD_EXPORT = "load-tests/results/$Profile/html/$fileStem.html"
        Write-Host "Starting $Label $Profile VU run: VUS=$vusCount, run=$run/$Runs"
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
