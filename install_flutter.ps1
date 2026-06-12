# ============================================================
#  Lebanon Gold Tracker - environment installer
#  Checks Git & Python, installs the latest stable Flutter SDK,
#  adds it to PATH, and prepares the gold_dashboard app (web).
#  Run via setup_environment.bat (double-click it).
# ============================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes downloads much faster

Write-Host ''
Write-Host '=== Lebanon Gold Tracker environment setup ===' -ForegroundColor Yellow

# ------------------------------------------------------------
# 1. Check tools that should already be installed
# ------------------------------------------------------------
Write-Host ''
Write-Host '[1/5] Checking existing tools...' -ForegroundColor Cyan

foreach ($tool in @('git', 'python')) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if ($cmd) {
        $version = & $tool --version 2>&1 | Select-Object -First 1
        Write-Host "  OK  $tool : $version"
    } else {
        Write-Host "  MISSING  $tool - install it from the official site:" -ForegroundColor Red
        if ($tool -eq 'git')    { Write-Host '           https://git-scm.com' }
        if ($tool -eq 'python') { Write-Host '           https://python.org (check "Add Python to PATH")' }
    }
}

# ------------------------------------------------------------
# 2. Install Flutter SDK (latest stable) if not present
# ------------------------------------------------------------
# Flutter must live in a path WITHOUT spaces - your user folder has spaces,
# so we use C:\dev\flutter (the officially recommended style of location).
$flutterRoot = 'C:\dev'
$flutterBin  = Join-Path $flutterRoot 'flutter\bin'

Write-Host ''
Write-Host '[2/5] Checking Flutter...' -ForegroundColor Cyan

$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterCmd) {
    Write-Host "  Flutter already installed: $($flutterCmd.Source)"
} elseif (Test-Path (Join-Path $flutterBin 'flutter.bat')) {
    Write-Host "  Flutter found at $flutterBin (will add to PATH below)."
} else {
    Write-Host '  Downloading the latest stable Flutter SDK (about 1 GB, please wait)...'

    # Ask Google for the current stable release for Windows
    $releases   = Invoke-RestMethod 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
    $stableHash = $releases.current_release.stable
    $entry      = $releases.releases | Where-Object { $_.hash -eq $stableHash } | Select-Object -First 1
    $zipUrl     = "$($releases.base_url)/$($entry.archive)"
    New-Item -ItemType Directory -Path $flutterRoot -Force | Out-Null
    $zipPath    = Join-Path $flutterRoot 'flutter_stable.zip'

    Write-Host "  Version: $($entry.version)"
    Write-Host "  From   : $zipUrl"
    # curl shows a live progress bar; -C - resumes a partial download if you
    # re-run this script after an interruption.
    curl.exe -L -C - --retry 5 --retry-delay 5 -o $zipPath $zipUrl
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed (curl exit code $LASTEXITCODE). Re-run this script to resume."
    }

    Write-Host "  Extracting to $flutterRoot ..."
    tar -xf $zipPath -C $flutterRoot          # built-in Windows tar handles zip
    Remove-Item $zipPath -Force
    Write-Host '  Flutter SDK extracted.' -ForegroundColor Green
}

# ------------------------------------------------------------
# 3. Add Flutter to the user PATH (permanent)
# ------------------------------------------------------------
Write-Host ''
Write-Host '[3/5] Updating PATH...' -ForegroundColor Cyan

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$flutterBin*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$flutterBin", 'User')
    Write-Host "  Added $flutterBin to your PATH (new terminals will see it)."
} else {
    Write-Host '  PATH already contains Flutter.'
}
$env:Path = "$env:Path;$flutterBin"           # also for THIS session

# ------------------------------------------------------------
# 4. Verify with flutter doctor
# ------------------------------------------------------------
Write-Host ''
Write-Host '[4/5] Running flutter doctor (first run takes a few minutes)...' -ForegroundColor Cyan
flutter doctor

# ------------------------------------------------------------
# 5. Prepare the dashboard app (web platform)
# ------------------------------------------------------------
Write-Host ''
Write-Host '[5/5] Preparing gold_dashboard...' -ForegroundColor Cyan
$dashboard = Join-Path $PSScriptRoot 'gold_dashboard'
Set-Location $dashboard
flutter create . --platforms web
flutter pub get

Write-Host ''
Write-Host '=== Done! ===' -ForegroundColor Green
Write-Host 'Run the dashboard with:'
Write-Host "  cd `"$dashboard`""
Write-Host '  flutter run -d chrome'
Write-Host ''
Write-Host 'Optional (for Android phone builds): install Android Studio from'
Write-Host 'https://developer.android.com/studio then re-run "flutter doctor".'
