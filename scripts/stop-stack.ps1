[CmdletBinding()]
param(
    [switch]$StopContainers,
    [switch]$ReadInstancesOnly
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $repoRoot "logs"
$statePath = Join-Path $logsDir "start-stack-state.json"
. (Join-Path $PSScriptRoot "stack-helpers.ps1")

if (-not (Test-Path -LiteralPath $statePath)) {
    throw "Stack state was not found at $statePath."
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$services = @($state.Services)
if ($ReadInstancesOnly) {
    $services = @($services | Where-Object { $_.Name -like "result-read-service-*" })
    if ($services.Count -eq 0) {
        Write-Host "No read instances are recorded in the stack state."
        return
    }
}
[array]::Reverse($services)
foreach ($service in $services) {
    $processId = [int]$service.ProcessId
    if (-not (Test-ManagedJavaProcess -ProcessId $processId -JarPath $service.JarPath)) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -ne $process) {
            throw "Process $processId no longer matches the recorded $($service.Name) JAR; leaving it untouched."
        }
        Write-Host "Already stopped: $($service.Name)"
        continue
    }
    Stop-Process -Id $processId -ErrorAction Stop
    Write-Host "Stopped $($service.Name) (PID $processId)."
}

if ($ReadInstancesOnly) {
    $state.Services = @($state.Services | Where-Object { $_.Name -notlike "result-read-service-*" })
    $state.Complete = $false
    [System.IO.File]::WriteAllText(
        $statePath,
        ($state | ConvertTo-Json -Depth 6),
        [System.Text.UTF8Encoding]::new($false)
    )
    Write-Host "Read instances stopped. Eureka, the gateway, Redis containers, and stack state remain."
    return
}

if ($StopContainers) {
    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if ($null -eq $dockerCommand) {
        throw "Docker CLI was not found; application processes stopped but Redis containers were left running."
    }
    & $dockerCommand.Source compose stop redis-cache redis-state
    if ($LASTEXITCODE -ne 0) {
        throw "Application processes stopped, but Docker Compose could not stop the Redis containers."
    }
}

Remove-Item -LiteralPath $statePath -Force
Write-Host "Stack stopped. Redis containers $(if ($StopContainers) { 'were stopped' } else { 'remain running' }); logs remain in $logsDir."
