param(
  [string]$Device = "emulator-5554",
  [switch]$ResetAdb,
  [switch]$CleanInstall
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")

& (Join-Path $repoRoot "scripts\run-flutter-app.ps1") `
  -App rider `
  -Device $Device `
  -ResetAdb:$ResetAdb `
  -CleanInstall:$CleanInstall
