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
  -Uri "$supabaseUrl/rest/v1/rpc/admin_security_policy_audit" `
  -Headers $headers `
  -ContentType 'application/json' `
  -Body '{}' `
  -TimeoutSec 30

$rows | Sort-Object risk, table_name | Format-Table -AutoSize

$errors = @($rows | Where-Object { $_.risk -eq 'error' })
$warnings = @($rows | Where-Object { $_.risk -eq 'warning' })

if ($errors.Count -gt 0) {
  throw "$($errors.Count) table(s) have RLS disabled."
}

if ($FailOnWarnings -and $warnings.Count -gt 0) {
  throw "$($warnings.Count) table(s) have RLS enabled but no policies."
}

Write-Host "Security/RLS audit passed with $($warnings.Count) warning(s)."
