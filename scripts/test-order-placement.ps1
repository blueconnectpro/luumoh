param(
  [string]$Email = 'customer.smoke@luumoh.test',
  [string]$Password = 'Password123!',
  [string]$StoreId = '77777777-7777-7777-7777-777777777771',
  [string]$ProductId = '88888888-8888-8888-8888-888888888881',
  [int]$Quantity = 1
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
    Method      = $Method
    Uri         = $Uri
    Headers     = $Headers
    TimeoutSec  = 30
    ContentType = 'application/json'
  }

  if ($null -ne $Body) {
    $params.Body = ($Body | ConvertTo-Json -Depth 10)
  }

  return Invoke-RestMethod @params
}

function Sign-In {
  param(
    [string]$SupabaseUrl,
    [string]$PublishableKey,
    [string]$Email,
    [string]$Password
  )

  $headers = @{
    apikey = $PublishableKey
  }

  return Invoke-SupabaseJson `
    -Method 'POST' `
    -Uri "$SupabaseUrl/auth/v1/token?grant_type=password" `
    -Headers $headers `
    -Body @{
      email    = $Email
      password = $Password
    }
}

function Ensure-Test-Customer {
  param(
    [string]$SupabaseUrl,
    [string]$PublishableKey,
    [string]$ServiceRoleKey,
    [string]$Email,
    [string]$Password
  )

  try {
    return Sign-In `
      -SupabaseUrl $SupabaseUrl `
      -PublishableKey $PublishableKey `
      -Email $Email `
      -Password $Password
  } catch {
    Write-Host 'Smoke customer sign-in failed. Creating/updating test auth user...'
  }

  $adminHeaders = @{
    apikey        = $ServiceRoleKey
    Authorization = "Bearer $ServiceRoleKey"
  }

  $users = Invoke-SupabaseJson `
    -Method 'GET' `
    -Uri "$SupabaseUrl/auth/v1/admin/users?per_page=100" `
    -Headers $adminHeaders

  $existing = @($users.users) | Where-Object { $_.email -eq $Email } | Select-Object -First 1

  if ($existing) {
    Invoke-SupabaseJson `
      -Method 'PUT' `
      -Uri "$SupabaseUrl/auth/v1/admin/users/$($existing.id)" `
      -Headers $adminHeaders `
      -Body @{
        password      = $Password
        email_confirm = $true
        user_metadata = @{
          full_name = 'Smoke Test Customer'
          phone     = '+2348000000999'
        }
      } | Out-Null
  } else {
    Invoke-SupabaseJson `
      -Method 'POST' `
      -Uri "$SupabaseUrl/auth/v1/admin/users" `
      -Headers $adminHeaders `
      -Body @{
        email         = $Email
        password      = $Password
        email_confirm = $true
        user_metadata = @{
          full_name = 'Smoke Test Customer'
          phone     = '+2348000000999'
        }
      } | Out-Null
  }

  return Sign-In `
    -SupabaseUrl $SupabaseUrl `
    -PublishableKey $PublishableKey `
    -Email $Email `
    -Password $Password
}

function Ensure-Demo-CatalogReady {
  param(
    [string]$SupabaseUrl,
    [hashtable]$ServiceHeaders,
    [string]$StoreId,
    [string]$ProductId
  )

  Invoke-SupabaseJson `
    -Method 'PATCH' `
    -Uri "$SupabaseUrl/rest/v1/stores?id=eq.$StoreId" `
    -Headers $ServiceHeaders `
    -Body @{ is_active = $true; is_open = $true } | Out-Null

  Invoke-SupabaseJson `
    -Method 'PATCH' `
    -Uri "$SupabaseUrl/rest/v1/products?id=eq.$ProductId" `
    -Headers $ServiceHeaders `
    -Body @{ is_available = $true } | Out-Null

  Invoke-SupabaseJson `
    -Method 'PATCH' `
    -Uri "$SupabaseUrl/rest/v1/inventory_items?product_id=eq.$ProductId" `
    -Headers $ServiceHeaders `
    -Body @{ quantity_on_hand = 100 } | Out-Null
}

$envValues = Read-DotEnv '.env'
$supabaseUrl = ([string]$envValues['SUPABASE_URL']).Trim().TrimEnd('/')
$publishableKey = ([string]$envValues['SUPABASE_PUBLISHABLE_KEY']).Trim()
$serviceRoleKey = ([string]$envValues['SUPABASE_SERVICE_ROLE_KEY']).Trim()

if (!$supabaseUrl -or !$publishableKey -or !$serviceRoleKey) {
  throw 'SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, and SUPABASE_SERVICE_ROLE_KEY are required in .env.'
}

$serviceHeaders = @{
  apikey        = $serviceRoleKey
  Authorization = "Bearer $serviceRoleKey"
}

Ensure-Demo-CatalogReady `
  -SupabaseUrl $supabaseUrl `
  -ServiceHeaders $serviceHeaders `
  -StoreId $StoreId `
  -ProductId $ProductId

$session = Ensure-Test-Customer `
  -SupabaseUrl $supabaseUrl `
  -PublishableKey $publishableKey `
  -ServiceRoleKey $serviceRoleKey `
  -Email $Email `
  -Password $Password

$customerToken = $session.access_token
$customerHeaders = @{
  apikey        = $publishableKey
  Authorization = "Bearer $customerToken"
}

$orderId = Invoke-SupabaseJson `
  -Method 'POST' `
  -Uri "$supabaseUrl/rest/v1/rpc/place_order" `
  -Headers $customerHeaders `
  -Body @{
    p_store_id         = $StoreId
    p_delivery_address = 'Smoke test delivery address, Lagos'
    p_items            = @(
      @{
        product_id = $ProductId
        quantity   = $Quantity
      }
    )
    p_promo_code       = $null
    p_fulfillment_type = 'delivery'
    p_customer_latitude = 6.4281
    p_customer_longitude = 3.4219
  }

$orderId = "$orderId".Trim('"')
Write-Host "Placed smoke order: $orderId"

$orderRows = Invoke-SupabaseJson `
  -Method 'GET' `
  -Uri "$supabaseUrl/rest/v1/order_summaries?id=eq.$orderId&select=id,status,payment_status,total_amount,store_name" `
  -Headers $customerHeaders

if (@($orderRows).Count -ne 1) {
  throw 'Smoke order was not visible in order_summaries.'
}

$orderRows | Select-Object id, status, payment_status, total_amount, store_name | Format-Table -AutoSize

Invoke-SupabaseJson `
  -Method 'POST' `
  -Uri "$supabaseUrl/rest/v1/rpc/customer_cancel_pending_order" `
  -Headers $customerHeaders `
  -Body @{
    p_order_id = $orderId
  } | Out-Null

Write-Host "Cancelled smoke order: $orderId"
Write-Host 'Order placement smoke test passed.'
