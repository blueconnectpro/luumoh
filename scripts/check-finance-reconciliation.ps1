param(
  [switch]$FailOnIssues,
  [switch]$FailOnWarnings,
  [switch]$Repair
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

if ($Repair) {
  $repairRows = Invoke-RestMethod `
    -Method 'POST' `
    -Uri "$supabaseUrl/rest/v1/rpc/admin_repair_finance_reconciliation" `
    -Headers $headers `
    -ContentType 'application/json' `
    -Body '{}' `
    -TimeoutSec 30

  Write-Host 'Finance repair results:'
  $repairRows | Sort-Object metric | Format-Table -AutoSize
}

$rows = Invoke-RestMethod `
  -Method 'POST' `
  -Uri "$supabaseUrl/rest/v1/rpc/admin_finance_reconciliation" `
  -Headers $headers `
  -ContentType 'application/json' `
  -Body '{}' `
  -TimeoutSec 30

$rows | Sort-Object severity, metric | Format-Table -AutoSize

$issues = @($rows | Where-Object { $_.severity -eq 'error' -and [decimal]$_.value -gt 0 })
$warnings = @($rows | Where-Object { $_.severity -eq 'warning' -and [decimal]$_.value -gt 0 })
if ($FailOnIssues -and $issues.Count -gt 0) {
  throw "$($issues.Count) finance reconciliation issue(s) found."
}

if ($FailOnWarnings -and $warnings.Count -gt 0) {
  throw "$($warnings.Count) finance reconciliation warning metric(s) found."
}

Write-Host "Finance reconciliation completed with $($issues.Count) issue metric(s) and $($warnings.Count) warning metric(s)."
