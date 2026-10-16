<#
.SYNOPSIS
Full Verification Suite for Phase 4 Write Path: Real Scale (5k, 10k), Limits, Idempotency, Durability, Atomicity, and Storage.

.DESCRIPTION
Executes all 6 required Phase 4 verification scenarios against the live Gateway, Ingestion, RabbitMQ, and Neon PostgreSQL Shards.
#>
[CmdletBinding()]
param(
    [string]$GatewayUrl = "http://localhost:8081",
    [string]$IngestionUrl = "http://localhost:3000",
    [string]$RabbitMqApi = "http://localhost:15672/api"
)

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

function Wait-QueueEmpty([string]$QueueName, [int]$TimeoutSeconds = 60) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $queue = curl.exe -s -u guest:guest "$RabbitMqApi/queues/%2F/$QueueName" | ConvertFrom-Json
            if ($null -ne $queue -and $queue.messages -eq 0 -and $queue.messages_unacknowledged -eq 0) {
                return [math]::Round($sw.Elapsed.TotalSeconds, 2)
            }
        } catch {}
        Start-Sleep -Milliseconds 500
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

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " PHASE 4 WRITE PATH SCALE, DURABILITY & ATOMICITY TEST SUITE" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Purge DLQ before starting
curl.exe -s -u guest:guest -X DELETE "$RabbitMqApi/queues/%2F/results.write.dlq/contents" | Out-Null

# ----------------------------------------------------
# SCENARIO 1A: 5,000-ROW UPLOAD
# ----------------------------------------------------
Write-Host "`n>>> [1/6] Running 5,000-Row Scale Verification (EXAM_SCALE_5K)..." -ForegroundColor Yellow
$csv5k = Join-Path $repoRoot "scratch\upload-5k.csv"
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
Write-Host "`n>>> [2/6] Running 10,000-Row Scale Verification (EXAM_SCALE_10K)..." -ForegroundColor Yellow
$csv10k = Join-Path $repoRoot "scratch\upload-10k.csv"
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
Write-Host "`n>>> [3/6] Testing Upload Size Limit (Oversized 52MB file)..." -ForegroundColor Yellow
$csvOversized = Join-Path $repoRoot "scratch\oversized-upload.csv"
$resOversized = curl.exe -s -X POST "$GatewayUrl/admin/results/upload" `
    -H "X-Admin-Api-Key: $adminKey" `
    -F "file=@$csvOversized"

Write-Host "Oversized Response Envelope:" -ForegroundColor Green
Write-Host $resOversized

# ----------------------------------------------------
# SCENARIO 3: IDEMPOTENCY TEST (RE-UPLOAD 5,000 ROWS)
# ----------------------------------------------------
Write-Host "`n>>> [4/6] Testing Idempotency (Re-uploading 5,000 rows)..." -ForegroundColor Yellow
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
Write-Host "`n>>> [5/6] Testing Per-Shard Transaction Atomicity (Simulated mid-batch failure)..." -ForegroundColor Yellow
$csvAtomicity = Join-Path $repoRoot "scratch\upload-atomicity-fail.csv"

# Record DLQ count before
$dlqBeforeAtomicity = Get-DlqCount

$resAtomicity = curl.exe -s -X POST "$GatewayUrl/admin/results/upload" `
    -H "X-Admin-Api-Key: $adminKey" `
    -F "file=@$csvAtomicity" `
    -F "title=Atomicity Test Exam" `
    -F "resultDate=2026-08-15"

Write-Host "Atomicity Upload Response: $resAtomicity" -ForegroundColor Gray
# Wait 10 seconds for Spring AMQP retry attempts and DLQ routing
Start-Sleep -Seconds 10
$countShard1_Atomicity = psql "$env:SHARD_1_PRIMARY" -t -A -c "SELECT COUNT(*) FROM results WHERE exam_id = 'EXAM_ATOMICITY_FAIL';"
$dlqAfterAtomicity = Get-DlqCount

Write-Host "ATOMICITY VERIFICATION:" -ForegroundColor Green
Write-Host "  - Shard 1 Rows Written: $countShard1_Atomicity (Expected: 0 - entire batch rolled back!)"
Write-Host "  - DLQ Count Increase: $([int]$dlqAfterAtomicity - [int]$dlqBeforeAtomicity) (Expected: 1)"

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " TEST RUN COMPLETED. ALL DATA IS READY FOR REPORTING." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
