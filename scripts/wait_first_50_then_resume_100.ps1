# While another window runs the first 50 epochs, wait until results.csv shows at least
# 50 epochs completed, no retrain_yolo Python process is running, then run resume to
# 100 total (--no-export). Safe if phase 1 is still in progress (waits for idle + CSV).
#
# Example:
#   powershell -ExecutionPolicy Bypass -File scripts\wait_first_50_then_resume_100.ps1
param(
    [int]$TotalEpochs = 100,
    [int]$FirstChunkEpochs = 50,
    [int]$PollSeconds = 60,
    [int]$MaxWaitHours = 48
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Py = Join-Path $Root ".venv\Scripts\python.exe"
$Train = Join-Path $Root "scripts\retrain_yolo.py"
$RunDir = Join-Path $Root "runs\retrain\mealybug_v2"
$Csv = Join-Path $RunDir "results.csv"
$LastPt = Join-Path $RunDir "weights\last.pt"

if (-not (Test-Path $Py)) { throw "Missing venv Python: $Py" }
Set-Location $Root

function Get-LastResultsEpoch {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return -1 }
    $line = Get-Content -Path $Path -Tail 1 -ErrorAction SilentlyContinue
    if (-not $line) { return -1 }
    if ($line -match '^\s*epoch\s*,') { return -1 }
    if ($line -match '^(\d+)') { return [int]$Matches[1] }
    return -1
}

function Get-RetrainPythonProcesses {
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and ($_.CommandLine -like '*retrain_yolo*') }
}

$deadline = (Get-Date).AddHours($MaxWaitHours)
Write-Host "Waiting until first chunk is done (CSV latest epoch >= $FirstChunkEpochs), training idle, then resume to $TotalEpochs."
Write-Host "CSV: $Csv | Poll: ${PollSeconds}s | Max wait: ${MaxWaitHours}h`n"

while ((Get-Date) -lt $deadline) {
    # retrain_yolo.py archives results.csv as results_epochs_1_to_N.csv when starting leg 2; if that exists,
    # do not fire chunk 2 again (second-leg results.csv only goes 1..50 so lastEp would look like chunk 1 again).
    if ((Get-ChildItem -Path $RunDir -Filter "results_epochs_1_to_*.csv" -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
        Write-Host "Found results_epochs_1_to_*.csv under mealybug_v2 — leg-2 continuation already started or finished. Exiting watcher."
        exit 0
    }

    $lastEp = Get-LastResultsEpoch -Path $Csv
    if ($lastEp -ge $TotalEpochs) {
        Write-Host "Latest epoch in CSV is $lastEp (already reached $TotalEpochs). Nothing to do."
        exit 0
    }

    $procs = @(Get-RetrainPythonProcesses)
    if ($lastEp -ge $FirstChunkEpochs -and $lastEp -lt $TotalEpochs -and $procs.Count -eq 0) {
        if (-not (Test-Path $LastPt)) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') Epoch $lastEp but last.pt missing; waiting ${PollSeconds}s..."
            Start-Sleep -Seconds $PollSeconds
            continue
        }
        Write-Host "$(Get-Date -Format 'HH:mm:ss') Chunk 1 done (CSV epoch $lastEp), no retrain process; debouncing 20s..."
        Start-Sleep -Seconds 20
        if ((Get-RetrainPythonProcesses).Count -gt 0) {
            Write-Host "Training started elsewhere; continuing to wait..."
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        Write-Host "`n=== Resume: target $TotalEpochs total epochs (--no-export) ===" -ForegroundColor Cyan
        & $Py $Train --resume --epochs $TotalEpochs --no-export
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            Write-Host "Resume run failed (exit $code)." -ForegroundColor Red
            exit $code
        }
        Write-Host "`n=== Done through $TotalEpochs epochs ===" -ForegroundColor Green
        Write-Host "Export TFLite when ready:" -ForegroundColor Green
        Write-Host "  $Py $Train --export-only runs\retrain\mealybug_v2\weights\best.pt`n"
        exit 0
    }

    $p = $procs.Count
    Write-Host "$(Get-Date -Format 'HH:mm:ss') CSV latest epoch: $lastEp | retrain_yolo Python process(es): $p"
    Start-Sleep -Seconds $PollSeconds
}

Write-Error "Timed out after $MaxWaitHours hours."
exit 1
