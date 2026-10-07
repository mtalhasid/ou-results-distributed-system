<#
.SYNOPSIS
Starts Eureka, Redis, the requested read instances, and the API gateway.

.DESCRIPTION
Run from any directory. Read instances listen on ports 8082, 8083, and onward.
Logs and the process state file are kept in the ignored repository logs folder.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("naive", "optimized")]
    [string]$Profile,
    [ValidateRange(1, 1000)]
    [int]$Instances = 1,
    [switch]$LoadTest,
    [ValidateSet("none", "shard1", "shard2")]
    [string]$FailShard = "none"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $repoRoot "logs"
$statePath = Join-Path $logsDir "start-stack-state.json"
$helperPath = Join-Path $PSScriptRoot "stack-helpers.ps1"
. $helperPath
$readPorts = @(Get-ReadInstancePorts -Count $Instances)
$selectedProfile = $Profile.ToLowerInvariant()
if ($selectedProfile -ne "optimized" -and $FailShard -ne "none") {
    throw "-FailShard is available only with -Profile optimized."
}
$eurekaBaseUrl = "http://localhost:8761"
$eurekaServerUrl = "$eurekaBaseUrl/eureka/"
$configuredReadServiceUrl = [Environment]::GetEnvironmentVariable("READ_SERVICE_URL", "Process")
$effectiveReadServiceUrl = if ([string]::IsNullOrWhiteSpace($configuredReadServiceUrl)) {
    "lb://result-read-service"
} else {
    $configuredReadServiceUrl
}
$readJar = Join-Path $repoRoot "result-read-service\target\result-read-service-0.0.1-SNAPSHOT.jar"
$gatewayJar = Join-Path $repoRoot "api-gateway\target\api-gateway-0.0.1-SNAPSHOT.jar"
$eurekaJar = Join-Path $repoRoot "service-discovery\target\service-discovery-0.0.1-SNAPSHOT.jar"
$mavenWrapper = Join-Path $repoRoot "api-gateway\mvnw.cmd"
$settingsPath = Join-Path $repoRoot ".env"
$script:stackServices = @()
$script:stackComplete = $false

