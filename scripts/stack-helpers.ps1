function Get-ReadInstancePorts {
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 1000)]
        [int]$Count
    )

    $basePort = 8082
    if (($basePort + $Count - 1) -gt 65535) {
        throw "The requested read-instance count exceeds the available TCP ports."
    }
    return @(
        for ($index = 0; $index -lt $Count; $index++) {
            $basePort + $index
        }
    )
}

function Get-RegisteredReadInstances {
    param(
        [string]$EurekaBaseUrl = "http://localhost:8761"
    )

    $registryUrl = "$($EurekaBaseUrl.TrimEnd('/'))/eureka/apps/RESULT-READ-SERVICE"
    try {
        $application = Invoke-RestMethod `
            -Uri $registryUrl `
            -Headers @{ Accept = "application/json" } `
            -TimeoutSec 5
    } catch {
        throw "Could not read registered result-read-service instances from $registryUrl."
    }

    $instances = @($application.application.instance)
    if ($instances.Count -eq 0 -or $null -eq $instances[0]) {
        return @()
    }

    return @(
        foreach ($instance in $instances) {
            $portValue = $instance.port
            if ($null -ne $portValue -and $null -ne $portValue.PSObject.Properties["$"]) {
                $portValue = $portValue.PSObject.Properties["$"].Value
            }
            if ($null -eq $portValue -or $null -eq $instance.instanceId -or
                $null -eq $instance.status) {
                throw "Eureka returned a result-read-service instance without an instance ID, port, or status."
            }
            [PSCustomObject]@{
                InstanceId = [string]$instance.instanceId
                Port = [int]$portValue
                Status = [string]$instance.status
            }
        }
    )
}

function Test-ManagedJavaProcess {
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId,
        [Parameter(Mandatory)]
        [string]$JarPath
    )

    $process = Get-CimInstance -ClassName Win32_Process `
        -Filter "ProcessId = $ProcessId" `
        -ErrorAction SilentlyContinue
    if ($null -eq $process -or $process.Name -notmatch '^java(w)?\.exe$') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($process.CommandLine)) {
        return $false
    }

    $resolvedJar = [System.IO.Path]::GetFullPath($JarPath)
    return $process.CommandLine.IndexOf(
        $resolvedJar,
        [System.StringComparison]::OrdinalIgnoreCase
    ) -ge 0
}
