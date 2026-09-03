param(
  [string]$AvdName = "Pixel_9",
  [string]$DnsServers = "8.8.8.8,1.1.1.1"
)

$ErrorActionPreference = "Stop"

$sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\sdk" }
$adb = Join-Path $sdkRoot "platform-tools\adb.exe"
$emulator = Join-Path $sdkRoot "emulator\emulator.exe"

if (-not (Test-Path $adb)) {
  throw "adb.exe was not found at $adb"
}

if (-not (Test-Path $emulator)) {
  throw "emulator.exe was not found at $emulator"
}

Write-Host "Stopping running Android emulators..."
$devices = & $adb devices | Select-String -Pattern "^emulator-\d+\s+device"
foreach ($device in $devices) {
  $serial = ($device.ToString() -split "\s+")[0]
  Write-Host "Stopping $serial"
  & $adb -s $serial emu kill | Out-Null
}

Start-Sleep -Seconds 3

Write-Host "Starting $AvdName with DNS servers $DnsServers..."
Start-Process -FilePath $emulator -ArgumentList @(
  "-avd",
  $AvdName,
  "-dns-server",
  $DnsServers
) -WindowStyle Normal

Write-Host "Waiting for emulator to boot..."
& $adb wait-for-device | Out-Null

for ($i = 0; $i -lt 60; $i++) {
  $booted = ""
  try {
    $booted = (& $adb shell getprop sys.boot_completed 2>$null).Trim()
  } catch {
    Start-Sleep -Seconds 2
    continue
  }
  if ($booted -eq "1") {
    break
  }
  Start-Sleep -Seconds 2
}

Write-Host "Testing DNS..."
& $adb shell ping -c 1 nrhezcdnqzgteppkcife.supabase.co
