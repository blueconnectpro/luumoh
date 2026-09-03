param(
  [switch]$FailOnWarnings
)

$ErrorActionPreference = 'Stop'

function Read-DotEnv {
  param([string]$Path)
  $values = @{}
  if (!(Test-Path $Path)) { return $values }
  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith('#') -or !$line.Contains('=')) { return }
    $parts = $line.Split('=', 2)
    $values[$parts[0].Trim()] = $parts[1].Trim().Trim('"').Trim("'")
  }
  return $values
}

$envValues = Read-DotEnv '.env'
$supabaseUrl = ([string]$envValues['SUPABASE_URL']).Trim().TrimEnd('/')
$serviceRoleKey = ([string]$envValues['SUPABASE_SERVICE_ROLE_KEY']).Trim()

if (!$supabaseUrl -or !$serviceRoleKey) {
  throw 'SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required in .env.'
}

$headers = @{
  apikey        = $serviceRoleKey
  Authorization = "Bearer $serviceRoleKey"
}

$rows = Invoke-RestMethod `
  -Method 'POST' `
  -Uri "$supabaseUrl/rest/v1/rpc/admin_realtime_readiness" `
  -Headers $headers `
  -ContentType 'application/json' `
  -Body '{}' `
  -TimeoutSec 30

$rows | Sort-Object risk, table_name | Format-Table -AutoSize

$errors = @($rows | Where-Object { $_.risk -eq 'error' })
$warnings = @($rows | Where-Object { $_.risk -eq 'warning' })

if ($errors.Count -gt 0) {
  throw "$($errors.Count) realtime table(s) are missing publication, RLS, or policies."
}

if ($FailOnWarnings -and $warnings.Count -gt 0) {
  throw "$($warnings.Count) realtime table(s) have warnings."
}

Write-Host "Supabase Realtime readiness passed with $($warnings.Count) warning(s)."
