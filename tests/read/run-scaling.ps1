# Proves horizontal read-tier scaling throughput and latency gains across 1, 2, and 3 Eureka-registered instances.
<#
.SYNOPSIS
Runs scaling arrival-rate tests with 1, 2, and 3 optimized read instances.

.DESCRIPTION
Stops and restarts the stack for each instance count, flushes the cache,
runs arrival-rate tests through the gateway, then generates scaling charts.
Takes about 40 minutes total.
#>
[CmdletBinding()]
param(
    [int[]]$Peaks = @(25, 50, 75),
    [ValidateRange(1, 100)][int]$Runs = 3,
    [ValidateSet("uniform", "hot")][string]$Mode = "hot",
    [string]$Timeout = "10s"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$scriptsDir = Join-Path $repoRoot "scripts"
$instanceCounts = @(1, 2, 3)
$dockerCommand = Get-Command docker -ErrorAction Stop

foreach ($count in $instanceCounts) {
    $label = "scale-${count}inst"
    Write-Host ""
    Write-Host "============================================"
    Write-Host " Scaling test: $count instance(s), label=$label"
    Write-Host "============================================"
    Write-Host ""

    $statePath = Join-Path $repoRoot "logs\start-stack-state.json"
    if (Test-Path -LiteralPath $statePath) {
        Write-Host "Stopping any running stack..."
        try {
            & (Join-Path $scriptsDir "stop-stack.ps1")
        } catch {
            Write-Host "Previous stack already stopped."
        }
    }

    Write-Host "Starting stack with $count instance(s)..."
    & (Join-Path $scriptsDir "start-stack.ps1") -Profile optimized -Instances $count -LoadTest

    Write-Host "Flushing cache..."
    & $dockerCommand.Source compose exec -T redis-cache redis-cli FLUSHDB
    if ($LASTEXITCODE -ne 0) { throw "Could not flush redis-cache." }

    Write-Host "Running arrival tests: peaks=$($Peaks -join ','), mode=$Mode, runs=$Runs"
    & (Join-Path $PSScriptRoot "run-spike-test.ps1") `
        -Profile optimized `
        -Peaks $Peaks `
        -Runs $Runs `
        -Label $label `
        -Mode $Mode `
        -BaseUrl "http://localhost:8081" `
        -Timeout $Timeout

    Write-Host ""
    Write-Host "Completed $count instance(s) test."
}

Write-Host ""
Write-Host "All scaling tests complete. Generating charts..."

$scalingScript = Join-Path $repoRoot "load-tests\report\make_scaling.py"
$pythonVenv = Join-Path $repoRoot ".venv\Scripts\python.exe"
if (Test-Path -LiteralPath $pythonVenv) {
    & $pythonVenv $scalingScript --mode $Mode
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    & python $scalingScript --mode $Mode
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    & py -3 $scalingScript --mode $Mode
} else {
    throw "Python 3 was not found; run load-tests\report\make_scaling.py manually."
}
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Scaling chart generation failed with exit code $LASTEXITCODE."
}

Write-Host ""
Write-Host "Stopping stack..."
& (Join-Path $scriptsDir "stop-stack.ps1") -StopContainers
Write-Host "Done. Charts written to load-tests\results\comparison\"
