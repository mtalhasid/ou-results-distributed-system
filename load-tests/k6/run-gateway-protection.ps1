<#
.SYNOPSIS
Runs gateway validation and rate-limit proof scenarios.

.DESCRIPTION
Requires the optimized read-service instances to be registered UP in Eureka,
with cache counters exposed through Actuator. It runs invalid requests first,
then a valid-roll burst, recording k6 summaries and summed counter deltas.
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
$stackHelper = Join-Path $repoRoot "scripts\stack-common.ps1"
. $stackHelper
$k6Script = Join-Path $PSScriptRoot "gateway-protection.js"
$resultsDir = Join-Path $repoRoot "load-tests\results\gateway"
$rawDir = Join-Path $resultsDir "raw"
$summaryPath = Join-Path $resultsDir "summary.md"
$eurekaBaseUrl = $EurekaBaseUrl.TrimEnd('/')
$counterNames = @(
    "result.cache.hit",
    "result.cache.miss",
    "result.cache.negative.hit",
    "result.cache.lock.wait"
)

$k6Command = Get-Command k6 -ErrorAction SilentlyContinue
if ($null -eq $k6Command) {
    throw "k6 was not found on PATH. Install k6 and open a new PowerShell window."
}
if (-not (Test-Path -LiteralPath $k6Script)) {
    throw "Gateway protection k6 script was not found: $k6Script"
}

function Get-ReadCacheCounters {
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

    $values = @{}
    foreach ($counterName in $counterNames) {
        $values[$counterName] = 0.0
        foreach ($port in $ports) {
            $metricsBase = "http://localhost:$port/actuator/metrics"
            try {
                $metric = Invoke-RestMethod -Uri "$metricsBase/$counterName" -TimeoutSec 5
            } catch {
                throw "Cannot read $counterName from $metricsBase. Verify the optimized read instance and its Actuator endpoint."
            }
            $count = $metric.measurements |
                Where-Object { $_.statistic -eq "COUNT" } |
                Select-Object -First 1
            if ($null -eq $count) {
                throw "Actuator did not return a COUNT measurement for $counterName on port $port."
            }
            $values[$counterName] += [double]$count.value
        }
    }
    $values["__ports"] = $ports
    return $values
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
    if ($null -eq $metric) {
        return "n/a"
    }
    $p95 = $metric.Value.PSObject.Properties["p(95)"]
    if ($null -eq $p95 -or $null -eq $p95.Value) {
        return "n/a"
    }
    return ([math]::Round([double]$p95.Value, 2)).ToString(
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Invoke-ProtectionScenario([string]$ScenarioName) {
    $before = Get-ReadCacheCounters
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
    $after = Get-ReadCacheCounters
    if (($before["__ports"] -join ",") -ne ($after["__ports"] -join ",")) {
        throw "The registered read-instance set changed during the $ScenarioName scenario."
    }
    $delta = @{}
    foreach ($counterName in $counterNames) {
        $delta[$counterName] = $after[$counterName] - $before[$counterName]
    }

    return [PSCustomObject]@{
        Name = $ScenarioName
        Summary = $summary
        StatusCounts = (Get-StatusCounts $summary)
        AcceptedP95 = Get-LatencyP95 $summary "gateway_accepted_duration"
        RejectedP95 = Get-LatencyP95 $summary "gateway_rejected_duration"
        Before = $before
        After = $after
        Delta = $delta
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
$burstResult = Invoke-ProtectionScenario "burst"

function Format-StatusCounts($Counts) {
    return (($Counts.GetEnumerator() | Sort-Object { [int]$_.Key } |
        ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", ")
}

function Format-CounterTable($Scenario) {
    $rows = foreach ($counterName in $counterNames) {
        "| $counterName | $($Scenario.Before[$counterName]) | $($Scenario.After[$counterName]) | $($Scenario.Delta[$counterName]) |"
    }
    return $rows -join "`n"
}

$generated = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
$summary = @"
# Gateway protection proof

Generated: $generated

Gateway: ``$GatewayBaseUrl``; Eureka: ``$eurekaBaseUrl``.
Cache counters are summed across all registered UP read instances on ports
``$($invalidResult.Before['__ports'] -join ', ')``; use the optimized profile.
Raw k6 summary exports: ``raw/invalid.json`` and ``raw/burst.json``.

## Invalid roll-number scenario

Configured for 50 requests/second over 20 seconds; every response is expected
to be HTTP 400.

- Status-code counts: $(Format-StatusCounts $invalidResult.StatusCounts)
- Accepted-request p95: $($invalidResult.AcceptedP95) ms
- Rejected-request p95: $($invalidResult.RejectedP95) ms

Cache counter delta (expected zero):

| Counter | Before | After | Delta |
|---|---:|---:|---:|
$(Format-CounterTable $invalidResult)

## Valid-roll burst scenario

Configured for 100 requests/second over 10 seconds to roll number
``$ValidRollNumber``. HTTP 200 responses are accepted; HTTP 429 responses
should be rate-limited before reaching the read service.

- Status-code counts: $(Format-StatusCounts $burstResult.StatusCounts)
- Accepted-request p95: $($burstResult.AcceptedP95) ms
- Rejected-request p95: $($burstResult.RejectedP95) ms

Cache counter delta (only accepted requests should affect the read service):

| Counter | Before | After | Delta |
|---|---:|---:|---:|
$(Format-CounterTable $burstResult)

Negative hits are also included in the hit counter. Compare the hit and miss
deltas with the HTTP 200 count; external concurrent traffic can affect these
Actuator deltas.
"@

[System.IO.File]::WriteAllText(
    $summaryPath,
    $summary,
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host "Wrote gateway protection summary to $summaryPath"
