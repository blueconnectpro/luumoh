param(
  [ValidateSet('customer', 'store', 'rider', 'admin')]
  [string]$App = 'customer',

  [int]$Port = 7358,

  [switch]$Build
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$apps = @{
  customer = 'apps/customer_app'
  store    = 'apps/store_app'
  rider    = 'apps/rider_app'
  admin    = 'apps/admin_dashboard'
}

if ($Build) {
  & (Join-Path $PSScriptRoot 'build-web-apps.ps1') -App $App
}

$buildDir = Join-Path $repoRoot (Join-Path $apps[$App] 'build/web')
if (!(Test-Path $buildDir)) {
  throw "No web build found at $buildDir. Run .\scripts\build-web-apps.ps1 -App $App first, or pass -Build."
}

$portInUse = Get-NetTCPConnection `
  -LocalPort $Port `
  -State Listen `
  -ErrorAction SilentlyContinue
if ($portInUse) {
  throw "Port $Port is already in use. Choose another port with -Port."
}

$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
  $python = Get-Command py -ErrorAction SilentlyContinue
}
if ($null -eq $python) {
  throw 'Python is required to serve built web apps. Install Python or use another static file server.'
}

$arguments = @('-m', 'http.server', "$Port", '--bind', '127.0.0.1', '--directory', $buildDir)
if ($python.Name -eq 'py.exe' -or $python.Name -eq 'py') {
  $arguments = @('-3') + $arguments
}

$process = Start-Process `
  -FilePath $python.Source `
  -ArgumentList $arguments `
  -WindowStyle Hidden `
  -PassThru

Write-Host "Serving $App at http://127.0.0.1:$Port"
Write-Host "Process id: $($process.Id)"
