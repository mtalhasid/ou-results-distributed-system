param(
    [string]$JarPath = ".\api-gateway\target\api-gateway-0.0.1-SNAPSHOT.jar",
    [int]$MaxHeapMb = 512,
    [switch]$LoadTest
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedJar = Join-Path $repoRoot $JarPath

if (-not (Test-Path -LiteralPath $resolvedJar)) {
    throw "Gateway JAR was not found. Build api-gateway first."
}
if ($MaxHeapMb -lt 256) {
    throw "MaxHeapMb must be at least 256."
}

$previousReplenishRate = [Environment]::GetEnvironmentVariable(
    "GATEWAY_RATE_LIMIT_REPLENISH_RATE",
    "Process"
)
$previousBurstCapacity = [Environment]::GetEnvironmentVariable(
    "GATEWAY_RATE_LIMIT_BURST_CAPACITY",
    "Process"
)

if ($LoadTest) {
    $env:GATEWAY_RATE_LIMIT_REPLENISH_RATE = "1000"
    $env:GATEWAY_RATE_LIMIT_BURST_CAPACITY = "2000"
    Write-Host "Gateway rate limit raised for load testing (1000 requests/second, burst 2000) for this process."
}

Push-Location $repoRoot
try {
    & java "-Xms128m" "-Xmx${MaxHeapMb}m" -jar $resolvedJar
    if ($LASTEXITCODE -ne 0) {
        throw "Gateway exited with code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
    if ($LoadTest) {
        [Environment]::SetEnvironmentVariable(
            "GATEWAY_RATE_LIMIT_REPLENISH_RATE",
            $previousReplenishRate,
            "Process"
        )
        [Environment]::SetEnvironmentVariable(
            "GATEWAY_RATE_LIMIT_BURST_CAPACITY",
            $previousBurstCapacity,
            "Process"
        )
    }
}
~