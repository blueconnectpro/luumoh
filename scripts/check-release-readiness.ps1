$ErrorActionPreference = 'Stop'

function Read-DotEnv {
  param([string]$Path)

  $values = @{}
  if (!(Test-Path $Path)) {
    return $values
  }

  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith('#') -or !$line.Contains('=')) {
      return
    }

    $parts = $line.Split('=', 2)
    $values[$parts[0].Trim()] = $parts[1].Trim().Trim('"').Trim("'")
  }

  return $values
}

function Add-Result {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Level,
    [string]$Check,
    [string]$Message
  )

  $List.Add([pscustomobject]@{
    Level = $Level
    Check = $Check
    Message = $Message
  }) | Out-Null
}

$results = New-Object System.Collections.Generic.List[object]
$envValues = Read-DotEnv '.env'

foreach ($name in @(
  'SUPABASE_URL',
  'SUPABASE_PUBLISHABLE_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_PROJECT_REF',
  'SUPABASE_ACCESS_TOKEN',
  'MAPBOX_ACCESS_TOKEN',
  'MONNIFY_BASE_URL',
  'MONNIFY_API_KEY',
  'MONNIFY_SECRET_KEY',
  'MONNIFY_CONTRACT_CODE',
  'MONNIFY_REDIRECT_URL',
  'MONNIFY_APP_RETURN_URL'
)) {
  $value = [string]$envValues[$name]
  if (!$value -or $value -match '^your-|only-needed|from-dashboard|server-side-only') {
    Add-Result $results 'error' $name 'Required launch env value is missing or still a placeholder.'
  } else {
    Add-Result $results 'ok' $name 'Configured.'
  }
}

$supabaseUrl = [string]$envValues['SUPABASE_URL']
if ($supabaseUrl -and $supabaseUrl -notmatch '^https://[a-z0-9-]+\.supabase\.co/?$') {
  Add-Result $results 'error' 'SUPABASE_URL format' 'Expected a cloud Supabase URL like https://project-ref.supabase.co.'
}

$mapboxAccessToken = [string]$envValues['MAPBOX_ACCESS_TOKEN']
if ($mapboxAccessToken -match '^sk\.') {
  Add-Result $results 'error' 'MAPBOX_ACCESS_TOKEN type' 'Do not embed a secret Mapbox token in mobile apps. Use a public token that starts with pk.'
} elseif ($mapboxAccessToken -and $mapboxAccessToken -notmatch '^pk\.') {
  Add-Result $results 'warning' 'MAPBOX_ACCESS_TOKEN type' 'Expected a public Mapbox token that starts with pk.'
} elseif ($mapboxAccessToken) {
  Add-Result $results 'ok' 'MAPBOX_ACCESS_TOKEN type' 'Uses a public token format.'
}

$monnifyRedirectUrl = [string]$envValues['MONNIFY_REDIRECT_URL']
if ($monnifyRedirectUrl -and $monnifyRedirectUrl -notmatch '^https?://') {
  Add-Result $results 'warning' 'MONNIFY_REDIRECT_URL' 'Monnify requires HTTP(S). The Edge Function will fall back to the hosted return page.'
} elseif ($supabaseUrl -and $monnifyRedirectUrl) {
  $expectedRedirectUrl = "$($supabaseUrl.TrimEnd('/'))/functions/v1/monnify-return"
  if ($monnifyRedirectUrl.TrimEnd('/') -eq $expectedRedirectUrl) {
    Add-Result $results 'ok' 'MONNIFY_REDIRECT_URL route' 'Uses the hosted Supabase return page.'
  } else {
    Add-Result $results 'warning' 'MONNIFY_REDIRECT_URL route' "Expected $expectedRedirectUrl for the hosted checkout return page."
  }
}

$monnifyAppReturnUrl = [string]$envValues['MONNIFY_APP_RETURN_URL']
if ($monnifyAppReturnUrl -ne 'luumoh://payment-return') {
  Add-Result $results 'warning' 'MONNIFY_APP_RETURN_URL' 'Unexpected deep link. Confirm Android intent filters match it.'
} else {
  Add-Result $results 'ok' 'MONNIFY_APP_RETURN_URL' 'Matches the customer app payment return deep link.'
}

