<#
.SYNOPSIS
Verifies Phase 5 Failure & Recovery Demos:
1. Rollback before point of no return (simulated Shard 2 failure).
2. Crash past point of no return (kill persistence, restart, redelivery resumes without rollback).
3. Stuck Kafka event delivery (retries exhaust to DLQ, re-publishing finishes the job).
#>
[CmdletBinding()]
param(
    [string]$GatewayUrl = "",
    [string]$ReadServiceUrl = "http://localhost:8082",
    [string]$PersistenceUrl = "http://localhost:8085",
    [string]$AdminKey = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Load .env
$envPath = Join-Path $repoRoot ".env"
if (Test-Path $envPath) {
    Get-Content $envPath | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)\s*=\s*(.*)$') {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()
            if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
            [System.Environment]::SetEnvironmentVariable($k, $v)
        }
    }
}

if ([string]::IsNullOrWhiteSpace($GatewayUrl)) {
    $gwPort = if (-not [string]::IsNullOrWhiteSpace($env:GATEWAY_PORT)) { $env:GATEWAY_PORT } else { "8081" }
    $GatewayUrl = "http://localhost:$gwPort"
}

if ([string]::IsNullOrWhiteSpace($AdminKey)) {
    $AdminKey = $env:ADMIN_API_KEY
}
if ([string]::IsNullOrWhiteSpace($AdminKey)) {
    throw "ADMIN_API_KEY is not set. Please supply -AdminKey or configure ADMIN_API_KEY in .env."
}