if ($null -eq ("OuResults.HiddenProcessLauncher" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace OuResults
{
    public static class HiddenProcessLauncher
    {
        private const uint GenericRead = 0x80000000;
        private const uint GenericWrite = 0x40000000;
        private const uint ShareRead = 0x00000001;
        private const uint ShareWrite = 0x00000002;
        private const uint CreateAlways = 2;
        private const uint OpenExisting = 3;
        private const uint FileAttributeNormal = 0x00000080;
        private const uint HandleFlagInherit = 0x00000001;
        private const uint StartfUseStdHandles = 0x00000100;
        private const uint CreateNoWindow = 0x08000000;
        private const uint CreateUnicodeEnvironment = 0x00000400;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct StartupInfo
        {
            public int cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public int dwX;
            public int dwY;
            public int dwXSize;
            public int dwYSize;
            public int dwXCountChars;
            public int dwYCountChars;
            public int dwFillAttribute;
            public uint dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessInformation
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public uint dwProcessId;
            public uint dwThreadId;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFile(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetHandleInformation(
            IntPtr handle,
            uint mask,
            uint flags);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateProcess(
            string applicationName,
            StringBuilder commandLine,
            IntPtr processAttributes,
            IntPtr threadAttributes,
            bool inheritHandles,
            uint creationFlags,
            IntPtr environment,
            string currentDirectory,
            ref StartupInfo startupInfo,
            out ProcessInformation processInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        public static int Start(
            string executable,
            string[] arguments,
            string workingDirectory,
            string stdoutPath,
            string stderrPath)
        {
            IntPtr stdin = CreateFile(
                "NUL", GenericRead, ShareRead | ShareWrite, IntPtr.Zero,
                OpenExisting, FileAttributeNormal, IntPtr.Zero);
            IntPtr stdout = CreateFile(
                stdoutPath, GenericWrite, ShareRead | ShareWrite, IntPtr.Zero,
                CreateAlways, FileAttributeNormal, IntPtr.Zero);
            IntPtr stderr = CreateFile(
                stderrPath, GenericWrite, ShareRead | ShareWrite, IntPtr.Zero,
                CreateAlways, FileAttributeNormal, IntPtr.Zero);
            ProcessInformation processInformation = new ProcessInformation();

            try
            {
                if (stdin == new IntPtr(-1) ||
                    stdout == new IntPtr(-1) ||
                    stderr == new IntPtr(-1))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                if (!SetHandleInformation(stdin, HandleFlagInherit, HandleFlagInherit) ||
                    !SetHandleInformation(stdout, HandleFlagInherit, HandleFlagInherit) ||
                    !SetHandleInformation(stderr, HandleFlagInherit, HandleFlagInherit))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }

                StartupInfo startupInfo = new StartupInfo();
                startupInfo.cb = Marshal.SizeOf(typeof(StartupInfo));
                startupInfo.dwFlags = StartfUseStdHandles;
                startupInfo.hStdInput = stdin;
                startupInfo.hStdOutput = stdout;
                startupInfo.hStdError = stderr;

                StringBuilder commandLine = new StringBuilder(Quote(executable));
                foreach (string argument in arguments)
                {
                    commandLine.Append(' ').Append(Quote(argument));
                }

                if (!CreateProcess(
                    executable,
                    commandLine,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    true,
                    CreateNoWindow | CreateUnicodeEnvironment,
                    IntPtr.Zero,
                    workingDirectory,
                    ref startupInfo,
                    out processInformation))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }

                return checked((int)processInformation.dwProcessId);
            }
            finally
            {
                if (processInformation.hThread != IntPtr.Zero)
                    CloseHandle(processInformation.hThread);
                if (processInformation.hProcess != IntPtr.Zero)
                    CloseHandle(processInformation.hProcess);
                if (stdin != new IntPtr(-1))
                    CloseHandle(stdin);
                if (stdout != new IntPtr(-1))
                    CloseHandle(stdout);
                if (stderr != new IntPtr(-1))
                    CloseHandle(stderr);
            }
        }

        private static string Quote(string value)
        {
            if (value.Length > 0 && value.IndexOfAny(new[] { ' ', '\t', '"' }) < 0)
                return value;

            StringBuilder quoted = new StringBuilder();
            quoted.Append('"');
            int backslashes = 0;
            foreach (char character in value)
            {
                if (character == '\\')
                {
                    backslashes++;
                }
                else if (character == '"')
                {
                    quoted.Append('\\', backslashes * 2 + 1).Append('"');
                    backslashes = 0;
                }
                else
                {
                    quoted.Append('\\', backslashes).Append(character);
                    backslashes = 0;
                }
            }
            quoted.Append('\\', backslashes * 2).Append('"');
            return quoted.ToString();
        }
    }
}
"@
}

function Save-StackState {
    $state = [PSCustomObject]@{
        Profile = $selectedProfile
        ReadPorts = @($readPorts)
        LoadTest = [bool]$LoadTest
        FailShard = $FailShard
        ReadServiceUrl = $effectiveReadServiceUrl
        Complete = [bool]$script:stackComplete
        Services = @($script:stackServices)
    }
    [System.IO.File]::WriteAllText(
        $statePath,
        ($state | ConvertTo-Json -Depth 6),
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Ensure-Jar {
    param(
        [string]$JarPath,
        [string]$PomPath,
        [string]$ArtifactName
    )
    $pomDirectory = Split-Path -Parent $PomPath
    $jarIsCurrent = Test-Path -LiteralPath $JarPath
    if ($jarIsCurrent) {
        $jarLastWrite = (Get-Item -LiteralPath $JarPath).LastWriteTimeUtc
        $sourceDirectory = Join-Path $pomDirectory "src"
        $newerSource = Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse |
            Where-Object { $_.LastWriteTimeUtc -gt $jarLastWrite } |
            Select-Object -First 1
        $jarIsCurrent = $null -eq $newerSource -and
            (Get-Item -LiteralPath $PomPath).LastWriteTimeUtc -le $jarLastWrite
    }
    if ($jarIsCurrent) {
        return
    }
    Write-Host "Building missing or stale $ArtifactName JAR."
    & $mavenWrapper -B -f $PomPath -DskipTests package
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $JarPath)) {
        throw "Could not build the $ArtifactName JAR."
    }
}

function Start-StackJar {
    param(
        [string]$Name,
        [string]$JarPath,
        [string[]]$JvmArguments,
        [hashtable]$Environment
    )

    $previousEnvironment = @{}
    foreach ($key in $Environment.Keys) {
        $previousEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], "Process")
    }
    try {
        $safeName = $Name -replace '[^A-Za-z0-9_-]', '-'
        $stdoutPath = Join-Path $logsDir "$safeName.stdout.log"
        $stderrPath = Join-Path $logsDir "$safeName.stderr.log"
        $arguments = @($JvmArguments) + @("-jar", $JarPath)
        $processId = [OuResults.HiddenProcessLauncher]::Start(
            $javaCommand.Source,
            [string[]]$arguments,
            $repoRoot,
            $stdoutPath,
            $stderrPath
        )
    } finally {
        foreach ($key in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $previousEnvironment[$key], "Process")
        }
    }

    $script:stackServices += [PSCustomObject]@{
        Name = $Name
        ProcessId = $processId
        JarPath = $JarPath
    }
    Save-StackState
    return $processId
}

