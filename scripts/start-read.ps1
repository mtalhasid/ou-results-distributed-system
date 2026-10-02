param(
    [ValidateSet("naive", "optimized")]
    [string]$Profile = "naive",
    [string]$JarPath = ".\result-read-service\target\result-read-service-0.0.1-SNAPSHOT.jar",
    [int]$MaxHeapMb = 512
)

$ErrorActionPreference = "Stop"
$Profile = $Profile.ToLowerInvariant()
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $repoRoot ".env"
$resolvedJar = Join-Path $repoRoot $JarPath

if (-not (Test-Path -LiteralPath $envPath)) {
    throw "Root .env file was not found."
}
if (-not (Test-Path -LiteralPath $resolvedJar)) {
    throw "Read-service JAR was not found. Build result-read-service first."
}
if ($MaxHeapMb -lt 256) {
    throw "MaxHeapMb must be at least 256."
}

$profileVariables = if ($Profile -eq "optimized") {
    @("SHARD_1_PRIMARY_REPLICA", "SHARD_2_PRIMARY_REPLICA")
} else {
    @("SHARD_1_PRIMARY", "SHARD_2_PRIMARY")
}
$settings = @{}
foreach ($line in [System.IO.File]::ReadAllLines($envPath)) {
    if ($line -match '^\s*(SHARD_[12]_(?:PRIMARY|PRIMARY_REPLICA))\s*=\s*(.*?)\s*$') {
        $value = $matches[2].Trim()
        if ($value.Length -ge 2 -and
            (($value.StartsWith('"') -and $value.EndsWith('"')) -or
             ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $settings[$matches[1]] = $value
    }
}

foreach ($name in $profileVariables) {
    if ([string]::IsNullOrWhiteSpace($settings[$name])) {
        throw "Missing $name in root .env."
    }
    if ($settings[$name] -notmatch '^postgres(?:ql)?://|^jdbc:postgresql://') {
        throw "$name does not look like a PostgreSQL connection URL."
    }
    [Environment]::SetEnvironmentVariable($name, $settings[$name], "Process")
}

$env:SHARD_MAP_PATH = Join-Path $repoRoot "contracts\shard-map.yml"
$env:SPRING_PROFILES_ACTIVE = $Profile
Push-Location $repoRoot
try {
    & java "-Xms128m" "-Xmx${MaxHeapMb}m" -jar $resolvedJar
    if ($LASTEXITCODE -ne 0) {
        throw "Read service exited with code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
    foreach ($name in $profileVariables) {
        [Environment]::SetEnvironmentVariable($name, $null, "Process")
    }
    Remove-Item Env:SHARD_MAP_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:SPRING_PROFILES_ACTIVE -ErrorAction SilentlyContinue
}
