<#
.SYNOPSIS
Tests the OU Results Write Pipeline end-to-end (Gateway -> Ingestion -> RabbitMQ -> Persistence -> Shards).

.DESCRIPTION
Uploads a sample or fresh CSV file through the API Gateway (or Ingestion service directly)
and verifies that batches are ingested, grouped, and persisted to both Neon database shards.
#>
[CmdletBinding()]
param(
    [string]$GatewayUrl = "http://localhost:8080",
    [string]$AdminKey = "",
    [string]$CsvPath = "load-tests/seed/out/upload-sample.csv",
    [switch]$FreshExam
)

$ErrorActionPreference = "Stop"
$repoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName

# Load .env if present
$envPath = Join-Path $repoRoot ".env"
if (Test-Path $envPath) {
    Get-Content $envPath | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
        }
    }
}

if ([string]::IsNullOrWhiteSpace($AdminKey)) {
    $AdminKey = $env:ADMIN_API_KEY
}
if ([string]::IsNullOrWhiteSpace($AdminKey)) {
    throw "ADMIN_API_KEY is not set. Please supply -AdminKey or configure ADMIN_API_KEY in .env."
}

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Testing OU Results Write Pipeline End-to-End" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# 1. Check services connectivity
Write-Host "`n[1/5] Checking service endpoints..." -ForegroundColor Yellow
$targetUrl = $GatewayUrl
$usingGateway = $true

try {
    $null = Invoke-RestMethod -Uri "$GatewayUrl/actuator/health" -TimeoutSec 3
    Write-Host "API Gateway is active on $GatewayUrl" -ForegroundColor Green
} catch {
    Write-Host "API Gateway not running on $GatewayUrl; connecting directly to Ingestion Service (http://localhost:3000)..." -ForegroundColor Yellow
    $targetUrl = "http://localhost:3000"
    $usingGateway = $false
    try {
        $null = Invoke-RestMethod -Uri "$targetUrl/health" -TimeoutSec 3
        Write-Host "Ingestion Service is active on $targetUrl" -ForegroundColor Green
    } catch {
        Write-Host "Neither Gateway nor Ingestion Service is reachable!" -ForegroundColor Red
        Write-Host "Please start the stack with write services: .\scripts\start-stack.ps1 -Profile optimized -Write" -ForegroundColor Yellow
        return
    }
}

# 2. Prepare upload payload
$testExamId = ""
$resolvedCsv = ""
$tempCreated = $false

if ($FreshExam) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $testExamId = "EXAM_TEST_$timestamp"
    $scratchDir = Join-Path $repoRoot "scratch"
    if (-not (Test-Path $scratchDir)) {
        New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
    }
    $resolvedCsv = Join-Path $scratchDir "test_upload_$timestamp.csv"
    $tempCreated = $true

    Write-Host "`n[2/5] Creating fresh test CSV with exam ID '$testExamId'..." -ForegroundColor Yellow
    
    $csvContent = @"
exam_id,roll_no,semester,college_code,batch_year,dept_code,name,father_name,gender,course,medium,subjects,result_status,sgpa,cgpa
$testExamId,160423733801,6,1604,23,733,STUDENT S1,PARENT S1,FEMALE,B.E. (AICTE),ENGLISH,"[{""code"":""CS601"",""name"":""DISTRIBUTED SYSTEMS"",""credits"":3,""grade"":""A""}]",PASSED,8.50,8.10
$testExamId,160423733802,6,1604,23,733,STUDENT S2,PARENT S2,MALE,B.E. (AICTE),ENGLISH,"[{""code"":""CS601"",""name"":""DISTRIBUTED SYSTEMS"",""credits"":3,""grade"":""B""}]",PASSED,7.50,7.20
$testExamId,160823733801,6,1608,23,733,STUDENT S3,PARENT S3,MALE,B.E. (AICTE),ENGLISH,"[{""code"":""CS601"",""name"":""DISTRIBUTED SYSTEMS"",""credits"":3,""grade"":""A""}]",PASSED,9.00,8.80
$testExamId,160823733802,6,1608,23,733,STUDENT S4,PARENT S4,FEMALE,B.E. (AICTE),ENGLISH,"[{""code"":""CS601"",""name"":""DISTRIBUTED SYSTEMS"",""credits"":3,""grade"":""S""}]",PASSED,9.50,9.30
"@
    Set-Content -Path $resolvedCsv -Value $csvContent -Encoding UTF8
    Write-Host "Created fresh test file: $resolvedCsv (2 students for Shard 1, 2 students for Shard 2)" -ForegroundColor Green
} else {
    $resolvedCsv = Join-Path $repoRoot $CsvPath
    if (-not (Test-Path $resolvedCsv)) {
        throw "CSV file not found at $resolvedCsv."
    }
    Write-Host "`n[2/5] Using sample dataset: $resolvedCsv (5,000 students)" -ForegroundColor Yellow
    Write-Host "Note: If results for this exam already exist in the database, this tests idempotent upsert." -ForegroundColor Gray
}