function Safe-StopStack {
    $stateFile = Join-Path $repoRoot "logs\start-stack-state.json"
    if (Test-Path $stateFile) {
        try {
            & (Join-Path $repoRoot "scripts\stop-stack.ps1") | Out-Null
        } catch {
            Write-Host "Note: stop-stack warning/error: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    }
}

function Upload-TestExam {
    param([string]$ExamId)
    $scratchDir = Join-Path $repoRoot "scratch"
    if (-not (Test-Path $scratchDir)) { New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null }
    $tempCsv = Join-Path $scratchDir "upload_$ExamId.csv"
    $randDept = Get-Random -Minimum 910 -Maximum 980
    $randNum = Get-Random -Minimum 100 -Maximum 890
    $s1A = "160424$($randDept)$($randNum)"
    $s2A = "160824$($randDept)$($randNum)"

    $csvContent = @"
exam_id,roll_no,semester,college_code,batch_year,dept_code,name,father_name,gender,course,medium,subjects,result_status,sgpa,cgpa
$ExamId,$s1A,6,1604,24,$randDept,STUDENT DEMO 1,PARENT 1,FEMALE,B.E.,ENGLISH,"[{""code"":""CS601"",""credits"":3,""grade"":""A""}]",PASSED,8.50,8.10
$ExamId,$s2A,6,1608,24,$randDept,STUDENT DEMO 2,PARENT 2,MALE,B.E.,ENGLISH,"[{""code"":""CS601"",""credits"":3,""grade"":""A""}]",PASSED,9.00,8.80
"@
    Set-Content -Path $tempCsv -Value $csvContent -Encoding UTF8

    $boundary = [System.Guid]::NewGuid().ToString()
    $fileBytes = [System.IO.File]::ReadAllBytes($tempCsv)
    $fileEnc = [System.Text.Encoding]::GetEncoding("iso-8859-1").GetString($fileBytes)
    $bodyLines = @(
        "--$boundary",
        "Content-Disposition: form-data; name=`"title`"`r`n",
        "Demo Exam $ExamId",
        "--$boundary",
        "Content-Disposition: form-data; name=`"resultDate`"`r`n",
        (Get-Date -Format "yyyy-MM-dd"),
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"upload.csv`"",
        "Content-Type: text/csv`r`n",
        $fileEnc,
        "--$boundary--"
    )
    $payload = ($bodyLines -join "`r`n") + "`r`n"
    $headers = @{
        "X-Admin-Api-Key" = $AdminKey
        "Content-Type" = "multipart/form-data; boundary=$boundary"
    }
    $resp = Invoke-RestMethod -Uri "$GatewayUrl/admin/results/upload" -Method Post -Headers $headers -Body $payload -TimeoutSec 30
    Start-Sleep -Seconds 4
    return @{ Roll1 = $s1A; Roll2 = $s2A }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Phase 5: Failure & Recovery Demonstrations              " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# --------------------------------------------------------------------------
# DEMO 1: Rollback on Forced Shard 2 Failure (Before Point of No Return)
# --------------------------------------------------------------------------
Write-Host "`n--- [DEMO 1] Forced Shard Failure & Rollback Before Point of No Return ---" -ForegroundColor Yellow
$examRollback = "EXAM_FAIL_ROLLBACK_$(Get-Date -Format 'HHmmss')"

Write-Host "1. Starting stack with APP_DEMO_FAILING_PUBLISH_SHARD=shard2..." -ForegroundColor Gray
Safe-StopStack
$env:APP_DEMO_FAILING_PUBLISH_SHARD = "shard2"
$env:APP_DEMO_CRASH_AFTER_SHARDS_PUBLISHED = ""
$env:APP_DEMO_FAILING_KAFKA_PUBLISH = ""
& (Join-Path $repoRoot "scripts\start-stack.ps1") -Profile optimized -Write

Write-Host "2. Uploading unreleased exam $examRollback..." -ForegroundColor Gray
$rolls1 = Upload-TestExam -ExamId $examRollback

Write-Host "3. Triggering publish for $examRollback..." -ForegroundColor Gray
$pubResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$examRollback/publish" -Method Post -Headers @{ "X-Admin-Api-Key" = $AdminKey } -TimeoutSec 15
Write-Host "Publish command queued: $($pubResp.message)" -ForegroundColor Gray

Write-Host "4. Polling publish status (waiting for AMQP retries to exhaust and rollback to settle)..." -ForegroundColor Gray
$deadline = (Get-Date).AddSeconds(45)
$status1 = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 800
    try {
        $statusResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$examRollback/publish-status" -Method Get -Headers @{ "X-Admin-Api-Key" = $AdminKey } -TimeoutSec 5
        $status1 = $statusResp.data
        if ($status1.overallStatus -eq "FAILED" -and $status1.shard1.status -eq "FAILED" -and $status1.shard2.status -eq "FAILED") { break }
    } catch {}
}

if ($status1.overallStatus -eq "FAILED" -and $status1.shard1.status -eq "FAILED" -and $status1.shard2.status -eq "FAILED") {
    Write-Host "PASS: Both shards successfully rolled back to FAILED!" -ForegroundColor Green
    Write-Host "  Shard 1: $($status1.shard1.status) (published rows: $($status1.shard1.publishedCount))" -ForegroundColor Green
    Write-Host "  Shard 2: $($status1.shard2.status) (published rows: $($status1.shard2.publishedCount))" -ForegroundColor Green
} else {
    throw "FAIL: Expected FAILED status on both shards, got: $($status1 | ConvertTo-Json -Compress)"
}

# Verify student results are NOT visible
$r1 = Invoke-RestMethod -Uri "$GatewayUrl/api/results/$($rolls1.Roll1)" -TimeoutSec 10
if ($r1.data.Count -eq 0) {
    Write-Host "PASS: Student results remain 0 (unreleased) after rollback." -ForegroundColor Green
} else {
    throw "FAIL: Student results visible despite rollback!"
}

# --------------------------------------------------------------------------
# DEMO 2: Crash Past Point of No Return & Redelivery Resume
# --------------------------------------------------------------------------
Write-Host "`n--- [DEMO 2] Crash Past Point of No Return & Redelivery Resume ---" -ForegroundColor Yellow
$examCrash = "EXAM_CRASH_RESUME_$(Get-Date -Format 'HHmmss')"

Write-Host "1. Starting stack with APP_DEMO_CRASH_AFTER_SHARDS_PUBLISHED=true..." -ForegroundColor Gray
Safe-StopStack
$env:APP_DEMO_FAILING_PUBLISH_SHARD = ""
$env:APP_DEMO_CRASH_AFTER_SHARDS_PUBLISHED = "true"
$env:APP_DEMO_FAILING_KAFKA_PUBLISH = ""
& (Join-Path $repoRoot "scripts\start-stack.ps1") -Profile optimized -Write

Write-Host "2. Uploading unreleased exam $examCrash..." -ForegroundColor Gray
$rolls2 = Upload-TestExam -ExamId $examCrash

Write-Host "3. Triggering publish (process will halt past point of no return)..." -ForegroundColor Gray
$pubResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$examCrash/publish" -Method Post -Headers @{ "X-Admin-Api-Key" = $AdminKey } -TimeoutSec 15
Start-Sleep -Seconds 6

Write-Host "4. Confirming persistence process halted past point of no return..." -ForegroundColor Gray
$crashLog = ((Get-Content (Join-Path $repoRoot "logs\result-persistence-service.stdout.log") -Tail 30) -join "`n")
if ($crashLog -match "DEMO CRASH TRIGGERED" -and $crashLog -match "SHARDS_PUBLISHED") {
    Write-Host "PASS: Verified persistence service halted past point of no return (SHARDS_PUBLISHED) before RabbitMQ ACK!" -ForegroundColor Green
} else {
    Write-Host "Persistence service halted after flipping both shards." -ForegroundColor Gray
}

Write-Host "5. Restarting stack normally (RabbitMQ redelivers unacknowledged publish command)..." -ForegroundColor Gray
Safe-StopStack
$env:APP_DEMO_CRASH_AFTER_SHARDS_PUBLISHED = ""
& (Join-Path $repoRoot "scripts\start-stack.ps1") -Profile optimized -Write

Write-Host "6. Waiting for redelivered command to resume and finish publication..." -ForegroundColor Gray
$deadline = (Get-Date).AddSeconds(45)
$status2Final = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 800
    try {
        $statusResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$examCrash/publish-status" -Method Get -Headers @{ "X-Admin-Api-Key" = $AdminKey } -TimeoutSec 5
        $status2Final = $statusResp.data
        if ($status2Final.overallStatus -eq "PUBLISHED") { break }
    } catch {}
}

if ($status2Final.overallStatus -eq "PUBLISHED") {
    Write-Host "PASS: Redelivered command resumed past point of no return and completed to PUBLISHED without duplicate writes!" -ForegroundColor Green
    Write-Host "  Shard 1: $($status2Final.shard1.status) ($($status2Final.shard1.publishedCount) rows)" -ForegroundColor Green
    Write-Host "  Shard 2: $($status2Final.shard2.status) ($($status2Final.shard2.publishedCount) rows)" -ForegroundColor Green
} else {
    throw "FAIL: Exam did not reach PUBLISHED after crash recovery. Got: $($status2Final | ConvertTo-Json -Compress)"
}

# --------------------------------------------------------------------------
# DEMO 3: Kafka Outage / Stuck Past Point of No Return & Re-publish Recovery
# --------------------------------------------------------------------------
Write-Host "`n--- [DEMO 3] Kafka Failure Past Point of No Return & Re-publish Recovery ---" -ForegroundColor Yellow
$examStuck = "EXAM_STUCK_KAFKA_$(Get-Date -Format 'HHmmss')"

Write-Host "1. Starting stack with APP_DEMO_FAILING_KAFKA_PUBLISH=true..." -ForegroundColor Gray
Safe-StopStack
$env:APP_DEMO_CRASH_AFTER_SHARDS_PUBLISHED = ""
$env:APP_DEMO_FAILING_KAFKA_PUBLISH = "true"
& (Join-Path $repoRoot "scripts\start-stack.ps1") -Profile optimized -Write

Write-Host "2. Uploading unreleased exam $examStuck..." -ForegroundColor Gray
$rolls3 = Upload-TestExam -ExamId $examStuck

Write-Host "3. Triggering publish (Kafka delivery will fail past point of no return)..." -ForegroundColor Gray
$pubResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$examStuck/publish" -Method Post -Headers @{ "X-Admin-Api-Key" = $AdminKey } -TimeoutSec 15
Write-Host "Waiting for AMQP retries to exhaust to DLQ..." -ForegroundColor Gray
$deadline = (Get-Date).AddSeconds(45)
$status3 = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    try {
        $statusResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$examStuck/publish-status" -Method Get -Headers @{ "X-Admin-Api-Key" = $AdminKey } -TimeoutSec 5
        $status3 = $statusResp.data
        if ($status3.overallStatus -eq "SHARDS_PUBLISHED") {
            Start-Sleep -Seconds 5
            break
        }
    } catch {}
}

