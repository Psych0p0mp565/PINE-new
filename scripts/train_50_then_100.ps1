# Chain: fresh 50 epochs, then resume to 100 total (both with --no-export).
# Use when starting from scratch in one window: double-click or:
#   powershell -ExecutionPolicy Bypass -File scripts\train_50_then_100.ps1
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root
$Py = Join-Path $Root ".venv\Scripts\python.exe"
$Train = Join-Path $Root "scripts\retrain_yolo.py"

if (-not (Test-Path $Py)) { throw "Missing venv Python: $Py" }

Write-Host "`n=== Phase 1: epochs 1-50 (--no-export) ===" -ForegroundColor Cyan
& $Py $Train --epochs 50 --no-export
if ($LASTEXITCODE -ne 0) {
    Write-Host "Phase 1 failed (exit $LASTEXITCODE). Phase 2 not started." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`n=== Phase 2: resume to epoch 100 total (--no-export) ===" -ForegroundColor Cyan
& $Py $Train --resume --epochs 100 --no-export
if ($LASTEXITCODE -ne 0) {
    Write-Host "Phase 2 failed (exit $LASTEXITCODE)." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`n=== All training chunks finished ===" -ForegroundColor Green
Write-Host "Export TFLite when ready:" -ForegroundColor Green
Write-Host "  $Py $Train --export-only runs\retrain\mealybug_v2\weights\best.pt`n"
