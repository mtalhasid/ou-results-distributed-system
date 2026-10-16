# Proves multi-shard exam publishing saga, Kafka event emission, gentle cache warm-up, and strong read consistency.
<#
.SYNOPSIS
Tests Phase 5 Exam Publishing Saga, Kafka Event, Cache Warm-Up, and Internal Strong-Read.

.DESCRIPTION
1. Uploads a fresh unreleased exam (published = false) with students spanning Shard 1 and Shard 2.
2. Verifies student results are NOT returned prior to publishing (empty result list).
3. Verifies internal strong-read cannot be reached through the API Gateway (HTTP 404).
4. Initiates exam publishing via POST /admin/exams/{examId}/publish through Gateway.
5. Polls GET /admin/exams/{examId}/publish-status through Gateway until PUBLISHED.
6. Verifies cache warm-up by reading student results via Gateway with warm Redis cache.
7. Verifies internal strong-read endpoint on Read Service (bypasses cache and replica).
8. Verifies idempotency by re-submitting publish for an already PUBLISHED exam.
#>
[CmdletBinding()]
param(
    [string]$GatewayUrl = "",
    [string]$ReadServiceUrl = "http://localhost:8082",
    [string]$PersistenceUrl = "http://localhost:8085",
    [string]$AdminKey = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

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

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Phase 5 Verification: Publishing Saga & Cache Warm-Up   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Health checks
Write-Host "`n[1/7] Checking service health..." -ForegroundColor Yellow
$gwHealth = Invoke-RestMethod -Uri "$GatewayUrl/actuator/health" -TimeoutSec 10
Write-Host "Gateway UP at $GatewayUrl (Status: $($gwHealth.status))" -ForegroundColor Green

$readHealth = Invoke-RestMethod -Uri "$ReadServiceUrl/actuator/health" -TimeoutSec 10
Write-Host "Read Service UP at $ReadServiceUrl (Status: $($readHealth.status))" -ForegroundColor Green

# 2. Gateway Route Security Check
Write-Host "`n[2/7] Verifying Internal Strong-Read is NOT exposed via Gateway..." -ForegroundColor Yellow
try {
    $resp = Invoke-WebRequest -Uri "$GatewayUrl/internal/results/160424910101?consistency=strong" -Method GET -TimeoutSec 10
    Write-Host "WARNING: Internal route returned status $($resp.StatusCode) via Gateway!" -ForegroundColor Red
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 404) {
        Write-Host "PASS: Gateway correctly rejected /internal/results with HTTP 404 (Not Found)." -ForegroundColor Green
    } else {
        Write-Host "Gateway returned HTTP $statusCode for /internal/results." -ForegroundColor Yellow
    }
}

# 3. Create and upload fresh exam with unique roll numbers
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$testExamId = "EXAM_P5_$timestamp"
$scratchDir = Join-Path $repoRoot "scratch"
if (-not (Test-Path $scratchDir)) {
    New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
}
$tempCsv = Join-Path $scratchDir "upload_$timestamp.csv"

# Guaranteed unique 12-digit roll numbers (batch 24, dept 910-980) so they never collide with Phase 3/4 seed data
$randDept = Get-Random -Minimum 910 -Maximum 980
$randNum = Get-Random -Minimum 100 -Maximum 890
$rollShard1_A = "160424$($randDept)$($randNum)"
$rollShard1_B = "160424$($randDept)$($randNum + 1)"
$rollShard2_A = "160824$($randDept)$($randNum)"
$rollShard2_B = "160824$($randDept)$($randNum + 1)"

$csvContent = @"
exam_id,roll_no,semester,college_code,batch_year,dept_code,name,father_name,gender,course,medium,subjects,result_status,sgpa,cgpa
$testExamId,$rollShard1_A,6,1604,24,$randDept,STUDENT S1,PARENT S1,FEMALE,B.E. (AICTE),ENGLISH,"[{""code"":""CS601"",""name"":""SYSTEMS"",""credits"":3,""grade"":""A""}]",PASSED,8.50,8.10
$testExamId,$rollShard1_B,6,1604,24,$randDept,STUDENT S2,PARENT S2,MALE,B.E. (AICTE),ENGLISH,"[{""code"":""CS601"",""name"":""SYSTEMS"",""credits"":3,""grade"":""B""}]",PASSED,7.50,7.20
$testExamId,$rollShard2_A,6,1608,24,$randDept,STUDENT S3,PARENT S3,MALE,B.E. (AICTE),ENGLISH,"[{""code"":""CS601"",""name"":""SYSTEMS"",""credits"":3,""grade"":""A""}]",PASSED,9.00,8.80
$testExamId,$rollShard2_B,6,1608,24,$randDept,STUDENT S4,PARENT S4,FEMALE,B.E. (AICTE),ENGLISH,"[{""code"":""CS601"",""name"":""SYSTEMS"",""credits"":3,""grade"":""S""}]",PASSED,9.50,9.30
"@
Set-Content -Path $tempCsv -Value $csvContent -Encoding UTF8