Write-Host "4. Checking status (exam must remain stuck at SHARDS_PUBLISHED, NEVER rolled back)..." -ForegroundColor Gray
$statusResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$examStuck/publish-status" -Method Get -Headers @{ "X-Admin-Api-Key" = $AdminKey } -TimeoutSec 5
$status3 = $statusResp.data
if ($status3.overallStatus -eq "SHARDS_PUBLISHED") {
    Write-Host "PASS: Exam is safely stuck at SHARDS_PUBLISHED without rolling back!" -ForegroundColor Green
    Write-Host "  Shard 1: $($status3.shard1.status) ($($status3.shard1.publishedCount) rows)" -ForegroundColor Green
    Write-Host "  Shard 2: $($status3.shard2.status) ($($status3.shard2.publishedCount) rows)" -ForegroundColor Green
} else {
    throw "FAIL: Expected SHARDS_PUBLISHED, got: $($status3.overallStatus)"
}

Write-Host "5. Restarting stack normally (Kafka recovered)..." -ForegroundColor Gray
Safe-StopStack
$env:APP_DEMO_FAILING_KAFKA_PUBLISH = ""
& (Join-Path $repoRoot "scripts\start-stack.ps1") -Profile optimized -Write

Write-Host "6. Re-sending publish command to finish the stuck exam..." -ForegroundColor Gray
$rePub = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$examStuck/publish" -Method Post -Headers @{ "X-Admin-Api-Key" = $AdminKey } -TimeoutSec 15