if (!(Test-Path 'packages/luumoh_core/lib/src/config/local_env.dart')) {
  Add-Result $results 'error' 'local_env.dart' 'Run .\scripts\sync-flutter-env.ps1 before app builds.'
} else {
  $localEnv = Get-Content 'packages/luumoh_core/lib/src/config/local_env.dart' -Raw
  if ($localEnv -notmatch [regex]::Escape($supabaseUrl.TrimEnd('/'))) {
    Add-Result $results 'warning' 'local_env.dart' 'Generated Flutter env does not appear to match SUPABASE_URL. Run .\scripts\sync-flutter-env.ps1.'
  } else {
    Add-Result $results 'ok' 'local_env.dart:SUPABASE_URL' 'Generated Flutter env matches SUPABASE_URL.'
  }

  if ($mapboxAccessToken -and $localEnv -notmatch [regex]::Escape($mapboxAccessToken)) {
    Add-Result $results 'warning' 'local_env.dart:MAPBOX_ACCESS_TOKEN' 'Generated Flutter env does not appear to match MAPBOX_ACCESS_TOKEN. Run .\scripts\sync-flutter-env.ps1.'
  } else {
    Add-Result $results 'ok' 'local_env.dart:MAPBOX_ACCESS_TOKEN' 'Generated Flutter env includes the Mapbox token.'
  }
}

foreach ($app in @('customer_app', 'store_app', 'rider_app')) {
  $manifest = "apps/$app/android/app/src/main/AndroidManifest.xml"
  if (!(Test-Path $manifest)) {
    Add-Result $results 'error' "$app manifest" 'Android manifest is missing.'
    continue
  }

  $content = Get-Content $manifest -Raw
  if ($content -notmatch 'android.permission.INTERNET') {
    Add-Result $results 'error' "$app INTERNET" 'INTERNET permission is missing.'
  } else {
    Add-Result $results 'ok' "$app INTERNET" 'Permission present.'
  }

  if ($content -notmatch 'android.permission.POST_NOTIFICATIONS') {
    Add-Result $results 'warning' "$app POST_NOTIFICATIONS" 'Android 13 notification permission is missing.'
  } else {
    Add-Result $results 'ok' "$app POST_NOTIFICATIONS" 'Permission present.'
  }

  foreach ($permission in @('ACCESS_COARSE_LOCATION', 'ACCESS_FINE_LOCATION')) {
    if ($content -notmatch "android.permission.$permission") {
      Add-Result $results 'error' "$app $permission" 'Location permission is missing.'
    } else {
      Add-Result $results 'ok' "$app $permission" 'Permission present.'
    }
  }

  if ($app -eq 'customer_app') {
    if ($content -match 'android:scheme="luumoh"' -and $content -match 'android:host="payment-return"') {
      Add-Result $results 'ok' "$app payment return deeplink" 'Registered luumoh://payment-return.'
    } else {
      Add-Result $results 'error' "$app payment return deeplink" 'Missing luumoh://payment-return intent filter.'
    }
  }

  if ($app -eq 'rider_app') {
    foreach ($scheme in @('mapbox', 'google.navigation', 'geo', 'tel', 'sms')) {
      if ($content -match "android:scheme=`"$([regex]::Escape($scheme))`"") {
        Add-Result $results 'ok' "$app query:$scheme" 'Registered package visibility query.'
      } else {
        Add-Result $results 'error' "$app query:$scheme" 'Missing package visibility query for navigation/contact launch.'
      }
    }
  }
}

foreach ($functionName in @(
  'monnify-initiate',
  'monnify-confirm',
  'monnify-webhook',
  'monnify-return',
  'admin-upsert-user'
)) {
  if (Test-Path "supabase/functions/$functionName/index.ts") {
    Add-Result $results 'ok' "function:$functionName" 'Source exists.'
  } else {
    Add-Result $results 'error' "function:$functionName" 'Edge Function source is missing.'
  }
}

foreach ($script in @(
  'check-cloud-health.ps1',
  'test-admin-onboarding.ps1',
  'test-support-flow.ps1',
  'test-order-placement.ps1',
  'test-operations-flow.ps1',
  'test-notifications-flow.ps1',
  'test-order-messages-flow.ps1',
  'test-monnify-checkout-init.ps1',
  'check-supabase-realtime-readiness.ps1',
  'check-android-release-readiness.ps1',
  'check-ios-release-readiness.ps1',
  'check-monnify-readiness.ps1',
  'check-security-rls.ps1',
  'check-finance-reconciliation.ps1',
  'export-admin-ops-report.ps1',
  'run-full-prelaunch-qa.ps1',
  'run-production-final-qa.ps1',
  'run-launch-smoke.ps1'
)) {
  if (Test-Path "scripts/$script") {
    Add-Result $results 'ok' "script:$script" 'Present.'
  } else {
    Add-Result $results 'error' "script:$script" 'Missing.'
  }
}

$results | Sort-Object Level, Check | Format-Table -AutoSize

$errorCount = @($results | Where-Object { $_.Level -eq 'error' }).Count
$warningCount = @($results | Where-Object { $_.Level -eq 'warning' }).Count

if ($errorCount -gt 0) {
  throw "$errorCount release readiness error(s) found. Fix errors before launch."
}

Write-Host "Release readiness checks passed with $warningCount warning(s)."
