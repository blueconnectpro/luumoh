param(
  [switch]$SkipDeploy,
  [switch]$SkipFlowTests,
  [switch]$SkipDbPush,
  [switch]$RunAnalyze
)

$ErrorActionPreference = "Stop"

Write-Host "Syncing local Flutter env..."
& "$PSScriptRoot\sync-flutter-env.ps1"

Write-Host "Checking release readiness..."
& "$PSScriptRoot\check-release-readiness.ps1"

Write-Host "Checking Android release readiness..."
& "$PSScriptRoot\check-android-release-readiness.ps1" -AllowMissingExternal

Write-Host "Checking iOS release readiness..."
& "$PSScriptRoot\check-ios-release-readiness.ps1" -AllowMissingExternal

Write-Host "Checking Monnify readiness..."
& "$PSScriptRoot\check-monnify-readiness.ps1"

if (-not $SkipDbPush) {
  Write-Host "Pushing database migrations..."
  & "$PSScriptRoot\push-supabase-db.ps1"
} else {
  Write-Host "Skipping database migration push."
}

if (-not $SkipDeploy) {
  Write-Host "Deploying Supabase Edge Functions..."
  & "$PSScriptRoot\deploy-supabase-functions.ps1"
} else {
  Write-Host "Skipping Edge Function deployment."
}

Write-Host "Checking cloud health..."
& "$PSScriptRoot\check-cloud-health.ps1"

Write-Host "Checking Supabase realtime readiness..."
& "$PSScriptRoot\check-supabase-realtime-readiness.ps1" -FailOnWarnings

Write-Host "Running security/RLS audit..."
& "$PSScriptRoot\check-security-rls.ps1" -FailOnWarnings

Write-Host "Running finance reconciliation..."
& "$PSScriptRoot\check-finance-reconciliation.ps1" -FailOnIssues -FailOnWarnings

Write-Host "Testing admin onboarding..."
& "$PSScriptRoot\test-admin-onboarding.ps1"

if (-not $SkipFlowTests) {
  Write-Host "Testing customer order placement..."
  & "$PSScriptRoot\test-order-placement.ps1"

  Write-Host "Testing Monnify checkout initialization..."
  & "$PSScriptRoot\test-monnify-checkout-init.ps1"

  Write-Host "Testing paid operations flow..."
  & "$PSScriptRoot\test-operations-flow.ps1"

  Write-Host "Testing customer support issue flow..."
  & "$PSScriptRoot\test-support-flow.ps1"

  Write-Host "Testing Supabase realtime notifications..."
  & "$PSScriptRoot\test-notifications-flow.ps1"

  Write-Host "Testing Supabase realtime order messages..."
  & "$PSScriptRoot\test-order-messages-flow.ps1"
}

if ($RunAnalyze) {
  Write-Host "Running Dart analyzer..."
  & "C:\Users\FORTUNE\Development\flutter\bin\cache\dart-sdk\bin\dart.exe" analyze
} else {
  Write-Host "Skipping Dart analyzer. Run with -RunAnalyze after the local Dart CLI hang is resolved."
}

Write-Host "Launch smoke checks passed."
