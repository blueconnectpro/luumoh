param(
  [switch]$SkipDeploy,
  [switch]$SkipAnalyze
)

$ErrorActionPreference = 'Stop'

$qaArgs = @(
  '-RequireAndroidRelease',
  '-RequireIosRelease',
  '-RequireRealtime',
  '-RequireProductionMonnify',
  '-RequireFinance'
)

if ($SkipDeploy) {
  $qaArgs += '-SkipDeploy'
}

if (-not $SkipAnalyze) {
  $qaArgs += '-RunAnalyze'
}

Write-Host 'Running strict production final QA...'
& "$PSScriptRoot\run-full-prelaunch-qa.ps1" @qaArgs

Write-Host 'Exporting final operations report...'
& "$PSScriptRoot\export-admin-ops-report.ps1"

Write-Host 'Production final QA completed.'
