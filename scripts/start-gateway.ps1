param(
    [string]$JarPath = ".\api-gateway\target\api-gateway-0.0.1-SNAPSHOT.jar",
    [int]$MaxHeapMb = 512
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

Push-Location $repoRoot
try {
    & java "-Xms128m" "-Xmx${MaxHeapMb}m" -jar $resolvedJar
    if ($LASTEXITCODE -ne 0) {
        throw "Gateway exited with code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
