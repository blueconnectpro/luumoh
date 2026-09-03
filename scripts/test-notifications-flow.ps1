param(
  [string]$CustomerEmail = 'customer.notify@luumoh.test',
  [string]$StoreEmail = 'store.notify@luumoh.test',
  [string]$RiderEmail = 'rider.notify@luumoh.test',
  [string]$AdminEmail = 'admin.notify@luumoh.test',
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

function Register-Test-Device {
  param(
    [string]$SupabaseUrl,
    [hashtable]$Headers,
    [string]$Token,
    [string]$Name
  )

  return Invoke-Rpc `
    -SupabaseUrl $SupabaseUrl `
    -Name 'register_notification_device' `
    -Headers $Headers `
    -Body @{
      p_platform     = 'test'
      p_provider     = 'test'
      p_device_token = $Token
      p_device_name  = $Name
    }
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

function Assert-NotificationType {
  param(
    [array]$Notifications,
    [string]$Type,
    [string]$Label
  )

  if (-not (@($Notifications) | Where-Object { $_.type -eq $Type } | Select-Object -First 1)) {
    $Notifications | Select-Object type, title, body | Format-Table -AutoSize
    throw "Missing $Label notification of type $Type."
  }
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

$customerId = Ensure-Test-User -SupabaseUrl $supabaseUrl -ServiceHeaders $serviceHeaders -Email $CustomerEmail -Password $Password -FullName 'Notify Smoke Customer' -Phone '+2348000000811' -Role 'customer'
$storeUserId = Ensure-Test-User -SupabaseUrl $supabaseUrl -ServiceHeaders $serviceHeaders -Email $StoreEmail -Password $Password -FullName 'Notify Smoke Store' -Phone '+2348000000822' -Role 'store_admin'
$riderId = Ensure-Test-User -SupabaseUrl $supabaseUrl -ServiceHeaders $serviceHeaders -Email $RiderEmail -Password $Password -FullName 'Notify Smoke Rider' -Phone '+2348000000833' -Role 'rider'
$adminId = Ensure-Test-User -SupabaseUrl $supabaseUrl -ServiceHeaders $serviceHeaders -Email $AdminEmail -Password $Password -FullName 'Notify Smoke Admin' -Phone '+2348000000844' -Role 'admin'

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
$adminSession = Sign-In -SupabaseUrl $supabaseUrl -PublishableKey $publishableKey -Email $AdminEmail -Password $Password

$customerHeaders = @{ apikey = $publishableKey; Authorization = "Bearer $($customerSession.access_token)" }
$storeHeaders = @{ apikey = $publishableKey; Authorization = "Bearer $($storeSession.access_token)" }
$riderHeaders = @{ apikey = $publishableKey; Authorization = "Bearer $($riderSession.access_token)" }
$adminHeaders = @{ apikey = $publishableKey; Authorization = "Bearer $($adminSession.access_token)" }

$orderId = Invoke-Rpc `
  -SupabaseUrl $supabaseUrl `
  -Name 'place_order' `
  -Headers $customerHeaders `
  -Body @{
    p_store_id         = $StoreId
    p_delivery_address = 'Notification smoke delivery address, Lagos'
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
Write-Host "Placed notification smoke order: $orderId"

$orderRows = Invoke-SupabaseJson `
  -Method 'GET' `
  -Uri "$supabaseUrl/rest/v1/order_summaries?id=eq.$orderId&select=id,total_amount" `
  -Headers $customerHeaders
$order = @($orderRows)[0]
$paymentReference = "notify-smoke-$orderId"

Invoke-SupabaseJson `
  -Method 'POST' `
  -Uri "$supabaseUrl/rest/v1/payments" `
  -Headers $serviceHeaders `
  -Body @{
    order_id                       = $orderId
    provider                       = 'monnify'
    payment_reference              = $paymentReference
    provider_transaction_reference = "notify-tx-$orderId"
    amount                         = $order.total_amount
    status                         = 'pending'
    checkout_url                   = 'https://example.test/notify-smoke'
    raw_response                   = @{ smoke = $true }
  } | Out-Null

Invoke-Rpc `
  -SupabaseUrl $supabaseUrl `
  -Name 'finalize_paid_order' `
  -Headers $serviceHeaders `
  -Body @{
    p_payment_reference              = $paymentReference
    p_provider_transaction_reference = "notify-tx-$orderId"
    p_amount                         = $order.total_amount
    p_raw_response                   = @{ smoke = $true; source = 'notifications-flow' }
  } | Out-Null

foreach ($status in @('accepted', 'preparing', 'ready_for_pickup')) {
  Invoke-Rpc -SupabaseUrl $supabaseUrl -Name 'store_update_order_status' -Headers $storeHeaders -Body @{
    p_order_id = $orderId
    p_status   = $status
    p_note     = "Notification smoke store moved order to $status"
  } | Out-Null
}

Invoke-Rpc -SupabaseUrl $supabaseUrl -Name 'rider_set_availability' -Headers $riderHeaders -Body @{
  p_is_online = $true
} | Out-Null

Invoke-Rpc -SupabaseUrl $supabaseUrl -Name 'accept_rider_order' -Headers $riderHeaders -Body @{
  p_order_id    = $orderId
  p_eta_minutes = 25
  p_note        = 'Notification smoke rider accepted'
} | Out-Null

Invoke-Rpc -SupabaseUrl $supabaseUrl -Name 'update_rider_eta' -Headers $riderHeaders -Body @{
  p_order_id    = $orderId
  p_eta_minutes = 15
  p_note        = 'Notification smoke ETA update'
} | Out-Null

Invoke-Rpc -SupabaseUrl $supabaseUrl -Name 'rider_update_order_status' -Headers $riderHeaders -Body @{
  p_order_id = $orderId
  p_status   = 'out_for_delivery'
  p_note     = 'Notification smoke rider confirmed pickup'
} | Out-Null

Invoke-Rpc -SupabaseUrl $supabaseUrl -Name 'rider_update_order_status' -Headers $riderHeaders -Body @{
  p_order_id = $orderId
  p_status   = 'delivered'
  p_note     = 'Notification smoke delivered'
} | Out-Null

$customerNotifications = @(Invoke-SupabaseJson -Method 'GET' -Uri "$supabaseUrl/rest/v1/user_notifications?user_id=eq.$customerId&select=type,title,body,data&order=created_at.desc&limit=50" -Headers $serviceHeaders) |
  Where-Object { $_.data.order_id -eq $orderId }
$storeNotifications = @(Invoke-SupabaseJson -Method 'GET' -Uri "$supabaseUrl/rest/v1/user_notifications?user_id=eq.$storeUserId&select=type,title,body,data&order=created_at.desc&limit=50" -Headers $serviceHeaders) |
  Where-Object { $_.data.order_id -eq $orderId }
$riderNotifications = @(Invoke-SupabaseJson -Method 'GET' -Uri "$supabaseUrl/rest/v1/user_notifications?user_id=eq.$riderId&select=type,title,body,data&order=created_at.desc&limit=50" -Headers $serviceHeaders) |
  Where-Object { $_.data.order_id -eq $orderId }
$adminNotifications = @(Invoke-SupabaseJson -Method 'GET' -Uri "$supabaseUrl/rest/v1/user_notifications?user_id=eq.$adminId&select=type,title,body,data&order=created_at.desc&limit=50" -Headers $serviceHeaders) |
  Where-Object { $_.data.order_id -eq $orderId }

Assert-NotificationType -Notifications $customerNotifications -Type 'payment_success' -Label 'customer payment success'
Assert-NotificationType -Notifications $customerNotifications -Type 'eta_updated' -Label 'customer ETA'
Assert-NotificationType -Notifications $customerNotifications -Type 'order_status' -Label 'customer order status'
Assert-NotificationType -Notifications $storeNotifications -Type 'order_paid' -Label 'store paid order'
Assert-NotificationType -Notifications $storeNotifications -Type 'rider_assigned' -Label 'store rider assignment'
Assert-NotificationType -Notifications $riderNotifications -Type 'rider_assigned' -Label 'rider assignment'
Assert-NotificationType -Notifications $adminNotifications -Type 'order_paid' -Label 'admin paid order'

$customerNotifications | Select-Object type, title | Format-Table -AutoSize

Write-Host 'Supabase notifications realtime smoke test passed.'
