param(
  [switch]$RequireRealtime,
  [switch]$RequireProductionMonnify,
  [switch]$RequireAndroidRelease,
  [switch]$RequireIosRelease,
  [switch]$RequireFinance,
  [switch]$RunAnalyze,
  [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'

Write-Host '1/12 Syncing Flutter env...'
& "$PSScriptRoot\sync-flutter-env.ps1"

Write-Host '2/12 Checking release readiness...'
& "$PSScriptRoot\check-release-readiness.ps1"

Write-Host '3/12 Checking Android release readiness...'
if ($RequireAndroidRelease) {
  & "$PSScriptRoot\check-android-release-readiness.ps1"
} else {
  & "$PSScriptRoot\check-android-release-readiness.ps1" -AllowMissingExternal
}

Write-Host '4/12 Checking iOS release readiness...'
if ($RequireIosRelease) {
  & "$PSScriptRoot\check-ios-release-readiness.ps1"
} else {
  & "$PSScriptRoot\check-ios-release-readiness.ps1" -AllowMissingExternal
}

Write-Host '5/12 Checking Monnify readiness...'
if ($RequireProductionMonnify) {
  & "$PSScriptRoot\check-monnify-readiness.ps1" -RequireProduction
} else {
  & "$PSScriptRoot\check-monnify-readiness.ps1"
}

Write-Host '6/12 Checking Supabase Realtime readiness...'
if ($RequireRealtime) {
  & "$PSScriptRoot\check-supabase-realtime-readiness.ps1" -FailOnWarnings
} else {
  & "$PSScriptRoot\check-supabase-realtime-readiness.ps1"
}

Write-Host '7/12 Pushing database migrations...'
& "$PSScriptRoot\push-supabase-db.ps1"

if (-not $SkipDeploy) {
  Write-Host '8/12 Deploying Edge Functions...'
  & "$PSScriptRoot\deploy-supabase-functions.ps1"
} else {
  Write-Host '8/12 Skipping Edge Function deployment.'
}

Write-Host '9/12 Checking cloud health...'
& "$PSScriptRoot\check-cloud-health.ps1"

Write-Host '10/12 Running security/RLS audit...'
& "$PSScriptRoot\check-security-rls.ps1"

Write-Host '11/12 Running finance reconciliation...'
if ($RequireFinance) {
  & "$PSScriptRoot\check-finance-reconciliation.ps1" -FailOnIssues
} else {
  & "$PSScriptRoot\check-finance-reconciliation.ps1"
}

Write-Host '12/12 Running launch smoke flows...'
& "$PSScriptRoot\test-admin-onboarding.ps1"
& "$PSScriptRoot\test-order-placement.ps1"
& "$PSScriptRoot\test-monnify-checkout-init.ps1"
& "$PSScriptRoot\test-operations-flow.ps1"
& "$PSScriptRoot\test-support-flow.ps1"
& "$PSScriptRoot\test-notifications-flow.ps1"
& "$PSScriptRoot\test-order-messages-flow.ps1"

if ($RunAnalyze) {
  Write-Host 'Running Dart analyzer...'
  & 'C:\Users\FORTUNE\Development\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
} else {
  Write-Host 'Skipping Dart analyzer. Add -RunAnalyze once the local Dart CLI is healthy.'
}

Write-Host 'Full pre-launch QA completed.'