function Wait-ForHttpStatus {
    param(
        [string]$Uri,
        [string]$ExpectedStatus,
        [string]$ServiceName,
        [int]$TimeoutSeconds = 90
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $response = Invoke-RestMethod -Uri $Uri -TimeoutSec 3
            if ([string]$response.status -eq $ExpectedStatus) {
                return
            }
        } catch {
            # Readiness is polled until the service responds or the timeout is reached.
        }
        Start-Sleep -Seconds 1
    }
    throw "$ServiceName did not report $ExpectedStatus at $Uri within $TimeoutSeconds seconds."
}

if (Test-Path -LiteralPath $statePath) {
    $existingState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $allProcessesAlive = $true
    foreach ($service in @($existingState.Services)) {
        if (-not (Test-ManagedJavaProcess -ProcessId ([int]$service.ProcessId) -JarPath $service.JarPath)) {
            $allProcessesAlive = $false
            break
        }
    }
    if ($allProcessesAlive -and @($existingState.Services).Count -gt 0 -and
        [bool]$existingState.Complete) {
        $sameConfiguration = $existingState.Profile -eq $selectedProfile -and
            (@($existingState.ReadPorts) -join ",") -eq ($readPorts -join ",") -and
            [bool]$existingState.LoadTest -eq [bool]$LoadTest -and
            $(if ([string]::IsNullOrWhiteSpace([string]$existingState.FailShard)) { "none" } else { [string]$existingState.FailShard }) -eq $FailShard -and
            $existingState.ReadServiceUrl -eq $effectiveReadServiceUrl
        if (-not $sameConfiguration) {
            throw "A stack is already running with different settings. Stop it with .\scripts\stop-stack.ps1 first."
        }
        Write-Host "The requested stack is already running; no duplicate processes were started."
        Write-Host "Gateway: http://localhost:8080"
        Write-Host "Eureka:  $eurekaBaseUrl"
        foreach ($port in $existingState.ReadPorts) {
            Write-Host "Read:    http://localhost:$port (instance result-read-service:$port)"
        }
        return
    }
    throw "Stack state exists but does not match all running processes. Run .\scripts\stop-stack.ps1 before starting again."
}

