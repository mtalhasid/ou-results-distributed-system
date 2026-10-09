<#
.SYNOPSIS
Builds all three service JARs from source.

.DESCRIPTION
Run from any directory after a fresh clone or after making code changes.
Packages service-discovery, result-read-service, and api-gateway in order,
skipping tests. After this completes, run start-stack.ps1 to start everything.

.EXAMPLE
.\scripts\build.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mvn = Join-Path $repoRoot "api-gateway\mvnw.cmd"

function Build-Service([string]$Name, [string]$PomPath) {
    Write-Host ""
    Write-Host "Building $Name..."
    & $mvn -B -f $PomPath -DskipTests package
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed for $Name."
    }
    Write-Host "$Name built OK."
}

Build-Service "service-discovery"          (Join-Path $repoRoot "service-discovery\pom.xml")
Build-Service "result-read-service"         (Join-Path $repoRoot "result-read-service\pom.xml")
Build-Service "api-gateway"                 (Join-Path $repoRoot "api-gateway\pom.xml")
Build-Service "result-persistence-service" (Join-Path $repoRoot "result-persistence-service\pom.xml")

Write-Host ""
Write-Host "Building result-ingestion-service (TypeScript)..."
Push-Location (Join-Path $repoRoot "result-ingestion-service")
& npm run build
if ($LASTEXITCODE -ne 0) {
    throw "Build failed for result-ingestion-service."
}
Pop-Location
Write-Host "result-ingestion-service built OK."

Write-Host ""
Write-Host "All services built successfully."
Write-Host "Read Path:  .\scripts\start-stack.ps1 -Profile optimized"
Write-Host "Write Path: .\scripts\start-write-stack.ps1"
