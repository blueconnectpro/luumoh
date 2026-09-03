param(
  [switch]$AllowMissingExternal
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
  param(
    [string]$Level,
    [string]$Check,
    [string]$Message
  )

  $results.Add([pscustomobject]@{
    Level = $Level
    Check = $Check
    Message = $Message
  }) | Out-Null
}

function External-Level {
  if ($AllowMissingExternal) { return 'warning' }
  return 'error'
}

$apps = @(
  @{
    Name = 'customer'
    AppDir = 'customer_app'
    BundleId = 'com.luumoh.customer'
    DisplayName = 'Luumoh'
    RequiresUrlScheme = $true
  },
  @{
    Name = 'store'
    AppDir = 'store_app'
    BundleId = 'com.luumoh.store'
    DisplayName = 'Luumoh Store'
    RequiresUrlScheme = $false
  },
  @{
    Name = 'rider'
    AppDir = 'rider_app'
    BundleId = 'com.luumoh.rider'
    DisplayName = 'Luumoh Rider'
    RequiresUrlScheme = $false
  }
)

foreach ($app in $apps) {
  $appRoot = Join-Path $repoRoot "apps/$($app.AppDir)"
  $pubspecPath = Join-Path $appRoot 'pubspec.yaml'
  $plistPath = Join-Path $appRoot 'ios/Runner/Info.plist'
  $projectPath = Join-Path $appRoot 'ios/Runner.xcodeproj/project.pbxproj'

  if (!(Test-Path $pubspecPath)) {
    Add-Result 'error' "$($app.Name) pubspec" 'pubspec.yaml is missing.'
  } else {
    $pubspec = Get-Content $pubspecPath -Raw
    if ($pubspec -match '(?m)^version:\s*1\.0\.0\+1\s*$') {
      Add-Result 'ok' "$($app.Name) version" 'Uses launch version 1.0.0+1.'
    } else {
      Add-Result 'error' "$($app.Name) version" 'Expected version: 1.0.0+1 for first release.'
    }
  }

  if (!(Test-Path $plistPath)) {
    Add-Result 'error' "$($app.Name) Info.plist" 'Info.plist is missing.'
  } else {
    $plist = Get-Content $plistPath -Raw
    if ($plist -match '<key>CFBundleDisplayName</key>\s*<string>' + [regex]::Escape($app.DisplayName) + '</string>') {
      Add-Result 'ok' "$($app.Name) display name" "Uses $($app.DisplayName)."
    } else {
      Add-Result 'error' "$($app.Name) display name" "Expected $($app.DisplayName)."
    }
    if ($plist -match '<key>NSLocationWhenInUseUsageDescription</key>') {
      Add-Result 'ok' "$($app.Name) location usage" 'Location usage text is present.'
    } else {
      Add-Result 'error' "$($app.Name) location usage" 'Location usage text is missing.'
    }
    if ($app.RequiresUrlScheme) {
      if ($plist -match '<key>CFBundleURLTypes</key>' -and $plist -match '<string>luumoh</string>') {
        Add-Result 'ok' "$($app.Name) URL scheme" 'Registers luumoh:// deep links.'
      } else {
        Add-Result 'error' "$($app.Name) URL scheme" 'Expected luumoh:// URL scheme registration.'
      }
    }
  }

  if (!(Test-Path $projectPath)) {
    Add-Result 'error' "$($app.Name) Xcode project" 'project.pbxproj is missing.'
  } else {
    $project = Get-Content $projectPath -Raw
    if ($project -match 'com\.example') {
      Add-Result 'error' "$($app.Name) bundle id" 'Xcode project still contains com.example bundle IDs.'
    } elseif ($project -match [regex]::Escape("PRODUCT_BUNDLE_IDENTIFIER = $($app.BundleId);")) {
      Add-Result 'ok' "$($app.Name) bundle id" "Uses $($app.BundleId)."
    } else {
      Add-Result 'error' "$($app.Name) bundle id" "Expected $($app.BundleId)."
    }

    if ($project -match 'DEVELOPMENT_TEAM = [A-Z0-9]+;') {
      Add-Result 'ok' "$($app.Name) Apple team" 'Development team is configured.'
    } else {
      Add-Result (External-Level) "$($app.Name) Apple team" 'Set DEVELOPMENT_TEAM in Xcode before archiving for App Store.'
    }
  }
}

$results | Sort-Object Level, Check | Format-Table -AutoSize

$errorCount = @($results | Where-Object { $_.Level -eq 'error' }).Count
$warningCount = @($results | Where-Object { $_.Level -eq 'warning' }).Count

if ($errorCount -gt 0) {
  throw "$errorCount iOS release readiness error(s) found."
}

Write-Host "iOS release readiness checks passed with $warningCount warning(s)."
