<#
.SYNOPSIS
Starts the write pipeline: RabbitMQ, Result Persistence Service, and Result Ingestion Service.

.DESCRIPTION
Runs from any directory. Maintains process IDs in logs/write-stack-state.json for clean termination.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $repoRoot "logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}
$statePath = Join-Path $logsDir "write-stack-state.json"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Starting OU Results Write Path Services" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# 1. Start RabbitMQ container
Write-Host "`n[1/3] Ensuring RabbitMQ is running..." -ForegroundColor Yellow
& docker compose up -d rabbitmq
if ($LASTEXITCODE -ne 0) {
    throw "Failed to start RabbitMQ container."
}
Start-Sleep -Seconds 2

# 2. Load .env
$envPath = Join-Path $repoRoot ".env"
if (Test-Path $envPath) {
    Get-Content $envPath | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
        }
    }
}

# 3. Start Result Persistence Service
Write-Host "`n[2/3] Starting Result Persistence Service (Port 8085)..." -ForegroundColor Yellow
$persistenceJar = Join-Path $repoRoot "result-persistence-service\target\result-persistence-service-0.0.1-SNAPSHOT.jar"
if (-not (Test-Path $persistenceJar)) {
    throw "Persistence JAR not found at $persistenceJar. Run mvn package first."
}

$jvmArgs = @(
    "-DSHARD_1_PRIMARY=$($env:SHARD_1_PRIMARY)",
    "-DSHARD_2_PRIMARY=$($env:SHARD_2_PRIMARY)",
    "-jar",
    "`"$persistenceJar`""
)

$persistenceProc = Start-Process -FilePath "java" `
    -ArgumentList $jvmArgs `
    -WorkingDirectory $repoRoot `
    -WindowStyle Hidden `
    -PassThru

Write-Host "Result Persistence Service started (PID: $($persistenceProc.Id))." -ForegroundColor Green

# 4. Start Result Ingestion Service
Write-Host "`n[3/3] Starting Result Ingestion Service (Port 3000)..." -ForegroundColor Yellow
$ingestionDir = Join-Path $repoRoot "result-ingestion-service"
$ingestionEntry = Join-Path $ingestionDir "dist\index.js"
if (-not (Test-Path $ingestionEntry)) {
    Write-Host "Building Ingestion Service TypeScript..." -ForegroundColor Cyan
    Push-Location $ingestionDir
    & npm run build
    Pop-Location
}

$ingestionProc = Start-Process -FilePath "node" `
    -ArgumentList "dist/index.js" `
    -WorkingDirectory $ingestionDir `
    -WindowStyle Hidden `
    -PassThru

Write-Host "Result Ingestion Service started (PID: $($ingestionProc.Id))." -ForegroundColor Green

# Save state
$state = @{
    StartedAt = (Get-Date).ToString("o")
    Services = @(
        @{ Name = "result-persistence-service"; ProcessId = $persistenceProc.Id; Port = 8085 },
        @{ Name = "result-ingestion-service"; ProcessId = $ingestionProc.Id; Port = 3000 }
    )
}
$state | ConvertTo-Json -Depth 4 | Set-Content $statePath

Write-Host "`n==============================================" -ForegroundColor Green
Write-Host " Write Pipeline is UP and Running!" -ForegroundColor Green
Write-Host " Ingestion Service:   http://localhost:3000" -ForegroundColor Green
Write-Host " Persistence Service: http://localhost:8085" -ForegroundColor Green
Write-Host " RabbitMQ Management: http://localhost:15672 (guest/guest)" -ForegroundColor Green
Write-Host " To test: .\scripts\test-write-pipeline.ps1" -ForegroundColor Green
Write-Host " To stop: .\scripts\stop-write-stack.ps1" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
