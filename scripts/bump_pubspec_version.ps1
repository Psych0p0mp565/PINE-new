param(
    [string]$PubspecPath = "pubspec.yaml",
    [switch]$Minor,
    [switch]$Major
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $PubspecPath)) {
    throw "pubspec.yaml not found at: $PubspecPath"
}

$content = Get-Content -Path $PubspecPath -Raw
$match = [regex]::Match($content, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
if (-not $match.Success) {
    throw "Could not parse version from pubspec.yaml. Expected format: version: x.y.z+n"
}

$majorNum = [int]$match.Groups[1].Value
$minorNum = [int]$match.Groups[2].Value
$patchNum = [int]$match.Groups[3].Value
$buildNum = [int]$match.Groups[4].Value

if ($Major) {
    $majorNum += 1
    $minorNum = 0
    $patchNum = 0
} elseif ($Minor) {
    $minorNum += 1
    $patchNum = 0
} else {
    $patchNum += 1
}
$buildNum += 1

$newVersion = "$majorNum.$minorNum.$patchNum+$buildNum"
$updated = [regex]::Replace($content, '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$', "version: $newVersion", 1)
Set-Content -Path $PubspecPath -Value $updated -NoNewline

Write-Host "Updated pubspec version to $newVersion"
