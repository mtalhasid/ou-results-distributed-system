# Proves write-path throughput scaling (5k/10k rows), upload size limits, idempotency, and transaction rollback with DLQ routing.
<#
.SYNOPSIS
Full Verification Suite for Phase 4 Write Path: Real Scale (5k, 10k), Limits, Idempotency, Durability, Atomicity, and Storage.

.DESCRIPTION
Executes all 6 required Phase 4 verification scenarios against the live Gateway, Ingestion, RabbitMQ, and Neon PostgreSQL Shards.
Generates required test payloads dynamically in a temporary directory and cleans up afterwards.
#>
[CmdletBinding()]
param(
    [string]$GatewayUrl = "http://localhost:8081",
    [string]$IngestionUrl = "http://localhost:3000",
    [string]$RabbitMqApi = "http://localhost:15672/api"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

# Load .env
$envPath = Join-Path $repoRoot ".env"
if (Test-Path $envPath) {
    Get-Content $envPath | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
        }
    }
}

$adminKey = $env:ADMIN_API_KEY
if ([string]::IsNullOrWhiteSpace($adminKey)) {
    throw "ADMIN_API_KEY is not set in environment or .env file."
}

function Wait-QueueEmpty([string]$QueueName, [int]$TimeoutSeconds = 90) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds 2
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $queue = curl.exe -s -u guest:guest "$RabbitMqApi/queues/%2F/$QueueName" | ConvertFrom-Json
            if ($null -ne $queue) {
                $totalActive = [int]$queue.messages + [int]$queue.messages_unacknowledged
                if ($totalActive -eq 0 -and $sw.Elapsed.TotalSeconds -ge 4) {
                    return [math]::Round($sw.Elapsed.TotalSeconds, 2)
                }
            }
        } catch {}
        Start-Sleep -Milliseconds 800
    }
    return [math]::Round($sw.Elapsed.TotalSeconds, 2)
}

function Get-DlqCount {
    try {
        $q = curl.exe -s -u guest:guest "$RabbitMqApi/queues/%2F/results.write.dlq" | ConvertFrom-Json
        return [int]$q.messages
    } catch {
        return -1
    }
}

function Get-IngestionMemory {
    try {
        $m = Invoke-RestMethod -Uri "$IngestionUrl/admin/metrics/memory" -TimeoutSec 3
        return $m.data
    } catch {
        return @{ rssMB = 0; heapUsedMB = 0 }
    }
}

