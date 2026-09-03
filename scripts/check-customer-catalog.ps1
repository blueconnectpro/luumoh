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

$envValues = Read-DotEnv '.env'
$supabaseUrl = ([string]$envValues['SUPABASE_URL']).Trim().TrimEnd('/')
$publishableKey = ([string]$envValues['SUPABASE_PUBLISHABLE_KEY']).Trim()

if (!$supabaseUrl -or !$publishableKey) {
  throw 'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required in .env.'
}

$headers = @{
  apikey        = $publishableKey
  Authorization = "Bearer $publishableKey"
}

$endpoint = "$supabaseUrl/rest/v1/customer_catalog?select=store_name,name,is_available,quantity_available&order=store_name.asc&order=name.asc"
$rows = Invoke-RestMethod -Method Get -Uri $endpoint -Headers $headers -TimeoutSec 30

if ($rows.Count -eq 0) {
  Write-Warning 'No customer catalog rows are visible. Check store is_active, product stock, and customer_catalog policies/grants.'
  exit 1
}

$rows |
  Select-Object store_name, name, is_available, quantity_available |
  Format-Table -AutoSize

Write-Host "Total visible catalog rows: $($rows.Count)"
