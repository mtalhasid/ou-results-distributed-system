<#
.SYNOPSIS
Runs gateway validation and rate-limit proof scenarios.

.DESCRIPTION
Requires the optimized read-service instances to be registered UP in Eureka,
with cache metrics exposed through Actuator. It runs invalid requests first,
then a valid-roll burst, recording k6 summaries and summed metric deltas.

Cache metrics use Spring's built-in cache.gets counter (result=hit / result=miss).
The lock.wait row from the old report is replaced with the shard circuit-breaker
call count delta (resilience4j.circuitbreaker.calls), which equals database reads.
#>
[CmdletBinding()]
param(
    [string]$GatewayBaseUrl = "http://localhost:8080",
    [string]$EurekaBaseUrl = "http://localhost:8761",
    [ValidatePattern('^\d{12}$')]
    [string]$ValidRollNumber = "160423733001"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$stackHelper = Join-Path $repoRoot "scripts\stack-helpers.ps1"
. $stackHelper
$k6Script = Join-Path $PSScriptRoot "gateway-protection.js"
$resultsDir = Join-Path $repoRoot "load-tests\results\gateway"
$rawDir = Join-Path $resultsDir "raw"
$summaryPath = Join-Path $resultsDir "summary.md"
$eurekaBaseUrl = $EurekaBaseUrl.TrimEnd('/')

# Metrics read via Actuator
$cacheMetricName = "cache.gets"
$breakerMetric   = "resilience4j.circuitbreaker.calls"

$k6Command = Get-Command k6 -ErrorAction SilentlyContinue
if ($null -eq $k6Command) {
    throw "k6 was not found on PATH. Install k6 and open a new PowerShell window."
}
if (-not (Test-Path -LiteralPath $k6Script)) {
    throw "Gateway protection k6 script was not found: $k6Script"
}

function Get-MetricCount([string]$BaseUrl, [string]$Uri) {
    try {
        $data = Invoke-RestMethod -Uri "$BaseUrl/actuator/metrics/$Uri" -TimeoutSec 5
        $m = $data.measurements | Where-Object { $_.statistic -eq "COUNT" } | Select-Object -First 1
        if ($null -eq $m) { return 0.0 }
        return [double]$m.value
    } catch { return 0.0 }
}

function Get-ReadMetrics {
    $registered = @(Get-RegisteredReadInstances -EurekaBaseUrl $eurekaBaseUrl)
    if ($registered.Count -eq 0) {
        throw "Eureka has no registered result-read-service instances at $eurekaBaseUrl."
    }
    $notUp = @($registered | Where-Object { $_.Status -ne "UP" })
    if ($notUp.Count -gt 0) {
        throw "One or more registered result-read-service instances are not UP in Eureka."
    }

    $ports = @($registered | ForEach-Object { [int]$_.Port } | Sort-Object -Unique)
    $expectedPorts = @(Get-ReadInstancePorts -Count $ports.Count | Sort-Object)
    if (($ports -join ",") -ne ($expectedPorts -join ",")) {
        throw "Registered read-service ports do not match the stack port sequence (8082 upward)."
    }

    $hits = 0.0; $misses = 0.0; $shard1Calls = 0.0; $shard2Calls = 0.0

    foreach ($port in $ports) {
        $base = "http://localhost:$port"
        $hits        += Get-MetricCount $base "cache.gets?tag=name:result&tag=result:hit"
        $misses      += Get-MetricCount $base "cache.gets?tag=name:result&tag=result:miss"
        $shard1Calls += Get-MetricCount $base "resilience4j.circuitbreaker.calls?tag=name:shard1Database"
        $shard2Calls += Get-MetricCount $base "resilience4j.circuitbreaker.calls?tag=name:shard2Database"
    }

    return [PSCustomObject]@{
        Hits        = $hits
        Misses      = $misses
        Shard1Calls = $shard1Calls
        Shard2Calls = $shard2Calls
        Ports       = $ports
    }
}

function Get-StatusCounts($Summary) {
    $counts = [ordered]@{}
    $metrics = $Summary.metrics
    foreach ($property in $metrics.PSObject.Properties) {
        if ($property.Name -match '^gateway_status_(?<status>\d{3}|other)$') {
            $counts[$matches.status] = [long]$property.Value.count
        }
    }
    if ($counts.Count -eq 0) {
        throw "The k6 summary did not contain gateway_status_* counters."
    }
    return $counts
}

function Get-LatencyP95($Summary, [string]$MetricName) {
    $metric = $Summary.metrics.PSObject.Properties[$MetricName]
    if ($null -eq $metric) { return "n/a" }
    $p95 = $metric.Value.PSObject.Properties["p(95)"]
    if ($null -eq $p95 -or $null -eq $p95.Value) { return "n/a" }
    return ([math]::Round([double]$p95.Value, 2)).ToString(
        [System.Globalization.CultureInfo]::InvariantCulture)
}

function Invoke-ProtectionScenario([string]$ScenarioName) {
    $before = Get-ReadMetrics
    $rawPath = Join-Path $rawDir "$ScenarioName.json"
    Push-Location $repoRoot
    try {
        & $k6Command.Source run `
            -e "SCENARIO=$ScenarioName" `
            -e "BASE_URL=$GatewayBaseUrl" `
            -e "VALID_ROLL_NUMBER=$ValidRollNumber" `
            "--summary-export=$rawPath" `
            $k6Script
        if ($LASTEXITCODE -ne 0) {
            throw "k6 gateway $ScenarioName scenario failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $rawPath)) {
        throw "k6 did not create the expected summary file: $rawPath"
    }
    $summary = Get-Content -LiteralPath $rawPath -Raw | ConvertFrom-Json
    $after = Get-ReadMetrics
    if (($before.Ports -join ",") -ne ($after.Ports -join ",")) {
        throw "The registered read-instance set changed during the $ScenarioName scenario."
    }
    return [PSCustomObject]@{
        Name         = $ScenarioName
        Summary      = $summary
        StatusCounts = (Get-StatusCounts $summary)
        AcceptedP95  = Get-LatencyP95 $summary "gateway_accepted_duration"
        RejectedP95  = Get-LatencyP95 $summary "gateway_rejected_duration"
        Before       = $before
        After        = $after
        HitDelta     = $after.Hits        - $before.Hits
        MissDelta    = $after.Misses      - $before.Misses
        Shard1Delta  = $after.Shard1Calls - $before.Shard1Calls
        Shard2Delta  = $after.Shard2Calls - $before.Shard2Calls
    }
}

New-Item -ItemType Directory -Path $rawDir -Force | Out-Null
Add-Type -AssemblyName System.Net.Http
$httpClient = [System.Net.Http.HttpClient]::new()
try {
    foreach ($suffix in 2..11) {
        $rollNumber = "160423733{0:D3}" -f $suffix
        $warmupUrl = "$($GatewayBaseUrl.TrimEnd('/'))/api/results/$rollNumber"
        $response = $httpClient.GetAsync($warmupUrl).GetAwaiter().GetResult()
        Write-Host "Warm-up roll $rollNumber returned HTTP $([int]$response.StatusCode)"
        $response.Dispose()
    }
} finally {
    $httpClient.Dispose()
}

$invalidResult = Invoke-ProtectionScenario "invalid"
$burstResult   = Invoke-ProtectionScenario "burst"

function Format-StatusCounts($Counts) {
    return (($Counts.GetEnumerator() | Sort-Object { if ($_.Key -match '^\d+$') { [int]$_.Key } else { 9999 } } |
        ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", ")
}

$generated = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
$report = @"
# Gateway protection proof

Generated: $generated

Gateway: ``$GatewayBaseUrl``; Eureka: ``$eurekaBaseUrl``.
Cache metrics (cache.gets) and circuit-breaker call counts are summed across
all registered UP read instances on ports ``$($invalidResult.Before.Ports -join ', ')``;
use the optimized profile.
Raw k6 summary exports: ``raw/invalid.json`` and ``raw/burst.json``.

## Invalid roll-number scenario

Configured for 50 requests/second over 20 seconds; every response is expected
to be HTTP 400.

- Status-code counts: $(Format-StatusCounts $invalidResult.StatusCounts)
- Accepted-request p95: $($invalidResult.AcceptedP95) ms
- Rejected-request p95: $($invalidResult.RejectedP95) ms

Cache metric delta (expected zero — invalid requests are rejected before the read service):

| Metric | Before | After | Delta |
|---|---:|---:|---:|
| cache.gets (hit) | $($invalidResult.Before.Hits) | $($invalidResult.After.Hits) | $($invalidResult.HitDelta) |
| cache.gets (miss) | $($invalidResult.Before.Misses) | $($invalidResult.After.Misses) | $($invalidResult.MissDelta) |
| shard1 breaker calls | $($invalidResult.Before.Shard1Calls) | $($invalidResult.After.Shard1Calls) | $($invalidResult.Shard1Delta) |
| shard2 breaker calls | $($invalidResult.Before.Shard2Calls) | $($invalidResult.After.Shard2Calls) | $($invalidResult.Shard2Delta) |

## Valid-roll burst scenario

Configured for 100 requests/second over 10 seconds to roll number
``$ValidRollNumber``. HTTP 200 responses are accepted; HTTP 429 responses
should be rate-limited before reaching the read service; HTTP 503 responses
indicate the bulkhead or circuit breaker rejected the request.

- Status-code counts: $(Format-StatusCounts $burstResult.StatusCounts)
- Accepted-request p95: $($burstResult.AcceptedP95) ms
- Rejected-request p95: $($burstResult.RejectedP95) ms

Cache metric delta (only accepted requests should affect the read service):

| Metric | Before | After | Delta |
|---|---:|---:|---:|
| cache.gets (hit) | $($burstResult.Before.Hits) | $($burstResult.After.Hits) | $($burstResult.HitDelta) |
| cache.gets (miss) | $($burstResult.Before.Misses) | $($burstResult.After.Misses) | $($burstResult.MissDelta) |
| shard1 breaker calls | $($burstResult.Before.Shard1Calls) | $($burstResult.After.Shard1Calls) | $($burstResult.Shard1Delta) |
| shard2 breaker calls | $($burstResult.Before.Shard2Calls) | $($burstResult.After.Shard2Calls) | $($burstResult.Shard2Delta) |

The miss delta equals the number of cold keys that required a database read.
Cache hits are served without a database call. Compare the shard breaker call
delta with the miss delta; they should be equal for a single-instance stack.
"@

[System.IO.File]::WriteAllText(
    $summaryPath,
    $report,
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host "Wrote gateway protection summary to $summaryPath"