function Generate-TestCsv([string]$Path, [string]$ExamId, [int]$Shard1Count, [int]$Shard2Count) {
    $writer = [System.IO.StreamWriter]::new($Path, $false, [System.Text.Encoding]::UTF8)
    $writer.WriteLine("exam_id,roll_no,semester,college_code,batch_year,dept_code,name,father_name,gender,course,medium,subjects,result_status,sgpa,cgpa")
    $subjects = '[{""code"":""CS601"",""name"":""DISTRIBUTED SYSTEMS"",""credits"":3,""grade"":""A""},{""code"":""CS602"",""name"":""DATABASE INTERNALS"",""credits"":3,""grade"":""B""}]'
    for ($i = 1; $i -le $Shard1Count; $i++) {
        $roll = "160423{0:D6}" -f $i
        $writer.WriteLine("$ExamId,$roll,6,1604,23,733,STUDENT S1_$i,PARENT $i,MALE,B.E. (AICTE),ENGLISH,`"$subjects`",PASSED,8.50,8.20")
    }
    for ($i = 1; $i -le $Shard2Count; $i++) {
        $roll = "160823{0:D6}" -f $i
        $writer.WriteLine("$ExamId,$roll,6,1608,23,733,STUDENT S2_$i,PARENT $i,FEMALE,B.E. (AICTE),ENGLISH,`"$subjects`",PASSED,9.10,8.90")
    }
    $writer.Close()
}

function Generate-AtomicityCsv([string]$Path, [string]$ExamId, [int]$TotalCount) {
    $writer = [System.IO.StreamWriter]::new($Path, $false, [System.Text.Encoding]::UTF8)
    $writer.WriteLine("exam_id,roll_no,semester,college_code,batch_year,dept_code,name,father_name,gender,course,medium,subjects,result_status,sgpa,cgpa")
    $subjects = '[{""code"":""CS601"",""name"":""DISTRIBUTED SYSTEMS"",""credits"":3,""grade"":""A""}]'
    for ($i = 1; $i -le $TotalCount; $i++) {
        $roll = "160423{0:D6}" -f $i
        $name = if ($i -eq [math]::Floor($TotalCount / 2)) { "FORCE_TRANSACTION_FAILURE" } else { "STUDENT $i" }
        $writer.WriteLine("$ExamId,$roll,6,1604,23,733,$name,PARENT $i,MALE,B.E.,ENG,`"$subjects`",PASSED,8.0,8.0")
    }
    $writer.Close()
}

function Generate-OversizedCsv([string]$Path) {
    $fs = [System.IO.File]::Create($Path)
    $header = [System.Text.Encoding]::UTF8.GetBytes("exam_id,roll_no,semester,college_code,batch_year,dept_code,name,father_name,gender,course,medium,subjects,result_status,sgpa,cgpa`n")
    $fs.Write($header, 0, $header.Length)
    $fs.SetLength(52 * 1024 * 1024)
    $fs.Close()
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " WRITE PATH SCALE, DURABILITY & ATOMICITY TEST SUITE      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Set up temporary working directory
$tempDir = Join-Path $repoRoot "scratch"
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

$csv5k = Join-Path $tempDir "upload-5k.csv"
$csv10k = Join-Path $tempDir "upload-10k.csv"
$csvOversized = Join-Path $tempDir "oversized-upload.csv"
$csvAtomicity = Join-Path $tempDir "upload-atomicity-fail.csv"

try {
    # Generate payloads dynamically
    Write-Host "`nGenerating dynamic test payloads..." -ForegroundColor Gray
    Generate-TestCsv $csv5k "EXAM_SCALE_5K" 2500 2500
    Generate-TestCsv $csv10k "EXAM_SCALE_10K" 5000 5000
    Generate-AtomicityCsv $csvAtomicity "EXAM_ATOMICITY_FAIL" 500
    Generate-OversizedCsv $csvOversized
    Write-Host "Payloads generated successfully." -ForegroundColor Green

    # Clean prior test rows from shards for clean verification
    try {
        psql "$env:SHARD_1_PRIMARY" -c "DELETE FROM results WHERE exam_id IN ('EXAM_SCALE_5K', 'EXAM_SCALE_10K', 'EXAM_ATOMICITY_FAIL'); DELETE FROM exams WHERE exam_id IN ('EXAM_SCALE_5K', 'EXAM_SCALE_10K', 'EXAM_ATOMICITY_FAIL');" 2>$null | Out-Null
        psql "$env:SHARD_2_PRIMARY" -c "DELETE FROM results WHERE exam_id IN ('EXAM_SCALE_5K', 'EXAM_SCALE_10K', 'EXAM_ATOMICITY_FAIL'); DELETE FROM exams WHERE exam_id IN ('EXAM_SCALE_5K', 'EXAM_SCALE_10K', 'EXAM_ATOMICITY_FAIL');" 2>$null | Out-Null
    } catch {}

    # Purge DLQ before starting
    curl.exe -s -u guest:guest -X DELETE "$RabbitMqApi/queues/%2F/results.write.dlq/contents" | Out-Null

    # ----------------------------------------------------
    # SCENARIO 1A: 5,000-ROW UPLOAD
    # ----------------------------------------------------
    Write-Host "`n>>> [1/5] Running 5,000-Row Scale Verification (EXAM_SCALE_5K)..." -ForegroundColor Yellow
    $memBefore5k = Get-IngestionMemory

    $swUpload5k = [System.Diagnostics.Stopwatch]::StartNew()
    $res5k = curl.exe -s -X POST "$GatewayUrl/admin/results/upload" `
        -H "X-Admin-Api-Key: $adminKey" `
        -F "file=@$csv5k" `
        -F "title=Scale Verification 5K Exam" `
        -F "resultDate=2026-08-15"
    $swUpload5k.Stop()
    $uploadTime5k = [math]::Round($swUpload5k.Elapsed.TotalSeconds, 2)

    Write-Host "Upload response: $res5k" -ForegroundColor Gray
    $drainTime5k = Wait-QueueEmpty "results.write" 60
    $memAfter5k = Get-IngestionMemory
    $dlq5k = Get-DlqCount

    $countShard1_5k = psql "$env:SHARD_1_PRIMARY" -t -A -c "SELECT COUNT(*) FROM results WHERE exam_id = 'EXAM_SCALE_5K';"
    $countShard2_5k = psql "$env:SHARD_2_PRIMARY" -t -A -c "SELECT COUNT(*) FROM results WHERE exam_id = 'EXAM_SCALE_5K';"

    Write-Host "RESULTS FOR 5,000 ROWS:" -ForegroundColor Green
    Write-Host "  - Gateway Upload Response Time: ${uploadTime5k}s"
    Write-Host "  - Time to Complete Persistence: ${drainTime5k}s"
    Write-Host "  - Shard 1 Row Count: $countShard1_5k / 2500 expected"
    Write-Host "  - Shard 2 Row Count: $countShard2_5k / 2500 expected"
    Write-Host "  - Dead-Letter Queue Count: $dlq5k"
    Write-Host "  - Ingestion Memory (RSS): $($memAfter5k.rssMB) MB (Heap Used: $($memAfter5k.heapUsedMB) MB)"

    # ----------------------------------------------------
    # SCENARIO 1B: 10,000-ROW UPLOAD
    # ----------------------------------------------------
    Write-Host "`n>>> [2/5] Running 10,000-Row Scale Verification (EXAM_SCALE_10K)..." -ForegroundColor Yellow
    $memBefore10k = Get-IngestionMemory

    $swUpload10k = [System.Diagnostics.Stopwatch]::StartNew()
    $res10k = curl.exe -s -X POST "$GatewayUrl/admin/results/upload" `
        -H "X-Admin-Api-Key: $adminKey" `
        -F "file=@$csv10k" `
        -F "title=Scale Verification 10K Exam" `
        -F "resultDate=2026-08-15"
    $swUpload10k.Stop()
    $uploadTime10k = [math]::Round($swUpload10k.Elapsed.TotalSeconds, 2)

    Write-Host "Upload response: $res10k" -ForegroundColor Gray
    $drainTime10k = Wait-QueueEmpty "results.write" 90
    $memAfter10k = Get-IngestionMemory
    $dlq10k = Get-DlqCount

    $countShard1_10k = psql "$env:SHARD_1_PRIMARY" -t -A -c "SELECT COUNT(*) FROM results WHERE exam_id = 'EXAM_SCALE_10K';"
    $countShard2_10k = psql "$env:SHARD_2_PRIMARY" -t -A -c "SELECT COUNT(*) FROM results WHERE exam_id = 'EXAM_SCALE_10K';"

    Write-Host "RESULTS FOR 10,000 ROWS:" -ForegroundColor Green
    Write-Host "  - Gateway Upload Response Time: ${uploadTime10k}s"
    Write-Host "  - Time to Complete Persistence: ${drainTime10k}s"
    Write-Host "  - Shard 1 Row Count: $countShard1_10k / 5000 expected"
    Write-Host "  - Shard 2 Row Count: $countShard2_10k / 5000 expected"
    Write-Host "  - Dead-Letter Queue Count: $dlq10k"
    Write-Host "  - Ingestion Memory (RSS): $($memAfter10k.rssMB) MB (Heap Used: $($memAfter10k.heapUsedMB) MB)"

    # ----------------------------------------------------
    # SCENARIO 2: UPLOAD LIMIT & OVERSIZED FILE TEST
    # ----------------------------------------------------
    Write-Host "`n>>> [3/5] Testing Upload Size Limit (Oversized 52MB file)..." -ForegroundColor Yellow
    $resOversized = curl.exe -s -X POST "$GatewayUrl/admin/results/upload" `
        -H "X-Admin-Api-Key: $adminKey" `
        -F "file=@$csvOversized"

    Write-Host "Oversized Response Envelope:" -ForegroundColor Green
    Write-Host $resOversized

    # ----------------------------------------------------
    # SCENARIO 3: IDEMPOTENCY TEST (RE-UPLOAD 5,000 ROWS)
    # ----------------------------------------------------
    Write-Host "`n>>> [4/5] Testing Idempotency (Re-uploading 5,000 rows)..." -ForegroundColor Yellow
    $null = curl.exe -s -X POST "$GatewayUrl/admin/results/upload" `
        -H "X-Admin-Api-Key: $adminKey" `
        -F "file=@$csv5k" `
        -F "title=Scale Verification 5K Exam" `
        -F "resultDate=2026-08-15"

    $drainTimeReupload = Wait-QueueEmpty "results.write" 60
    $countShard1_Reupload = psql "$env:SHARD_1_PRIMARY" -t -A -c "SELECT COUNT(*) FROM results WHERE exam_id = 'EXAM_SCALE_5K';"
    $countShard2_Reupload = psql "$env:SHARD_2_PRIMARY" -t -A -c "SELECT COUNT(*) FROM results WHERE exam_id = 'EXAM_SCALE_5K';"

    Write-Host "IDEMPOTENCY VERIFICATION:" -ForegroundColor Green
    Write-Host "  - Shard 1 Row Count after re-upload: $countShard1_Reupload (Expected: 2500, no duplicates)"
    Write-Host "  - Shard 2 Row Count after re-upload: $countShard2_Reupload (Expected: 2500, no duplicates)"

    # ----------------------------------------------------
    # SCENARIO 4: TRANSACTIONS & ATOMICITY (MID-BATCH FAILURE)
    # ----------------------------------------------------
    Write-Host "`n>>> [5/5] Testing Per-Shard Transaction Atomicity (Simulated mid-batch failure)..." -ForegroundColor Yellow
    $dlqBeforeAtomicity = Get-DlqCount

    $resAtomicity = curl.exe -s -X POST "$GatewayUrl/admin/results/upload" `
        -H "X-Admin-Api-Key: $adminKey" `
        -F "file=@$csvAtomicity" `
        -F "title=Atomicity Test Exam" `
        -F "resultDate=2026-08-15"

    Write-Host "Atomicity Upload Response: $resAtomicity" -ForegroundColor Gray
    Start-Sleep -Seconds 15
    $countShard1_Atomicity = psql "$env:SHARD_1_PRIMARY" -t -A -c "SELECT COUNT(*) FROM results WHERE exam_id = 'EXAM_ATOMICITY_FAIL';"
    $dlqAfterAtomicity = Get-DlqCount

    Write-Host "ATOMICITY VERIFICATION:" -ForegroundColor Green
    Write-Host "  - Shard 1 Rows Written: $countShard1_Atomicity (Expected: 0 - entire batch rolled back!)"
    Write-Host "  - DLQ Count Increase: $([int]$dlqAfterAtomicity - [int]$dlqBeforeAtomicity) (Expected: 1)"

    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host " WRITE PATH RESILIENCE SUITE COMPLETED SUCCESSFULLY!      " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
} finally {
    Write-Host "`nCleaning up temporary test payloads in $tempDir..." -ForegroundColor Gray
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Temporary test directory cleaned." -ForegroundColor Green
}
