param(
  [string]$OutputDir = "reports",
  [int]$Limit = 1000,
  [int]$RecentDays = 14
)

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

function Invoke-SupabaseJson {
  param(
    [string]$Method,
    [string]$Uri,
    [hashtable]$Headers,
    [object]$Body = $null
  )

  $params = @{
    Method     = $Method
    Uri        = $Uri
    Headers    = $Headers
    TimeoutSec = 30
  }

  if ($null -ne $Body) {
    $params.ContentType = 'application/json'
    $params.Body = ($Body | ConvertTo-Json -Depth 12)
  }

  try {
    return Invoke-RestMethod @params
  } catch {
    throw "Request failed: $Method $Uri - $($_.Exception.Message)"
  }
}

function ConvertTo-Array {
  param([object]$Rows)

  if ($null -eq $Rows) {
    return @()
  }

  if ($Rows -is [System.Array]) {
    return @($Rows)
  }

  return @($Rows)
}

function Export-Rows {
  param(
    [object[]]$Rows,
    [string]$Path
  )

  if ($Rows.Count -eq 0) {
    Set-Content -Path $Path -Value '' -Encoding UTF8
  } else {
    $Rows | Export-Csv -Path $Path -NoTypeInformation
  }

  return [pscustomobject]@{
    file = (Split-Path $Path -Leaf)
    rows = $Rows.Count
  }
}

function Export-RestCsv {
  param(
    [string]$SupabaseUrl,
    [hashtable]$Headers,
    [string]$Path,
    [string]$Query
  )

  $rows = ConvertTo-Array (Invoke-SupabaseJson -Method 'GET' -Uri "$SupabaseUrl/rest/v1/$Query" -Headers $Headers)

  Write-Host "Exported $Path"
  return Export-Rows -Rows $rows -Path $Path
}

function Export-RpcCsv {
  param(
    [string]$SupabaseUrl,
    [hashtable]$Headers,
    [string]$Path,
    [string]$FunctionName
  )

  $rows = ConvertTo-Array (Invoke-SupabaseJson -Method 'POST' -Uri "$SupabaseUrl/rest/v1/rpc/$FunctionName" -Headers $Headers -Body @{})

  Write-Host "Exported $Path"
  return Export-Rows -Rows $rows -Path $Path
}

$envValues = Read-DotEnv '.env'
$supabaseUrl = ([string]$envValues['SUPABASE_URL']).Trim().TrimEnd('/')
$serviceRoleKey = ([string]$envValues['SUPABASE_SERVICE_ROLE_KEY']).Trim()

if (!$supabaseUrl -or !$serviceRoleKey) {
  throw 'SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required in .env.'
}

if (!(Test-Path $OutputDir)) {
  New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $OutputDir "ops-$timestamp"
New-Item -ItemType Directory -Path $runDir | Out-Null

$headers = @{
  apikey        = $serviceRoleKey
  Authorization = "Bearer $serviceRoleKey"
}

$since = (Get-Date).AddDays(-1 * $RecentDays).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$exports = @()

$restExports = @(
  @{ File = 'orders.csv'; Query = "order_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'recent_orders.csv'; Query = "order_summaries?created_at=gte.$since&select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'payments.csv'; Query = "payment_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'store_settlements.csv'; Query = "store_settlement_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'rider_settlements.csv'; Query = "rider_settlement_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'open_issues.csv'; Query = "order_issue_summaries?status=in.(open,in_review)&select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'catalog.csv'; Query = "customer_catalog?select=*&order=store_name.asc&limit=$Limit" },
  @{ File = 'promo_codes.csv'; Query = "promo_code_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'order_reviews.csv'; Query = "order_review_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'product_reviews.csv'; Query = "product_review_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'rider_reviews.csv'; Query = "rider_review_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'rider_ratings.csv'; Query = "rider_rating_summaries?select=*&order=average_rating.desc.nullslast&limit=$Limit" },
  @{ File = 'rider_locations.csv'; Query = "rider_location_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'store_staff_presence.csv'; Query = "store_staff_presence_summaries?select=*&order=last_seen_at.desc.nullslast&limit=$Limit" },
  @{ File = 'store_employee_activity.csv'; Query = "store_employee_activity_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'notifications.csv'; Query = "user_notifications?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'notification_deliveries.csv'; Query = "notification_delivery_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'order_messages.csv'; Query = "order_message_summaries?select=*&order=created_at.desc&limit=$Limit" },
  @{ File = 'payment_webhooks.csv'; Query = "payment_webhook_event_summaries?select=*&order=created_at.desc&limit=$Limit" }
)

foreach ($export in $restExports) {
  $exports += Export-RestCsv `
    -SupabaseUrl $supabaseUrl `
    -Headers $headers `
    -Path (Join-Path $runDir $export.File) `
    -Query $export.Query
}

$rpcExports = @(
  @{ File = 'realtime_readiness.csv'; Function = 'admin_realtime_readiness' },
  @{ File = 'security_policy_audit.csv'; Function = 'admin_security_policy_audit' },
  @{ File = 'finance_reconciliation.csv'; Function = 'admin_finance_reconciliation' }
)

foreach ($export in $rpcExports) {
  $exports += Export-RpcCsv `
    -SupabaseUrl $supabaseUrl `
    -Headers $headers `
    -Path (Join-Path $runDir $export.File) `
    -FunctionName $export.Function
}

$financeRows = Import-Csv (Join-Path $runDir 'finance_reconciliation.csv')
$securityRows = Import-Csv (Join-Path $runDir 'security_policy_audit.csv')
$realtimeRows = Import-Csv (Join-Path $runDir 'realtime_readiness.csv')

$healthSummary = [pscustomobject]@{
  generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
  supabase_url = $supabaseUrl
  recent_window_days = $RecentDays
  export_limit = $Limit
  finance_issue_metrics = @($financeRows | Where-Object { $_.severity -eq 'issue' }).Count
  finance_warning_metrics = @($financeRows | Where-Object { $_.severity -eq 'warning' }).Count
  security_risks = @($securityRows | Where-Object { $_.risk -ne 'ok' }).Count
  realtime_risks = @($realtimeRows | Where-Object { $_.risk -ne 'ok' }).Count
}

$healthSummary | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $runDir 'health_summary.json') -Encoding UTF8

$manifest = [pscustomobject]@{
  generated_at_utc = $healthSummary.generated_at_utc
  run_directory = $runDir
  supabase_url = $supabaseUrl
  recent_window_days = $RecentDays
  export_limit = $Limit
  files = $exports
  health_summary = $healthSummary
}

$manifest | ConvertTo-Json -Depth 12 | Set-Content -Path (Join-Path $runDir 'manifest.json') -Encoding UTF8

Write-Host "Admin ops report exported to $runDir"