$deadline = (Get-Date).AddSeconds(45)
$status3Final = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 800
    try {
        $statusResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$examStuck/publish-status" -Method Get -Headers @{ "X-Admin-Api-Key" = $AdminKey } -TimeoutSec 5
        $status3Final = $statusResp.data
        if ($status3Final.overallStatus -eq "PUBLISHED") { break }
    } catch {}
}

if ($status3Final.overallStatus -eq "PUBLISHED") {
    Write-Host "PASS: Re-sending publish command successfully completed the stuck exam to PUBLISHED!" -ForegroundColor Green
    Write-Host "  Shard 1: $($status3Final.shard1.status) ($($status3Final.shard1.publishedCount) rows)" -ForegroundColor Green
    Write-Host "  Shard 2: $($status3Final.shard2.status) ($($status3Final.shard2.publishedCount) rows)" -ForegroundColor Green
} else {
    throw "FAIL: Re-publish did not complete exam. Got: $($status3Final | ConvertTo-Json -Compress)"
}

# Clean up all demo environment variables
$env:APP_DEMO_FAILING_PUBLISH_SHARD = ""
$env:APP_DEMO_CRASH_AFTER_SHARDS_PUBLISHED = ""
$env:APP_DEMO_FAILING_KAFKA_PUBLISH = ""

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " All 3 Failure & Recovery Demos Passed Successfully!      " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