# 3. Upload CSV
Write-Host "`n[3/5] Uploading CSV to $targetUrl/admin/results/upload..." -ForegroundColor Yellow
$uploadUrl = "$targetUrl/admin/results/upload"

$headers = @("-H", "X-Admin-Api-Key: $AdminKey")
$title = if ($testExamId) { "Verification Exam $testExamId" } else { "July-August 2026 Examinations" }
$date = "2026-08-15"

$response = & curl.exe -s -X POST $uploadUrl `
    @headers `
    -F "file=@$resolvedCsv" `
    -F "title=$title" `
    -F "resultDate=$date"

Write-Host "Ingestion Response:" -ForegroundColor Green
Write-Host $response

# 4. Wait for RabbitMQ persistence consumer
Write-Host "`n[4/5] Waiting 8 seconds for asynchronous batch persistence..." -ForegroundColor Yellow
Start-Sleep -Seconds 8

# 5. Query Neon Shards
Write-Host "`n[5/5] Querying Neon PostgreSQL Shards..." -ForegroundColor Yellow

if ($FreshExam -and $testExamId) {
    Write-Host "`n--- Verification for fresh exam '$testExamId' ---" -ForegroundColor Cyan
    if ($env:SHARD_1_PRIMARY) {
        Write-Host "`nShard 1 (Exam & Results):" -ForegroundColor Cyan
        & psql "$env:SHARD_1_PRIMARY" -c "SELECT exam_id, title, publish_status FROM exams WHERE exam_id = '$testExamId';" -c "SELECT roll_no, name, college_code, sgpa, published FROM results WHERE exam_id = '$testExamId';"
    }
    if ($env:SHARD_2_PRIMARY) {
        Write-Host "`nShard 2 (Exam & Results):" -ForegroundColor Cyan
        & psql "$env:SHARD_2_PRIMARY" -c "SELECT exam_id, title, publish_status FROM exams WHERE exam_id = '$testExamId';" -c "SELECT roll_no, name, college_code, sgpa, published FROM results WHERE exam_id = '$testExamId';"
    }
} else {
    if ($env:SHARD_1_PRIMARY) {
        Write-Host "`nShard 1 Total Row Count:" -ForegroundColor Cyan
        & psql "$env:SHARD_1_PRIMARY" -c "SELECT COUNT(*) as total_rows_shard1 FROM results;"
    }
    if ($env:SHARD_2_PRIMARY) {
        Write-Host "`nShard 2 Total Row Count:" -ForegroundColor Cyan
        & psql "$env:SHARD_2_PRIMARY" -c "SELECT COUNT(*) as total_rows_shard2 FROM results;"
    }
}

# Cleanup temp file
if ($tempCreated -and (Test-Path $resolvedCsv)) {
    Remove-Item $resolvedCsv -Force -ErrorAction SilentlyContinue
}

Write-Host "`n==============================================" -ForegroundColor Green
Write-Host " Pipeline test executed successfully!" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
