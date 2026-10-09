<#
.SYNOPSIS
Stops the write pipeline services (Persistence & Ingestion).

.DESCRIPTION
Stops processes recorded in logs/write-stack-state.json and optionally shuts down RabbitMQ container.
#>
[CmdletBinding()]
param(
    [switch]$StopRabbitMQ
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $repoRoot "logs"
$statePath = Join-Path $logsDir "write-stack-state.json"

if (-not (Test-Path $statePath)) {
    Write-Host "No active write stack state found at $statePath." -ForegroundColor Yellow
    return
}

$state = Get-Content $statePath -Raw | ConvertFrom-Json
$services = @($state.Services)

foreach ($service in $services) {
    $procId = [int]$service.ProcessId
    $process = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($null -ne $process) {
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        Write-Host "Stopped $($service.Name) (PID: $procId)." -ForegroundColor Green
    } else {
        Write-Host "Already stopped: $($service.Name)" -ForegroundColor Gray
    }
}

Remove-Item $statePath -Force -ErrorAction SilentlyContinue

if ($StopRabbitMQ) {
    Write-Host "Stopping RabbitMQ container..." -ForegroundColor Yellow
    & docker compose stop rabbitmq
    Write-Host "RabbitMQ container stopped." -ForegroundColor Green
}

Write-Host "Write pipeline stopped successfully." -ForegroundColor Green
