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

function Read-PropertiesFile {
  param([string]$Path)

  $values = @{}
  if (!(Test-Path $Path)) { return $values }

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

$apps = @(
  @{
    Name = 'customer'
    AppDir = 'customer_app'
    Package = 'com.luumoh.customer'
    Label = 'Luumoh'
    MainActivity = 'apps/customer_app/android/app/src/main/kotlin/com/luumoh/customer/MainActivity.kt'
  },
  @{
    Name = 'store'
    AppDir = 'store_app'
    Package = 'com.luumoh.store'
    Label = 'Luumoh Store'
    MainActivity = 'apps/store_app/android/app/src/main/kotlin/com/luumoh/store/MainActivity.kt'
  },
  @{
    Name = 'rider'
    AppDir = 'rider_app'
    Package = 'com.luumoh.rider'
    Label = 'Luumoh Rider'
    MainActivity = 'apps/rider_app/android/app/src/main/kotlin/com/luumoh/rider/MainActivity.kt'
  }
)

foreach ($app in $apps) {
  $appRoot = Join-Path $repoRoot "apps/$($app.AppDir)"
  $androidRoot = Join-Path $appRoot 'android'
  $gradlePath = Join-Path $androidRoot 'app/build.gradle.kts'
  $settingsPath = Join-Path $androidRoot 'settings.gradle.kts'
  $gradlePropertiesPath = Join-Path $androidRoot 'gradle.properties'
  $gradleWrapperPath = Join-Path $androidRoot 'gradle/wrapper/gradle-wrapper.properties'
  $manifestPath = Join-Path $androidRoot 'app/src/main/AndroidManifest.xml'
  $mainActivityPath = Join-Path $repoRoot $app.MainActivity
  $keyPropertiesPath = Join-Path $androidRoot 'key.properties'

  if (!(Test-Path $gradlePath)) {
    Add-Result 'error' "$($app.Name) Gradle" 'Android app Gradle file is missing.'
  } else {
    $gradle = Get-Content $gradlePath -Raw
    if ($gradle -match 'com\.example') {
      Add-Result 'error' "$($app.Name) package" 'Gradle file still contains a com.example package.'
    }
    if ($gradle -match "namespace\s*=\s*`"$([regex]::Escape($app.Package))`"") {
      Add-Result 'ok' "$($app.Name) namespace" "Uses $($app.Package)."
    } else {
      Add-Result 'error' "$($app.Name) namespace" "Expected namespace $($app.Package)."
    }
    if ($gradle -match "applicationId\s*=\s*`"$([regex]::Escape($app.Package))`"") {
      Add-Result 'ok' "$($app.Name) applicationId" "Uses $($app.Package)."
    } else {
      Add-Result 'error' "$($app.Name) applicationId" "Expected applicationId $($app.Package)."
    }
    if ($gradle -match 'signingConfigs' -and $gradle -match 'key\.properties') {
      Add-Result 'ok' "$($app.Name) release signing hook" 'Release signing reads android/key.properties.'
    } else {
      Add-Result 'error' "$($app.Name) release signing hook" 'Release signing is not wired to key.properties.'
    }
    if ($gradle -match 'signingConfigs\.getByName\("debug"\)') {
      Add-Result 'error' "$($app.Name) release signing fallback" 'Release build can fall back to debug signing.'
    } else {
      Add-Result 'ok' "$($app.Name) release signing fallback" 'Release builds do not fall back to debug signing.'
    }
    if ($gradle -match 'targetSdk\s*=\s*36') {
      Add-Result 'ok' "$($app.Name) targetSdk" 'Targets Android 16 / API 36.'
    } else {
      Add-Result 'error' "$($app.Name) targetSdk" 'Expected targetSdk = 36 for Google Play launch readiness.'
    }
    if ($gradle -match 'compileSdk\s*=\s*36') {
      Add-Result 'ok' "$($app.Name) compileSdk" 'Compiles against Android 16 / API 36.'
    } else {
      Add-Result 'error' "$($app.Name) compileSdk" 'Expected compileSdk = 36 for release builds.'
    }
  }

  if (!(Test-Path $settingsPath)) {
    Add-Result 'error' "$($app.Name) Android settings" 'Android settings.gradle.kts is missing.'
  } else {
    $settings = Get-Content $settingsPath -Raw
    if ($settings -match 'id\("com\.android\.application"\)\s+version\s+"9\.3\.1"') {
      Add-Result 'ok' "$($app.Name) AGP" 'Uses Android Gradle Plugin 9.3.1.'
    } else {
      Add-Result 'error' "$($app.Name) AGP" 'Expected Android Gradle Plugin 9.3.1.'
    }
    if ($settings -match 'id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+"2\.4\.10"') {
      Add-Result 'ok' "$($app.Name) Kotlin Gradle plugin" 'Uses Kotlin Gradle plugin 2.4.10.'
    } else {
      Add-Result 'error' "$($app.Name) Kotlin Gradle plugin" 'Expected Kotlin Gradle plugin 2.4.10.'
    }
  }

  if (!(Test-Path $gradleWrapperPath)) {
    Add-Result 'error' "$($app.Name) Gradle wrapper" 'Gradle wrapper properties are missing.'
  } else {
    $gradleWrapper = Get-Content $gradleWrapperPath -Raw
    if ($gradleWrapper -match 'gradle-9\.6\.1-all\.zip') {
      Add-Result 'ok' "$($app.Name) Gradle wrapper" 'Uses Gradle 9.6.1.'
    } else {
      Add-Result 'error' "$($app.Name) Gradle wrapper" 'Expected Gradle 9.6.1.'
    }
  }

  if (!(Test-Path $gradlePropertiesPath)) {
    Add-Result 'error' "$($app.Name) Gradle properties" 'Android gradle.properties is missing.'
  } else {
    $gradleProperties = Get-Content $gradlePropertiesPath -Raw
    if ($gradleProperties -match 'android\.newDsl=false' -and $gradleProperties -match 'android\.builtInKotlin=false') {
      Add-Result 'ok' "$($app.Name) AGP compatibility flags" 'Keeps the Flutter-compatible legacy AGP/KGP path.'
    } else {
      Add-Result 'warning' "$($app.Name) AGP compatibility flags" 'Expected android.newDsl=false and android.builtInKotlin=false for the current Flutter plugin stack.'
    }
  }

  if (!(Test-Path $mainActivityPath)) {
    Add-Result 'error' "$($app.Name) MainActivity" 'Production package MainActivity is missing.'
  } else {
    $mainActivity = Get-Content $mainActivityPath -Raw
    if ($mainActivity -match "package\s+$([regex]::Escape($app.Package))") {
      Add-Result 'ok' "$($app.Name) MainActivity package" "Uses $($app.Package)."
    } else {
      Add-Result 'error' "$($app.Name) MainActivity package" "Expected package $($app.Package)."
    }
  }

  if (!(Test-Path $manifestPath)) {
    Add-Result 'error' "$($app.Name) manifest" 'Android manifest is missing.'
  } else {
    $manifest = Get-Content $manifestPath -Raw
    if ($manifest -match 'android.permission.INTERNET') {
      Add-Result 'ok' "$($app.Name) INTERNET" 'Permission present.'
    } else {
      Add-Result 'error' "$($app.Name) INTERNET" 'INTERNET permission is missing.'
    }
    if ($manifest -match 'android.permission.POST_NOTIFICATIONS') {
      Add-Result 'ok' "$($app.Name) POST_NOTIFICATIONS" 'Permission present.'
    } else {
      Add-Result 'error' "$($app.Name) POST_NOTIFICATIONS" 'Android 13 notification permission is missing.'
    }
    if ($manifest -match "android:label=`"$([regex]::Escape($app.Label))`"") {
      Add-Result 'ok' "$($app.Name) label" "Uses $($app.Label)."
    } else {
      Add-Result 'error' "$($app.Name) label" "Expected launcher label $($app.Label)."
    }
  }

  if (!(Test-Path $keyPropertiesPath)) {
    Add-Result (External-Level) "$($app.Name) key.properties" 'Create android/key.properties from key.properties.example for production signing.'
  } else {
    $keyProps = Read-PropertiesFile $keyPropertiesPath
    foreach ($name in @('storePassword', 'keyPassword', 'keyAlias', 'storeFile')) {
      if ([string]$keyProps[$name] -and [string]$keyProps[$name] -notmatch 'change-me') {
        Add-Result 'ok' "$($app.Name) key.properties:$name" 'Configured.'
      } else {
        Add-Result 'error' "$($app.Name) key.properties:$name" 'Missing or placeholder value.'
      }
    }

    if ([string]$keyProps['storeFile']) {
      $keystorePath = [IO.Path]::GetFullPath((Join-Path (Join-Path $androidRoot 'app') ([string]$keyProps['storeFile'])))
      if (Test-Path $keystorePath) {
        Add-Result 'ok' "$($app.Name) keystore file" 'Upload keystore exists.'
      } else {
        Add-Result 'error' "$($app.Name) keystore file" "Missing keystore file at $keystorePath."
      }
    }
  }
}

$gitignorePath = Join-Path $repoRoot '.gitignore'
if (Test-Path $gitignorePath) {
  $gitignore = Get-Content $gitignorePath -Raw
  foreach ($pattern in @('**/android/key.properties', '**/android/*.jks', '**/android/*.keystore')) {
    if ($gitignore -match [regex]::Escape($pattern)) {
      Add-Result 'ok' "gitignore:$pattern" 'Ignored.'
    } else {
      Add-Result 'error' "gitignore:$pattern" 'Missing ignore rule.'
    }
  }
}

$results | Sort-Object Level, Check | Format-Table -AutoSize

$errorCount = @($results | Where-Object { $_.Level -eq 'error' }).Count
$warningCount = @($results | Where-Object { $_.Level -eq 'warning' }).Count

if ($errorCount -gt 0) {
  throw "$errorCount Android release readiness error(s) found."
}

Write-Host "Android release readiness checks passed with $warningCount warning(s)."
