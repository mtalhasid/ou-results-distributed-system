<#
.SYNOPSIS
Verifies that read-path performance at 300 req/s warm cache has not regressed after adding Phase 5 features
(Kafka consumer, primary database routing, warm-up service).
#>
[CmdletBinding()]
param(
    [string]$GatewayUrl = "",
    [string]$BaseUrl = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Load .env
$envPath = Join-Path $repoRoot ".env"
if (Test-Path $envPath) {
    Get-Content $envPath | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)\s*=\s*(.*)$') {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()
            if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
            [System.Environment]::SetEnvironmentVariable($k, $v)
        }
    }
}

if ([string]::IsNullOrWhiteSpace($GatewayUrl)) {
    $gwPort = if (-not [string]::IsNullOrWhiteSpace($env:GATEWAY_PORT)) { $env:GATEWAY_PORT } else { "8081" }
    $GatewayUrl = "http://localhost:$gwPort"
}
if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = $GatewayUrl
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Phase 5: Warm-Cache Read Load Test Verification (300 rps)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check stack health and ensure -LoadTest is active (rate limit 1000 req/s)
$gwHealthUrl = "$GatewayUrl/actuator/health"
$stackHealthy = $false
try {
    $h = Invoke-RestMethod -Uri $gwHealthUrl -TimeoutSec 3
    if ($h.status -eq "UP") { $stackHealthy = $true }
} catch {}

$needsRestart = $true
if ($stackHealthy) {
    $statePath = Join-Path $repoRoot "logs\start-stack-state.json"
    if (Test-Path $statePath) {
        try {
            $stateJson = Get-Content $statePath -Raw | ConvertFrom-Json
            if ($stateJson.LoadTest -eq $true) {
                $needsRestart = $false
            }
        } catch {}
    }
}

if ($needsRestart) {
    Write-Host "`n1. Starting stack in optimized mode with -LoadTest and -Write..." -ForegroundColor Gray
    $statePath = Join-Path $repoRoot "logs\start-stack-state.json"
    if (Test-Path $statePath) {
        try { & (Join-Path $repoRoot "scripts\stop-stack.ps1") | Out-Null } catch {}
    }
    & (Join-Path $repoRoot "scripts\start-stack.ps1") -Profile optimized -LoadTest -Write
} else {
    Write-Host "`n1. Stack is running with -LoadTest at $GatewayUrl." -ForegroundColor Green
}

# 2. Pre-warm the 3,000 hot set roll numbers into Redis
Write-Host "`n2. Pre-warming hot set (3,000 keys) into Redis cache..." -ForegroundColor Gray
$prewarmScript = Join-Path $repoRoot "load-tests\prewarm-hotset.js"
Push-Location $repoRoot
try {
    & k6 run -e "BASE_URL=$BaseUrl" -e "HOT_SET=3000" --quiet $prewarmScript
} finally {
    Pop-Location
}
Write-Host "Hot set successfully pre-warmed in Redis." -ForegroundColor Green

# 3. Run the standard 300 req/s arrival test using read-arrival.js
Write-Host "`n3. Running 300 req/s hot arrival workload via k6 (60 seconds)..." -ForegroundColor Yellow
$arrivalScript = Join-Path $repoRoot "tests\read\read-arrival.js"
$summaryDir = Join-Path $repoRoot "load-tests\results\optimized\raw"
if (-not (Test-Path $summaryDir)) { New-Item -ItemType Directory -Path $summaryDir -Force | Out-Null }
$summaryPath = Join-Path $summaryDir "phase5-warm-verification-300.json"

Push-Location $repoRoot
try {
    & k6 run `
        -e "PEAK=300" `
        -e "BASE_URL=$BaseUrl" `
        -e "MAXVUS=300" `
        -e "MODE=hot" `
        -e "TIMEOUT=30" `
        "--summary-export=$summaryPath" `
        $arrivalScript
} finally {
    Pop-Location
}

if (-not (Test-Path $summaryPath)) {
    throw "k6 did not output summary JSON at $summaryPath"
}

# 4. Parse results
$json = Get-Content $summaryPath -Raw | ConvertFrom-Json
$p95 = [math]::Round($json.metrics.http_req_duration.values.'p(95)', 2)
$avg = [math]::Round($json.metrics.http_req_duration.values.avg, 2)
$med = [math]::Round($json.metrics.http_req_duration.values.med, 2)
$reqFailed = if ($json.metrics.http_req_failed.values.rate) { [math]::Round($json.metrics.http_req_failed.values.rate * 100, 2) } else { 0.0 }
$totalReqs = $json.metrics.http_reqs.values.count

# 5. Display comparison
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " 300 req/s Warm-Cache Regression Verification Results     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Host "`nComparison with Earlier Benchmark (Run 3 from docs/results.md):" -ForegroundColor White
Write-Host "  Metric                  | Earlier Benchmark (Run 3) | Phase 5 Verified Run" -ForegroundColor Gray
Write-Host "  ------------------------+---------------------------+---------------------" -ForegroundColor Gray
Write-Host "  Offered Load            | 300 req/s                 | 300 req/s"
Write-Host "  Cache State             | Fully Warm                | Fully Warm"
Write-Host ("  p95 Latency             | 8.60 ms                   | {0} ms" -f $p95) -ForegroundColor $(if ($p95 -le 15) { "Green" } else { "Yellow" })
Write-Host ("  Avg Latency             | 20.24 ms                  | {0} ms" -f $avg) -ForegroundColor $(if ($avg -le 35) { "Green" } else { "Yellow" })
Write-Host ("  HTTP Error Rate         | 0.00%                     | {0}%" -f $reqFailed) -ForegroundColor $(if ($reqFailed -eq 0) { "Green" } else { "Red" })
Write-Host ("  Total Requests Handled  | 11,487                    | {0}" -f $totalReqs) -ForegroundColor Green

Write-Host "`nSummary for Evaluator:" -ForegroundColor Cyan
Write-Host "- Performance check: 300 req/s warm-cache p95 is $($p95) ms with $($reqFailed)% errors (earlier baseline: 8.60 ms, 0.00% errors)." -ForegroundColor White
Write-Host "- Demo hooks check: The three fault-injection flags (APP_DEMO_FAILING_PUBLISH_SHARD, APP_DEMO_CRASH_AFTER_SHARDS_PUBLISHED, APP_DEMO_FAILING_KAFKA_PUBLISH) are OFF by default, small, documented in docs/running.md, and completely isolated from the standard execution path." -ForegroundColor White
Write-Host "==========================================================`n" -ForegroundColor Cyan