if (-not (Test-Path -LiteralPath $settingsPath)) {
    throw "Root .env file was not found."
}
$profileVariables = if ($selectedProfile -eq "optimized") {
    @("SHARD_1_PRIMARY_REPLICA", "SHARD_2_PRIMARY_REPLICA")
} else {
    @("SHARD_1_PRIMARY", "SHARD_2_PRIMARY")
}
$databaseSettings = @{}
foreach ($line in [System.IO.File]::ReadAllLines($settingsPath)) {
    if ($line -match '^\s*(SHARD_[12]_(?:PRIMARY|PRIMARY_REPLICA))\s*=\s*(.*?)\s*$') {
        $value = $matches[2].Trim()
        if ($value.Length -ge 2 -and
            (($value.StartsWith('"') -and $value.EndsWith('"')) -or
             ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $databaseSettings[$matches[1]] = $value
    }
}
foreach ($name in $profileVariables) {
    if ([string]::IsNullOrWhiteSpace($databaseSettings[$name])) {
        throw "Missing $name in root .env."
    }
    if ($databaseSettings[$name] -notmatch '^postgres(?:ql)?://|^jdbc:postgresql://') {
        throw "$name does not look like a PostgreSQL connection URL."
    }
}

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
Ensure-Jar -JarPath $eurekaJar -PomPath (Join-Path $repoRoot "service-discovery\pom.xml") -ArtifactName "service-discovery"
Ensure-Jar -JarPath $readJar -PomPath (Join-Path $repoRoot "result-read-service\pom.xml") -ArtifactName "result-read-service"
Ensure-Jar -JarPath $gatewayJar -PomPath (Join-Path $repoRoot "api-gateway\pom.xml") -ArtifactName "api-gateway"
$javaCommand = Get-Command java -ErrorAction Stop
$dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
if ($null -eq $dockerCommand) {
    throw "Docker CLI was not found on PATH."
}

& $dockerCommand.Source compose up -d redis-cache redis-state
if ($LASTEXITCODE -ne 0) {
    throw "Could not start redis-cache and redis-state with Docker Compose."
}

$eurekaEnvironment = @{
    EUREKA_PORT = "8761"
}
Start-StackJar `
    -Name "service-discovery" `
    -JarPath $eurekaJar `
    -JvmArguments @("-Xms64m", "-Xmx256m") `
    -Environment $eurekaEnvironment | Out-Null
Wait-ForHttpStatus `
    -Uri "$eurekaBaseUrl/actuator/health" `
    -ExpectedStatus "UP" `
    -ServiceName "Eureka"

$commonClientEnvironment = @{
    EUREKA_SERVER_URL = $eurekaServerUrl
    EUREKA_LEASE_RENEWAL_INTERVAL_SECONDS = "2"
    EUREKA_LEASE_EXPIRATION_DURATION_SECONDS = "6"
    EUREKA_REGISTRY_FETCH_INTERVAL_SECONDS = "2"
}
foreach ($port in $readPorts) {
    $readEnvironment = @{}
    foreach ($key in $commonClientEnvironment.Keys) {
        $readEnvironment[$key] = $commonClientEnvironment[$key]
    }
    foreach ($key in $databaseSettings.Keys) {
        $readEnvironment[$key] = $databaseSettings[$key]
    }
    $readEnvironment["SERVER_PORT"] = [string]$port
    $readEnvironment["APP_EXPOSE_INSTANCE_ID"] = "true"
    $readEnvironment["INSTANCE_ID"] = "result-read-service:$port"
    $readEnvironment["SHARD_MAP_PATH"] = Join-Path $repoRoot "contracts\shard-map.yml"
    $readEnvironment["SPRING_PROFILES_ACTIVE"] = $selectedProfile
    if ($selectedProfile -eq "optimized") {
        $readEnvironment["APP_DEMO_FAILING_SHARD"] = $FailShard
    }
    $readEnvironment["REDIS_CACHE_HOST"] = "localhost"
    $readEnvironment["REDIS_CACHE_PORT"] = "6379"
    Start-StackJar `
        -Name "result-read-service-$port" `
        -JarPath $readJar `
        -JvmArguments @("-Xms128m", "-Xmx512m") `
        -Environment $readEnvironment | Out-Null
}

$deadline = [DateTime]::UtcNow.AddSeconds(90)
$registeredInstances = @()
while ([DateTime]::UtcNow -lt $deadline) {
    try {
        $registeredInstances = @(Get-RegisteredReadInstances -EurekaBaseUrl $eurekaBaseUrl)
        $allReadInstancesUp = $true
        foreach ($port in $readPorts) {
            $expectedId = "result-read-service:$port"
            $instance = $registeredInstances |
                Where-Object { $_.InstanceId -eq $expectedId -and $_.Port -eq $port -and $_.Status -eq "UP" } |
                Select-Object -First 1
            if ($null -eq $instance) {
                $allReadInstancesUp = $false
                break
            }
        }
        if ($allReadInstancesUp) {
            break
        }
    } catch {
        $allReadInstancesUp = $false
    }
    Start-Sleep -Seconds 1
}
if (-not $allReadInstancesUp) {
    throw "Not every read instance reported UP in Eureka within 90 seconds."
}

$gatewayEnvironment = @{
    EUREKA_SERVER_URL = $eurekaServerUrl
    EUREKA_LEASE_RENEWAL_INTERVAL_SECONDS = "2"
    EUREKA_LEASE_EXPIRATION_DURATION_SECONDS = "6"
    EUREKA_REGISTRY_FETCH_INTERVAL_SECONDS = "2"
    GATEWAY_PORT = "8080"
    REDIS_STATE_HOST = "localhost"
    REDIS_STATE_PORT = "6380"
}
$gatewayEnvironment["READ_SERVICE_URL"] = $effectiveReadServiceUrl
if ($LoadTest) {
    $gatewayEnvironment["GATEWAY_RATE_LIMIT_REPLENISH_RATE"] = "1000"
    $gatewayEnvironment["GATEWAY_RATE_LIMIT_BURST_CAPACITY"] = "2000"
}
Start-StackJar `
    -Name "api-gateway" `
    -JarPath $gatewayJar `
    -JvmArguments @("-Xms128m", "-Xmx512m") `
    -Environment $gatewayEnvironment | Out-Null
Wait-ForHttpStatus `
    -Uri "http://localhost:8080/actuator/health" `
    -ExpectedStatus "UP" `
    -ServiceName "API gateway"

$script:stackComplete = $true
Save-StackState
Write-Host "Stack started with profile '$selectedProfile' and $Instances read instance(s)."
if ($LoadTest) {
    Write-Host "Gateway rate limit raised for load testing (1000 requests/second, burst 2000)."
}
Write-Host "Gateway: http://localhost:8080"
Write-Host "Eureka:  $eurekaBaseUrl"
foreach ($port in $readPorts) {
    Write-Host "Read:    http://localhost:$port (instance result-read-service:$port)"
}
