param(
    [Parameter(Mandatory = $true)]
    [string]$SupabaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$SupabaseAnonKey,

    [ValidateSet("apk", "aab")]
    [string]$Target = "apk",

    [switch]$SplitPerAbi,
    [switch]$Minor,
    [switch]$Major,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    if ($Clean) {
        flutter clean
    }

    if ($Major) {
        & "$PSScriptRoot\bump_pubspec_version.ps1" -PubspecPath "pubspec.yaml" -Major
    }
    elseif ($Minor) {
        & "$PSScriptRoot\bump_pubspec_version.ps1" -PubspecPath "pubspec.yaml" -Minor
    }
    else {
        & "$PSScriptRoot\bump_pubspec_version.ps1" -PubspecPath "pubspec.yaml"
    }

    flutter pub get

    if ($Target -eq "apk") {
        $args = @("build", "apk", "--release")
        if ($SplitPerAbi) {
            $args += "--split-per-abi"
        }
        $args += "--dart-define=SUPABASE_URL=$SupabaseUrl"
        $args += "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey"
        flutter @args
    } else {
        flutter build appbundle --release `
            --dart-define=SUPABASE_URL=$SupabaseUrl `
            --dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey
    }

    Write-Host ""
    Write-Host "Build complete."
    Write-Host "Tip: commit pubspec.yaml so version history stays consistent."
}
finally {
    Pop-Location
}