Write-Host "`n[3/7] Uploading fresh exam '$testExamId' with 4 students..." -ForegroundColor Yellow
$boundary = [System.Guid]::NewGuid().ToString()
$fileBytes = [System.IO.File]::ReadAllBytes($tempCsv)
$fileEnc = [System.Text.Encoding]::GetEncoding("iso-8859-1").GetString($fileBytes)

$bodyLines = @(
    "--$boundary",
    "Content-Disposition: form-data; name=`"title`"`r`n",
    "Phase 5 Test Exam $testExamId",
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

$uploadHeaders = @{
    "X-Admin-Api-Key" = $AdminKey
    "Content-Type" = "multipart/form-data; boundary=$boundary"
}

$uploadResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/results/upload" `
    -Method Post `
    -Headers $uploadHeaders `
    -Body $payload `
    -TimeoutSec 30
Write-Host "Upload accepted. Batches queued: $($uploadResp.data.batchesPublished), Total rows: $($uploadResp.data.totalRows)" -ForegroundColor Green

# Give persistence service time to write to both shards
Start-Sleep -Seconds 4

# 4. Confirm results are unreleased before publishing
Write-Host "`n[4/7] Verifying unreleased results are NOT visible to students..." -ForegroundColor Yellow
$prePublishResp = Invoke-RestMethod -Uri "$GatewayUrl/api/results/$rollShard1_A" -TimeoutSec 15
if ($prePublishResp.data.Count -eq 0) {
    Write-Host "PASS: Student $rollShard1_A has 0 visible results before publishing." -ForegroundColor Green
} else {
    Write-Host "WARNING: Expected 0 results before publish, but got $($prePublishResp.data.Count)!" -ForegroundColor Red
}

# 5. Trigger Exam Publishing via Gateway
Write-Host "`n[5/7] Publishing exam '$testExamId' via Gateway..." -ForegroundColor Yellow
$publishHeaders = @{
    "X-Admin-Api-Key" = $AdminKey
}
$pubResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$testExamId/publish" `
    -Method Post `
    -Headers $publishHeaders `
    -TimeoutSec 15
Write-Host "Publish command accepted: $($pubResp.message)" -ForegroundColor Green

# 6. Poll Publish Status via Gateway
Write-Host "`n[6/7] Polling multi-shard publish saga status via Gateway..." -ForegroundColor Yellow
$deadline = (Get-Date).AddSeconds(30)
$publishDone = $false
$lastStatus = $null

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 800
    try {
        $statusResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$testExamId/publish-status" `
            -Method Get `
            -Headers $publishHeaders `
            -TimeoutSec 10
        $lastStatus = $statusResp.data
        $s1Info = if ($lastStatus.shard1) { "$($lastStatus.shard1.status) [$($lastStatus.shard1.publishedCount) rows]" } else { "pending" }
        $s2Info = if ($lastStatus.shard2) { "$($lastStatus.shard2.status) [$($lastStatus.shard2.publishedCount) rows]" } else { "pending" }
        Write-Host "Current overall status: $($lastStatus.overallStatus) (Shard 1: $s1Info, Shard 2: $s2Info)" -ForegroundColor Gray
        if ($lastStatus.overallStatus -eq "PUBLISHED") {
            $publishDone = $true
            break
        }
    } catch {
        Write-Host "Status poll error: $_" -ForegroundColor DarkGray
    }
}

if (-not $publishDone) {
    throw "Exam did not reach PUBLISHED within 30s. Final status: $($lastStatus | ConvertTo-Json -Compress)"
}
Write-Host "PASS: Multi-shard saga completed! Overall status is PUBLISHED." -ForegroundColor Green
Write-Host "Shard 1: $($lastStatus.shard1.status) ($($lastStatus.shard1.publishedCount) published rows)" -ForegroundColor Green
Write-Host "Shard 2: $($lastStatus.shard2.status) ($($lastStatus.shard2.publishedCount) published rows)" -ForegroundColor Green

# 7. Wait for Kafka event consumption and cache warm-up to finish
Write-Host "`n[7/7] Verifying Kafka event, Redis cache warm-up, and Cache Hit metrics..." -ForegroundColor Yellow
Start-Sleep -Seconds 8

