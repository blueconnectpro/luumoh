param(
  [ValidateSet('all', 'customer', 'store', 'rider', 'admin')]
  [string]$App = 'all'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$apps = [ordered]@{
  customer = 'apps/customer_app'
  store    = 'apps/store_app'
  rider    = 'apps/rider_app'
  admin    = 'apps/admin_dashboard'
}

$syncScript = Join-Path $PSScriptRoot 'sync-flutter-env.ps1'
if (Test-Path $syncScript) {
  & $syncScript
}

$selectedApps = if ($App -eq 'all') { $apps.Keys } else { @($App) }

foreach ($appKey in $selectedApps) {
  $appPath = Join-Path $repoRoot $apps[$appKey]
  Write-Host "Building $appKey web app at $appPath"
  Push-Location $appPath
  try {
    flutter build web --no-wasm-dry-run
  } finally {
    Pop-Location
  }
}

Write-Host 'Web build complete.'
