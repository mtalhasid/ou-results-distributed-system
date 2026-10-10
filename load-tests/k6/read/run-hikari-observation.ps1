param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("naive", "optimized")]
    [string]$Profile,
    [string]$BaseUrl = "http://localhost:8082"
)

$ErrorActionPreference = "Stop"
$Profile = $Profile.ToLowerInvariant()
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resultsDir = Join-Path $repoRoot "load-tests\results\$Profile"
$rawDir = Join-Path $resultsDir "raw"
$csvPath = Join-Path $rawDir "hikari-100.csv"
$k6Script = Join-Path $repoRoot "load-tests\k6\read-baseline.js"
$metricsBase = "$($BaseUrl.TrimEnd('/'))/actuator/metrics"

if (-not (Get-Command k6 -ErrorAction SilentlyContinue)) {
    throw "k6 was not found on PATH."
}
foreach ($metric in @("hikaricp.connections.pending", "hikaricp.connections.active")) {
    try {
        $null = Invoke-RestMethod -Uri "$metricsBase/$metric" -TimeoutSec 5
    } catch {
        throw "Actuator metric '$metric' is unavailable. Rebuild and restart the service with the metrics endpoint exposed, then retry."
    }
}
$poolLimitMetric = Invoke-RestMethod -Uri "$metricsBase/hikaricp.connections.max" -TimeoutSec 5
$poolTag = $poolLimitMetric.availableTags | Where-Object { $_.tag -eq "pool" } | Select-Object -First 1
if ($null -eq $poolTag) {
    throw "Actuator did not report Hikari pool tags; cannot verify the effective pool size."
}
foreach ($poolName in $poolTag.values) {
    $tag = [uri]::EscapeDataString("pool:$poolName")
    $effectivePoolLimit = Invoke-RestMethod -Uri "$metricsBase/hikaricp.connections.max?tag=$tag" -TimeoutSec 5
    $limit = ($effectivePoolLimit.measurements | Where-Object { $_.statistic -eq "VALUE" } | Select-Object -First 1).value
    Write-Host "Effective Hikari maximumPoolSize for ${poolName}: $limit"
}

New-Item -ItemType Directory -Path $rawDir -Force | Out-Null
$rows = [System.Collections.Generic.List[object]]::new()
$k6 = Start-Process -FilePath (Get-Command k6).Source `
    -ArgumentList @(
        "run",
        "-e", "VUS=100",
        "-e", "BASE_URL=$BaseUrl",
        $k6Script
    ) `
    -WorkingDirectory $repoRoot `
    -NoNewWindow `
    -PassThru

try {
    do {
        $pending = Invoke-RestMethod -Uri "$metricsBase/hikaricp.connections.pending" -TimeoutSec 5
        $active = Invoke-RestMethod -Uri "$metricsBase/hikaricp.connections.active" -TimeoutSec 5
        $pendingValue = ($pending.measurements | Where-Object { $_.statistic -eq "VALUE" } | Select-Object -First 1).value
        $activeValue = ($active.measurements | Where-Object { $_.statistic -eq "VALUE" } | Select-Object -First 1).value
        $rows.Add([PSCustomObject]@{
            timestamp = (Get-Date).ToString("o")
            pending = $pendingValue
            active = $activeValue
        })
        $k6.Refresh()
        if (-not $k6.HasExited) {
            Start-Sleep -Seconds 2
        }
    } while (-not $k6.HasExited)
    $k6.WaitForExit()
    if ($k6.ExitCode -ne 0) {
        throw "k6 observation run failed with exit code $($k6.ExitCode)."
    }
}
finally {
    if (-not $k6.HasExited) {
        Stop-Process -Id $k6.Id
    }
}

$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
Write-Host "Wrote Hikari pending/active samples to $csvPath"