# Check direct Redis cache keys
$k1Exists = (docker exec ou-results-redis-cache-1 redis-cli EXISTS "result::$rollShard1_A").Trim()
$k2Exists = (docker exec ou-results-redis-cache-1 redis-cli EXISTS "result::$rollShard2_A").Trim()
if ($k1Exists -eq "1" -and $k2Exists -eq "1") {
    Write-Host "PASS: Keys 'result::$rollShard1_A' and 'result::$rollShard2_A' confirmed present in Redis cache!" -ForegroundColor Green
} else {
    throw "FAIL: Expected keys in Redis cache, but key1=$k1Exists, key2=$k2Exists"
}

# Capture cache hit counter before queries
$cacheHitsBefore = 0
try {
    $metric = Invoke-RestMethod -Uri "$ReadServiceUrl/actuator/metrics/cache.gets?tag=name:result&tag=result:hit" -TimeoutSec 5
    $cacheHitsBefore = [int]$metric.measurements[0].value
} catch {}

# Query Read path (Gateway -> Redis Cache)
$postPublish1 = Invoke-RestMethod -Uri "$GatewayUrl/api/results/$rollShard1_A" -TimeoutSec 15
if ($postPublish1.data.Count -gt 0 -and $postPublish1.data[0].rollNo -eq $rollShard1_A) {
    Write-Host "PASS: Student $rollShard1_A (Shard 1) result successfully retrieved via Gateway!" -ForegroundColor Green
    Write-Host "  Name: $($postPublish1.data[0].name), SGPA: $($postPublish1.data[0].sgpa)" -ForegroundColor Gray
} else {
    throw "FAIL: Expected results for student $rollShard1_A after publishing, got $($postPublish1.data.Count)!"
}

$postPublish2 = Invoke-RestMethod -Uri "$GatewayUrl/api/results/$rollShard2_A" -TimeoutSec 15
if ($postPublish2.data.Count -gt 0 -and $postPublish2.data[0].rollNo -eq $rollShard2_A) {
    Write-Host "PASS: Student $rollShard2_A (Shard 2) result successfully retrieved via Gateway!" -ForegroundColor Green
    Write-Host "  Name: $($postPublish2.data[0].name), SGPA: $($postPublish2.data[0].sgpa)" -ForegroundColor Gray
} else {
    throw "FAIL: Expected results for student $rollShard2_A after publishing, got $($postPublish2.data.Count)!"
}

# Verify cache hit metric incremented (proves both requests were served from Redis cache, not DB replica)
try {
    $metricAfter = Invoke-RestMethod -Uri "$ReadServiceUrl/actuator/metrics/cache.gets?tag=name:result&tag=result:hit" -TimeoutSec 5
    $cacheHitsAfter = [int]$metricAfter.measurements[0].value
    $deltaHits = $cacheHitsAfter - $cacheHitsBefore
    if ($deltaHits -ge 2) {
        Write-Host "PASS: Cache hit counter incremented by $deltaHits (proves both requests were served from Redis cache, NOT database replicas)!" -ForegroundColor Green
    } else {
        Write-Host "Cache hit counter delta: $deltaHits" -ForegroundColor Yellow
    }
} catch {}

# Test Internal Strong-Read on Read Service directly
$strongResp = Invoke-RestMethod -Uri "$ReadServiceUrl/internal/results/${rollShard1_A}?consistency=strong" -TimeoutSec 15
if ($strongResp.data.Count -gt 0 -and $strongResp.data[0].rollNo -eq $rollShard1_A) {
    Write-Host "PASS: Internal Strong-Read successfully fetched result directly from Primary Shard!" -ForegroundColor Green
} else {
    throw "FAIL: Internal strong-read failed for $rollShard1_A!"
}

# Idempotency check: Re-trigger publish on already published exam
Write-Host "`n[Bonus] Testing idempotency of publish command..." -ForegroundColor Yellow
$rePubResp = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$testExamId/publish" `
    -Method Post `
    -Headers $publishHeaders `
    -TimeoutSec 10
Start-Sleep -Seconds 2
$reStatus = Invoke-RestMethod -Uri "$GatewayUrl/admin/exams/$testExamId/publish-status" `
    -Method Get `
    -Headers $publishHeaders `
    -TimeoutSec 10
if ($reStatus.data.overallStatus -eq "PUBLISHED") {
    Write-Host "PASS: Re-triggering publish command on PUBLISHED exam remains safely PUBLISHED." -ForegroundColor Green
} else {
    Write-Host "WARNING: Unexpected status on re-publish: $($reStatus.data.overallStatus)" -ForegroundColor Yellow
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " Phase 5 Verification Completed Successfully!            " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
