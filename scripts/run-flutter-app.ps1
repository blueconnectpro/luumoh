param(
  [ValidateSet("customer", "admin", "store", "rider")]
  [string]$App = "customer",
  [string]$Device = "chrome",
  [switch]$ResetAdb,
  [switch]$CleanInstall
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $repoRoot
try {
  & "$PSScriptRoot\sync-flutter-env.ps1"
} finally {
  Pop-Location
}

$appPath = switch ($App) {
  "customer" { "apps/customer_app" }
  "admin" { "apps/admin_dashboard" }
  "store" { "apps/store_app" }
  "rider" { "apps/rider_app" }
}

$packageName = switch ($App) {
  "customer" { "com.luumoh.customer" }
  "admin" { "" }
  "store" { "com.luumoh.store" }
  "rider" { "com.luumoh.rider" }
}

if ($App -eq "store") {
  $storeIdLine = Get-Content (Join-Path $repoRoot ".env") | Where-Object { $_ -match "^\s*STORE_ID\s*=" } | Select-Object -First 1
  $storeId = if ($storeIdLine) { ($storeIdLine -split "=", 2)[1].Trim().Trim('"').Trim("'") } else { "" }
  if (-not $storeId) {
    throw "STORE_ID is required in .env to run the store app without dart defines."
  }
}

$adb = Join-Path $env:LOCALAPPDATA "Android\sdk\platform-tools\adb.exe"
if (($ResetAdb -or $CleanInstall) -and (Test-Path $adb) -and $Device -ne "chrome") {
  Write-Host "Resetting ADB connection..."
  & $adb kill-server
  & $adb start-server
}

if ($CleanInstall -and $packageName -and (Test-Path $adb) -and $Device -ne "chrome") {
  Write-Host "Removing previous $App install ($packageName) from $Device if present..."
  & $adb -s $Device uninstall $packageName | Out-Host
}

Push-Location (Join-Path $repoRoot $appPath)
try {
  flutter run -d $Device --target lib/main.dart
} finally {
  Pop-Location
}
