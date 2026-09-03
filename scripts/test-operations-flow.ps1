param(
  [string]$CustomerEmail = 'customer.ops@luumoh.test',
  [string]$StoreEmail = 'store.ops@luumoh.test',
  [string]$RiderEmail = 'rider.ops@luumoh.test',
  [string]$Password = 'Password123!',
  [string]$StoreId = '77777777-7777-7777-7777-777777777771',
  [string]$ProductId = '88888888-8888-8888-8888-888888888882',
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
    [object]$Body = $null,
    [string]$Prefer = $null
  )

  $headersWithPrefer = @{} + $Headers
  if ($Prefer) {
    $headersWithPrefer['Prefer'] = $Prefer
  }

  $params = @{
    Method      = $Method
    Uri         = $Uri
    Headers     = $headersWithPrefer
    TimeoutSec  = 30
    ContentType = 'application/json'
  }

  if ($null -ne $Body) {
    $params.Body = ($Body | ConvertTo-Json -Depth 12)
  }

  try {
    return Invoke-RestMethod @params
  } catch {
    Write-Host "Supabase request failed: $Method $Uri"
    throw
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
    -Body @{
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

  $users = Invoke-SupabaseJson `
    -Method 'GET' `
    -Uri "$SupabaseUrl/auth/v1/admin/users?per_page=100" `
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
          full_name = $FullName
          phone     = $Phone
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
          full_name = $FullName
          phone     = $Phone
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
        role      = $Role
        full_name = $FullName
        phone     = $Phone
      }
    ) | Out-Null

  return $userId
}

function Invoke-Rpc {
  param(
    [string]$SupabaseUrl,
    [string]$Name,
    [hashtable]$Headers,
    [object]$Body
  )

  return Invoke-SupabaseJson `
    -Method 'POST' `
    -Uri "$SupabaseUrl/rest/v1/rpc/$Name" `
    -Headers $Headers `
    -Body $Body
}

function Get-Order {
  param(
    [string]$SupabaseUrl,
    [hashtable]$Headers,
    [string]$OrderId
  )

  $rows = Invoke-SupabaseJson `
    -Method 'GET' `
    -Uri "$SupabaseUrl/rest/v1/order_summaries?id=eq.$OrderId&select=id,status,payment_status,total_amount,store_name,rider_id,eta_minutes" `
    -Headers $Headers

  if (@($rows).Count -ne 1) {
    throw "Order $OrderId was not visible."
  }

  return @($rows)[0]
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

$customerId = Ensure-Test-User `
  -SupabaseUrl $supabaseUrl `
  -ServiceHeaders $serviceHeaders `
  -Email $CustomerEmail `
  -Password $Password `
  -FullName 'Ops Smoke Customer' `
  -Phone '+2348000000911' `
  -Role 'customer'

$storeUserId = Ensure-Test-User `
  -SupabaseUrl $supabaseUrl `
  -ServiceHeaders $serviceHeaders `
  -Email $StoreEmail `
  -Password $Password `
  -FullName 'Ops Smoke Store' `
  -Phone '+2348000000922' `
  -Role 'store_admin'

$riderId = Ensure-Test-User `
  -SupabaseUrl $supabaseUrl `
  -ServiceHeaders $serviceHeaders `
  -Email $RiderEmail `
  -Password $Password `
  -FullName 'Ops Smoke Rider' `
  -Phone '+2348000000933' `
  -Role 'rider'

Invoke-SupabaseJson `
  -Method 'POST' `
  -Uri "$supabaseUrl/rest/v1/store_members?on_conflict=store_id,user_id" `
  -Headers $serviceHeaders `
  -Prefer 'resolution=merge-duplicates' `
  -Body @(
    @{
      store_id             = $StoreId
      user_id              = $storeUserId
      can_manage_inventory = $true
      can_manage_orders    = $true
    }
  ) | Out-Null

$customerSession = Sign-In -SupabaseUrl $supabaseUrl -PublishableKey $publishableKey -Email $CustomerEmail -Password $Password
$storeSession = Sign-In -SupabaseUrl $supabaseUrl -PublishableKey $publishableKey -Email $StoreEmail -Password $Password
$riderSession = Sign-In -SupabaseUrl $supabaseUrl -PublishableKey $publishableKey -Email $RiderEmail -Password $Password

$customerHeaders = @{
  apikey        = $publishableKey
  Authorization = "Bearer $($customerSession.access_token)"
}
$storeHeaders = @{
  apikey        = $publishableKey
  Authorization = "Bearer $($storeSession.access_token)"
}
$riderHeaders = @{
  apikey        = $publishableKey
  Authorization = "Bearer $($riderSession.access_token)"
}

$orderId = Invoke-Rpc `
  -SupabaseUrl $supabaseUrl `
  -Name 'place_order' `
  -Headers $customerHeaders `
  -Body @{
    p_store_id            = $StoreId
    p_delivery_address    = 'Operations smoke delivery address, Lagos'
    p_items               = @(
      @{
        product_id = $ProductId
        quantity   = $Quantity
      }
    )
    p_promo_code          = $null
    p_fulfillment_type    = 'delivery'
    p_customer_latitude   = 6.4281
    p_customer_longitude  = 3.4219
  }
$orderId = "$orderId".Trim('"')
Write-Host "Placed operations order: $orderId"

$pendingOrder = Get-Order -SupabaseUrl $supabaseUrl -Headers $customerHeaders -OrderId $orderId
$paymentReference = "ops-smoke-$orderId"

Invoke-SupabaseJson `
  -Method 'POST' `
  -Uri "$supabaseUrl/rest/v1/payments" `
  -Headers $serviceHeaders `
  -Body @{
    order_id                         = $orderId
    provider                         = 'monnify'
    payment_reference                = $paymentReference
    provider_transaction_reference   = "ops-tx-$orderId"
    amount                           = $pendingOrder.total_amount
    status                           = 'pending'
    checkout_url                     = 'https://example.test/ops-smoke'
    raw_response                     = @{
      smoke = $true
    }
  } | Out-Null

Invoke-Rpc `
  -SupabaseUrl $supabaseUrl `
  -Name 'finalize_paid_order' `
  -Headers $serviceHeaders `
  -Body @{
    p_payment_reference              = $paymentReference
    p_provider_transaction_reference = "ops-tx-$orderId"
    p_amount                         = $pendingOrder.total_amount
    p_raw_response                   = @{
      smoke = $true
      source = 'operations-flow'
    }
  } | Out-Null

foreach ($status in @('accepted', 'preparing')) {
  Invoke-Rpc `
    -SupabaseUrl $supabaseUrl `
    -Name 'store_update_order_status' `
    -Headers $storeHeaders `
    -Body @{
      p_order_id = $orderId
      p_status   = $status
      p_note     = "Operations smoke store moved order to $status"
    } | Out-Null
  Write-Host "Store moved order to $status"
}

Invoke-SupabaseJson `
  -Method 'PATCH' `
  -Uri "$supabaseUrl/rest/v1/rider_availability?rider_id=neq.$riderId" `
  -Headers $serviceHeaders `
  -Body @{
    is_online = $false
  } | Out-Null

Invoke-Rpc `
  -SupabaseUrl $supabaseUrl `
  -Name 'rider_set_availability' `
  -Headers $riderHeaders `
  -Body @{
    p_is_online = $true
  } | Out-Null

Invoke-Rpc `
  -SupabaseUrl $supabaseUrl `
  -Name 'store_mark_order_ready_and_dispatch' `
  -Headers $storeHeaders `
  -Body @{
    p_order_id     = $orderId
    p_eta_minutes  = 25
  } | Out-Null
Write-Host "Store marked order ready and notified rider"

$readyOrder = Get-Order -SupabaseUrl $supabaseUrl -Headers $riderHeaders -OrderId $orderId
if ($readyOrder.status -ne 'ready_for_pickup' -or $readyOrder.rider_id -ne $riderId) {
  $readyOrder | ConvertTo-Json -Depth 6
  throw 'Ready order was not visible to the assigned rider before acceptance.'
}

Invoke-Rpc `
  -SupabaseUrl $supabaseUrl `
  -Name 'accept_rider_order' `
  -Headers $riderHeaders `
  -Body @{
    p_order_id    = $orderId
    p_eta_minutes = 25
    p_note        = 'Operations smoke rider accepted ready order'
  } | Out-Null
Write-Host "Rider accepted ready order"

Invoke-Rpc `
  -SupabaseUrl $supabaseUrl `
  -Name 'rider_update_order_status' `
  -Headers $riderHeaders `
  -Body @{
    p_order_id = $orderId
    p_status   = 'out_for_delivery'
    p_note     = 'Operations smoke rider confirmed pickup'
  } | Out-Null
Write-Host "Rider confirmed pickup"

Invoke-Rpc `
  -SupabaseUrl $supabaseUrl `
  -Name 'rider_update_order_location' `
  -Headers $riderHeaders `
  -Body @{
    p_order_id         = $orderId
    p_latitude         = 6.524379
    p_longitude        = 3.379206
    p_accuracy_meters  = 12
    p_heading          = 84
    p_speed_mps        = 4.5
    p_note             = 'Operations smoke rider location'
  } | Out-Null

Invoke-Rpc `
  -SupabaseUrl $supabaseUrl `
  -Name 'update_rider_eta' `
  -Headers $riderHeaders `
  -Body @{
    p_order_id    = $orderId
    p_eta_minutes = 15
    p_note        = 'Operations smoke ETA update'
  } | Out-Null

Invoke-Rpc `
  -SupabaseUrl $supabaseUrl `
  -Name 'rider_update_order_status' `
  -Headers $riderHeaders `
  -Body @{
    p_order_id = $orderId
    p_status   = 'delivered'
    p_note     = 'Operations smoke delivered'
  } | Out-Null

$finalOrder = Get-Order -SupabaseUrl $supabaseUrl -Headers $customerHeaders -OrderId $orderId
if ($finalOrder.status -ne 'delivered' -or $finalOrder.payment_status -ne 'paid' -or $finalOrder.rider_id -ne $riderId) {
  $finalOrder | ConvertTo-Json -Depth 6
  throw 'Operations flow did not finish in the expected delivered/paid state.'
}

$events = Invoke-SupabaseJson `
  -Method 'GET' `
  -Uri "$supabaseUrl/rest/v1/delivery_events?order_id=eq.$orderId&select=status,eta_minutes,note,created_at&order=created_at.asc" `
  -Headers $customerHeaders

$locations = Invoke-SupabaseJson `
  -Method 'GET' `
  -Uri "$supabaseUrl/rest/v1/rider_location_summaries?order_id=eq.$orderId&select=rider_name,latitude,longitude,accuracy_meters,note,created_at&order=created_at.desc&limit=5" `
  -Headers $customerHeaders

if (@($locations).Count -lt 1) {
  throw 'Rider location update was not visible to the customer.'
}

$finalOrder | Select-Object id, status, payment_status, total_amount, store_name, rider_id, eta_minutes | Format-Table -AutoSize
$events | Select-Object status, eta_minutes, note | Format-Table -AutoSize
$locations | Select-Object rider_name, latitude, longitude, accuracy_meters, note | Format-Table -AutoSize

Write-Host 'Operations flow smoke test passed.'
