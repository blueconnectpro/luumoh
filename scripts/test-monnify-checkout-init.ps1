param(
  [string]$Email = 'customer.checkout@luumoh.test',
  [string]$Password = 'Password123!',
  [string]$StoreId = '77777777-7777-7777-7777-777777777771',
  [string]$ProductId = '88888888-8888-8888-8888-888888888881',
  [int]$Quantity = 1
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
    TimeoutSec  = 45
    ContentType = 'application/json'
  }

  if ($null -ne $Body) {
    $params.Body = ($Body | ConvertTo-Json -Depth 12)
  }

  try {
    return Invoke-RestMethod @params
  } catch {
    throw "Request failed: $Method $Uri - $($_.Exception.Message)"
  }
}

function Sign-In {
  param(
    [string]$SupabaseUrl,
    [string]$PublishableKey,
    [string]$Email,
    [string]$Password
  )

  return Invoke-SupabaseJson `
    -Method 'POST' `
    -Uri "$SupabaseUrl/auth/v1/token?grant_type=password" `
    -Headers @{ apikey = $PublishableKey } `
    -Body @{ email = $Email; password = $Password }
}

function Ensure-Test-Customer {
  param(
    [string]$SupabaseUrl,
    [hashtable]$ServiceHeaders,
    [string]$Email,
    [string]$Password
  )

  $users = Invoke-SupabaseJson `
    -Method 'GET' `
    -Uri "$SupabaseUrl/auth/v1/admin/users?per_page=1000" `
    -Headers $ServiceHeaders

  $existing = @($users.users) | Where-Object { $_.email -eq $Email } | Select-Object -First 1
  if ($existing) {
    Invoke-SupabaseJson `
      -Method 'PUT' `
      -Uri "$SupabaseUrl/auth/v1/admin/users/$($existing.id)" `
      -Headers $ServiceHeaders `
      -Body @{
        password      = $Password
        email_confirm = $true
        user_metadata = @{
          full_name = 'Checkout Smoke Customer'
          phone     = '+2348000000888'
        }
      } | Out-Null
    $userId = $existing.id
  } else {
    $created = Invoke-SupabaseJson `
      -Method 'POST' `
      -Uri "$SupabaseUrl/auth/v1/admin/users" `
      -Headers $ServiceHeaders `
      -Body @{
        email         = $Email
        password      = $Password
        email_confirm = $true
        user_metadata = @{
          full_name = 'Checkout Smoke Customer'
          phone     = '+2348000000888'
        }
      }
    $userId = $created.id
  }

  Invoke-SupabaseJson `
    -Method 'POST' `
    -Uri "$SupabaseUrl/rest/v1/profiles?on_conflict=id" `
    -Headers $ServiceHeaders `
    -Prefer 'resolution=merge-duplicates' `
    -Body @(
      @{
        id        = $userId
        role      = 'customer'
        full_name = 'Checkout Smoke Customer'
        phone     = '+2348000000888'
      }
    ) | Out-Null
}

function Ensure-Demo-CatalogReady {
  param(
    [string]$SupabaseUrl,
    [hashtable]$ServiceHeaders,
    [string]$StoreId,
    [string]$ProductId
  )

  Invoke-SupabaseJson -Method 'PATCH' -Uri "$SupabaseUrl/rest/v1/stores?id=eq.$StoreId" -Headers $ServiceHeaders -Body @{
    is_active = $true
    is_open   = $true
  } | Out-Null

  Invoke-SupabaseJson -Method 'PATCH' -Uri "$SupabaseUrl/rest/v1/products?id=eq.$ProductId" -Headers $ServiceHeaders -Body @{
    is_available = $true
  } | Out-Null

  Invoke-SupabaseJson -Method 'PATCH' -Uri "$SupabaseUrl/rest/v1/inventory_items?product_id=eq.$ProductId" -Headers $ServiceHeaders -Body @{
    quantity_on_hand = 100
  } | Out-Null
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

Ensure-Demo-CatalogReady -SupabaseUrl $supabaseUrl -ServiceHeaders $serviceHeaders -StoreId $StoreId -ProductId $ProductId
Ensure-Test-Customer -SupabaseUrl $supabaseUrl -ServiceHeaders $serviceHeaders -Email $Email -Password $Password

$session = Sign-In -SupabaseUrl $supabaseUrl -PublishableKey $publishableKey -Email $Email -Password $Password
$customerHeaders = @{
  apikey        = $publishableKey
  Authorization = "Bearer $($session.access_token)"
}

$orderId = Invoke-SupabaseJson `
  -Method 'POST' `
  -Uri "$supabaseUrl/rest/v1/rpc/place_order" `
  -Headers $customerHeaders `
  -Body @{
    p_store_id         = $StoreId
    p_delivery_address = 'Checkout smoke delivery address, Lagos'
    p_items            = @(@{ product_id = $ProductId; quantity = $Quantity })
    p_promo_code       = $null
    p_fulfillment_type = 'delivery'
    p_customer_latitude = 6.4281
    p_customer_longitude = 3.4219
  }
$orderId = "$orderId".Trim('"')

$checkout = Invoke-SupabaseJson `
  -Method 'POST' `
  -Uri "$supabaseUrl/functions/v1/monnify-initiate" `
  -Headers $customerHeaders `
  -Body @{ orderId = $orderId }

if (!$checkout.paymentReference -or $checkout.paymentReference -notmatch '^luumoh-') {
  $checkout | ConvertTo-Json -Depth 8
  throw 'Monnify paymentReference was not returned.'
}

if (!$checkout.apiKey -or !$checkout.contractCode) {
  $checkout | ConvertTo-Json -Depth 8
  throw 'Monnify SDK apiKey and contractCode are required.'
}

if (!$checkout.amount -or [decimal]$checkout.amount -le 0) {
  $checkout | ConvertTo-Json -Depth 8
  throw 'Monnify SDK amount must be greater than zero.'
}

if (!$checkout.currencyCode -or $checkout.currencyCode -ne 'NGN') {
  $checkout | ConvertTo-Json -Depth 8
  throw 'Monnify SDK currencyCode must be NGN.'
}

if (!$checkout.customerEmail -or !$checkout.customerName) {
  $checkout | ConvertTo-Json -Depth 8
  throw 'Monnify SDK customer details were not returned.'
}

if (!$checkout.redirectUrl -or $checkout.redirectUrl -notmatch '^https?://') {
  $checkout | ConvertTo-Json -Depth 8
  throw 'Monnify redirectUrl is not HTTP(S).'
}

Invoke-SupabaseJson `
  -Method 'POST' `
  -Uri "$supabaseUrl/rest/v1/rpc/customer_cancel_pending_order" `
  -Headers $customerHeaders `
  -Body @{ p_order_id = $orderId } | Out-Null

[pscustomobject]@{
  OrderId          = $orderId
  PaymentReference = $checkout.paymentReference
  Amount           = $checkout.amount
  Currency         = $checkout.currencyCode
  ContractCode     = $checkout.contractCode
  RedirectUrl      = $checkout.redirectUrl
} | Format-List

Write-Host 'Monnify SDK checkout initialization smoke test passed.'
