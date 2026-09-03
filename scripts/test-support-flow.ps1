param(
  [string]$CustomerEmail = 'customer.support@luumoh.test',
  [string]$AdminEmail = 'admin.support@luumoh.test',
  [string]$Password = 'Password123!',
  [string]$StoreId = '77777777-7777-7777-7777-777777777771',
  [string]$ProductId = '88888888-8888-8888-8888-888888888881'
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

function Invoke-SupabaseJson {
  param(
    [string]$Method,
    [string]$Uri,
    [hashtable]$Headers,
    [object]$Body = $null,
    [string]$Prefer = $null
  )
  $headersWithPrefer = @{} + $Headers
  if ($Prefer) { $headersWithPrefer['Prefer'] = $Prefer }
  $params = @{
    Method      = $Method
    Uri         = $Uri
    Headers     = $headersWithPrefer
    TimeoutSec  = 30
    ContentType = 'application/json'
  }
  if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 12) }
  return Invoke-RestMethod @params
}

function Sign-In {
  param([string]$SupabaseUrl, [string]$PublishableKey, [string]$Email, [string]$Password)
  return Invoke-SupabaseJson -Method 'POST' -Uri "$SupabaseUrl/auth/v1/token?grant_type=password" -Headers @{ apikey = $PublishableKey } -Body @{
    email    = $Email
    password = $Password
  }
}

function Ensure-Test-User {
  param(
    [string]$SupabaseUrl,
    [hashtable]$ServiceHeaders,
    [string]$Email,
    [string]$Password,
    [string]$FullName,
    [string]$Phone,
    [string]$Role
  )

  $users = Invoke-SupabaseJson -Method 'GET' -Uri "$SupabaseUrl/auth/v1/admin/users?per_page=1000" -Headers $ServiceHeaders
  $existing = @($users.users) | Where-Object { $_.email -eq $Email } | Select-Object -First 1

  if ($existing) {
    Invoke-SupabaseJson -Method 'PUT' -Uri "$SupabaseUrl/auth/v1/admin/users/$($existing.id)" -Headers $ServiceHeaders -Body @{
      password      = $Password
      email_confirm = $true
      user_metadata = @{ full_name = $FullName; phone = $Phone }
    } | Out-Null
    $userId = $existing.id
  } else {
    $created = Invoke-SupabaseJson -Method 'POST' -Uri "$SupabaseUrl/auth/v1/admin/users" -Headers $ServiceHeaders -Body @{
      email         = $Email
      password      = $Password
      email_confirm = $true
      user_metadata = @{ full_name = $FullName; phone = $Phone }
    }
    $userId = $created.id
  }

  Invoke-SupabaseJson -Method 'POST' -Uri "$SupabaseUrl/rest/v1/profiles?on_conflict=id" -Headers $ServiceHeaders -Prefer 'resolution=merge-duplicates' -Body @(
    @{ id = $userId; role = $Role; full_name = $FullName; phone = $Phone }
  ) | Out-Null

  return $userId
}

function Invoke-Rpc {
  param([string]$SupabaseUrl, [string]$Name, [hashtable]$Headers, [object]$Body)
  return Invoke-SupabaseJson -Method 'POST' -Uri "$SupabaseUrl/rest/v1/rpc/$Name" -Headers $Headers -Body $Body
}

$envValues = Read-DotEnv '.env'
$supabaseUrl = ([string]$envValues['SUPABASE_URL']).Trim().TrimEnd('/')
$publishableKey = ([string]$envValues['SUPABASE_PUBLISHABLE_KEY']).Trim()
$serviceRoleKey = ([string]$envValues['SUPABASE_SERVICE_ROLE_KEY']).Trim()

if (!$supabaseUrl -or !$publishableKey -or !$serviceRoleKey) {
  throw 'SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, and SUPABASE_SERVICE_ROLE_KEY are required in .env.'
}

$serviceHeaders = @{ apikey = $serviceRoleKey; Authorization = "Bearer $serviceRoleKey" }
Ensure-Test-User -SupabaseUrl $supabaseUrl -ServiceHeaders $serviceHeaders -Email $CustomerEmail -Password $Password -FullName 'Support Smoke Customer' -Phone '+2348000000711' -Role 'customer' | Out-Null
Ensure-Test-User -SupabaseUrl $supabaseUrl -ServiceHeaders $serviceHeaders -Email $AdminEmail -Password $Password -FullName 'Support Smoke Admin' -Phone '+2348000000744' -Role 'admin' | Out-Null

$customerSession = Sign-In -SupabaseUrl $supabaseUrl -PublishableKey $publishableKey -Email $CustomerEmail -Password $Password
$adminSession = Sign-In -SupabaseUrl $supabaseUrl -PublishableKey $publishableKey -Email $AdminEmail -Password $Password
$customerHeaders = @{ apikey = $publishableKey; Authorization = "Bearer $($customerSession.access_token)" }
$adminHeaders = @{ apikey = $publishableKey; Authorization = "Bearer $($adminSession.access_token)" }

$orderId = Invoke-Rpc -SupabaseUrl $supabaseUrl -Name 'place_order' -Headers $customerHeaders -Body @{
  p_store_id         = $StoreId
  p_delivery_address = 'Support smoke delivery address, Lagos'
  p_items            = @(@{ product_id = $ProductId; quantity = 1 })
  p_promo_code       = $null
  p_fulfillment_type = 'delivery'
  p_customer_latitude = 6.4281
  p_customer_longitude = 3.4219
}
$orderId = "$orderId".Trim('"')

$issueId = Invoke-Rpc -SupabaseUrl $supabaseUrl -Name 'customer_create_order_issue' -Headers $customerHeaders -Body @{
  p_order_id = $orderId
  p_category = 'order_help'
  p_message  = 'Support smoke issue for launch readiness.'
}
$issueId = "$issueId".Trim('"')

Invoke-Rpc -SupabaseUrl $supabaseUrl -Name 'admin_update_order_issue' -Headers $adminHeaders -Body @{
  p_issue_id    = $issueId
  p_status      = 'in_review'
  p_admin_note  = 'Support smoke in review'
} | Out-Null

Invoke-Rpc -SupabaseUrl $supabaseUrl -Name 'admin_update_order_issue' -Headers $adminHeaders -Body @{
  p_issue_id    = $issueId
  p_status      = 'resolved'
  p_admin_note  = 'Support smoke resolved'
} | Out-Null

$rows = Invoke-SupabaseJson -Method 'GET' -Uri "$supabaseUrl/rest/v1/order_issue_summaries?id=eq.$issueId&select=id,status,category,message,admin_note,order_id" -Headers $adminHeaders
$issue = @($rows)[0]
if (!$issue -or $issue.status -ne 'resolved') {
  $rows | ConvertTo-Json -Depth 6
  throw 'Support issue flow did not finish resolved.'
}

$issue | Select-Object id, status, category, order_id, admin_note | Format-Table -AutoSize
Write-Host 'Support issue smoke test passed.'
