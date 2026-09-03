param(
  [string]$Password = 'Password123!',
  [switch]$SkipOrders
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
    TimeoutSec  = 45
    ContentType = 'application/json'
  }

  if ($null -ne $Body) {
    $params.Body = ($Body | ConvertTo-Json -Depth 16)
  }

  try {
    return Invoke-RestMethod @params
  } catch {
    Write-Host "Supabase request failed: $Method $Uri"
    throw
  }
}

function New-OrUpdateAuthUser {
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
  $metadata = @{
    full_name = $FullName
    phone     = $Phone
  }

  if ($existing) {
    Invoke-SupabaseJson `
      -Method 'PUT' `
      -Uri "$SupabaseUrl/auth/v1/admin/users/$($existing.id)" `
      -Headers $ServiceHeaders `
      -Body @{
        password      = $Password
        email_confirm = $true
        user_metadata = $metadata
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
        user_metadata = $metadata
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

function Upsert-Rows {
  param(
    [string]$SupabaseUrl,
    [hashtable]$ServiceHeaders,
    [string]$Table,
    [string]$Conflict,
    [array]$Rows
  )

  Invoke-SupabaseJson `
    -Method 'POST' `
    -Uri "$SupabaseUrl/rest/v1/${Table}?on_conflict=${Conflict}" `
    -Headers $ServiceHeaders `
    -Prefer 'resolution=merge-duplicates' `
    -Body $Rows | Out-Null
}

function New-PaidOrder {
  param(
    [string]$SupabaseUrl,
    [string]$PublishableKey,
    [hashtable]$ServiceHeaders,
    [string]$CustomerToken,
    [string]$StoreId,
    [array]$Items,
    [string]$Address,
    [decimal]$Latitude,
    [decimal]$Longitude,
    [string]$ReferencePrefix
  )

  $customerHeaders = @{
    apikey        = $PublishableKey
    Authorization = "Bearer $CustomerToken"
  }

  $orderId = Invoke-SupabaseJson `
    -Method 'POST' `
    -Uri "$SupabaseUrl/rest/v1/rpc/place_order" `
    -Headers $customerHeaders `
    -Body @{
      p_store_id            = $StoreId
      p_delivery_address    = $Address
      p_items               = $Items
      p_promo_code          = $null
      p_fulfillment_type    = 'delivery'
      p_customer_latitude   = $Latitude
      p_customer_longitude  = $Longitude
    }

  $orderId = "$orderId".Trim('"')

  Invoke-SupabaseJson `
    -Method 'PATCH' `
    -Uri "$SupabaseUrl/rest/v1/orders?id=eq.$orderId" `
    -Headers $ServiceHeaders `
    -Body @{
      status              = 'paid'
      payment_status      = 'paid'
      preparation_minutes = 25
      eta_minutes         = 45
      eta_updated_at      = (Get-Date).ToUniversalTime().ToString('o')
    } | Out-Null

  $orders = Invoke-SupabaseJson `
    -Method 'GET' `
    -Uri "$SupabaseUrl/rest/v1/orders?id=eq.$orderId&select=id,total_amount" `
    -Headers $ServiceHeaders
  $totalAmount = @($orders)[0].total_amount
  $reference = "$ReferencePrefix-$((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmssfff'))"

  Invoke-SupabaseJson `
    -Method 'POST' `
    -Uri "$SupabaseUrl/rest/v1/payments" `
    -Headers $ServiceHeaders `
    -Prefer 'return=minimal' `
    -Body @(
      @{
        order_id          = $orderId
        provider          = 'monnify'
        payment_reference = $reference
        amount            = $totalAmount
        status            = 'paid'
        raw_response      = @{
          source = 'seed-store-order-flow'
          note   = 'Seeded paid order for store app order acceptance testing.'
        }
      }
    ) | Out-Null

  Invoke-SupabaseJson `
    -Method 'POST' `
    -Uri "$SupabaseUrl/rest/v1/delivery_events" `
    -Headers $ServiceHeaders `
    -Prefer 'return=minimal' `
    -Body @(
      @{
        order_id = $orderId
        status   = 'paid'
        note     = 'Seeded paid order for acceptance testing'
      }
    ) | Out-Null

  return $orderId
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

$users = @(
  @{
    Email = 'blueplate.manager@luumoh.test'
    FullName = 'Blue Plate Manager'
    Phone = '+2348100001001'
    Role = 'store_admin'
  },
  @{
    Email = 'blueplate.staff@luumoh.test'
    FullName = 'Blue Plate Attendant'
    Phone = '+2348100001002'
    Role = 'store_admin'
  },
  @{
    Email = 'freshbasket.manager@luumoh.test'
    FullName = 'Fresh Basket Manager'
    Phone = '+2348100002001'
    Role = 'store_admin'
  },
  @{
    Email = 'freshbasket.staff@luumoh.test'
    FullName = 'Fresh Basket Attendant'
    Phone = '+2348100002002'
    Role = 'store_admin'
  },
  @{
    Email = 'customer.orderflow@luumoh.test'
    FullName = 'Order Flow Customer'
    Phone = '+2348100003001'
    Role = 'customer'
  }
)

$userIds = @{}
foreach ($user in $users) {
  $userIds[$user.Email] = New-OrUpdateAuthUser `
    -SupabaseUrl $supabaseUrl `
    -ServiceHeaders $serviceHeaders `
    -Email $user.Email `
    -Password $Password `
    -FullName $user.FullName `
    -Phone $user.Phone `
    -Role $user.Role
}

$blueStoreId = '77777777-7777-7777-7777-777777777781'
$freshStoreId = '77777777-7777-7777-7777-777777777782'

Upsert-Rows `
  -SupabaseUrl $supabaseUrl `
  -ServiceHeaders $serviceHeaders `
  -Table 'stores' `
  -Conflict 'id' `
  -Rows @(
    @{
      id = $blueStoreId
      owner_id = $userIds['blueplate.manager@luumoh.test']
      name = 'Blue Plate Kitchen'
      category = 'african_cuisine'
      address = '32 Admiralty Way, Lekki Phase 1, Lagos'
      is_active = $true
      is_open = $true
      latitude = 6.4474
      longitude = 3.4723
      busy_until = $null
      closed_until = $null
    },
    @{
      id = $freshStoreId
      owner_id = $userIds['freshbasket.manager@luumoh.test']
      name = 'Fresh Basket Market'
      category = 'grocery'
      address = '18 Awolowo Road, Ikoyi, Lagos'
      is_active = $true
      is_open = $true
      latitude = 6.4528
      longitude = 3.4337
      busy_until = $null
      closed_until = $null
    }
  )

Upsert-Rows `
  -SupabaseUrl $supabaseUrl `
  -ServiceHeaders $serviceHeaders `
  -Table 'store_members' `
  -Conflict 'store_id,user_id' `
  -Rows @(
    @{
      store_id = $blueStoreId
      user_id = $userIds['blueplate.manager@luumoh.test']
      can_manage_inventory = $true
      can_manage_orders = $true
    },
    @{
      store_id = $blueStoreId
      user_id = $userIds['blueplate.staff@luumoh.test']
      can_manage_inventory = $true
      can_manage_orders = $true
    },
    @{
      store_id = $freshStoreId
      user_id = $userIds['freshbasket.manager@luumoh.test']
      can_manage_inventory = $true
      can_manage_orders = $true
    },
    @{
      store_id = $freshStoreId
      user_id = $userIds['freshbasket.staff@luumoh.test']
      can_manage_inventory = $true
      can_manage_orders = $true
    }
  )

$blueProducts = @(
  @{
    id = '88888888-8888-8888-8888-888888888891'
    store_id = $blueStoreId
    name = 'Jollof Rice Bowl'
    description = 'Smoky party jollof rice with grilled chicken and fried plantain.'
    price = 4500
    category = 'african_cuisine'
    image_url = 'https://images.unsplash.com/photo-1604329760661-e71dc83f8f26?auto=format&fit=crop&w=900&q=80'
    is_available = $true
    unavailable_until = $null
  },
  @{
    id = '88888888-8888-8888-8888-888888888892'
    store_id = $blueStoreId
    name = 'Suya Chicken Wrap'
    description = 'Spiced suya chicken, vegetables, and creamy pepper sauce in a warm wrap.'
    price = 3600
    category = 'fast_food'
    image_url = 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?auto=format&fit=crop&w=900&q=80'
    is_available = $true
    unavailable_until = $null
  },
  @{
    id = '88888888-8888-8888-8888-888888888893'
    store_id = $blueStoreId
    name = 'Plantain and Beans'
    description = 'Honey beans porridge with sweet fried plantain and pepper relish.'
    price = 3200
    category = 'african_cuisine'
    image_url = $null
    is_available = $true
    unavailable_until = $null
  },
  @{
    id = '88888888-8888-8888-8888-888888888894'
    store_id = $blueStoreId
    name = 'Zobo Cooler'
    description = 'Chilled hibiscus drink with ginger and pineapple notes.'
    price = 1200
    category = 'coffee_and_tea'
    image_url = $null
    is_available = $true
    unavailable_until = $null
  }
)

$freshProducts = @(
  @{
    id = '88888888-8888-8888-8888-888888888895'
    store_id = $freshStoreId
    name = 'Bottled Water Pack'
    description = 'Twelve 75cl bottles for home, office, or pickup orders.'
    price = 2400
    category = 'convenience'
    image_url = $null
    is_available = $true
    unavailable_until = $null
  },
  @{
    id = '88888888-8888-8888-8888-888888888896'
    store_id = $freshStoreId
    name = 'Rice 5kg'
    description = 'Premium long grain rice packed fresh from market stock.'
    price = 9800
    category = 'grocery'
    image_url = 'https://images.unsplash.com/photo-1586201375761-83865001e31c?auto=format&fit=crop&w=900&q=80'
    is_available = $true
    unavailable_until = $null
  },
  @{
    id = '88888888-8888-8888-8888-888888888897'
    store_id = $freshStoreId
    name = 'Eggs Crate'
    description = 'Thirty fresh eggs packed for safe delivery.'
    price = 6200
    category = 'grocery'
    image_url = 'https://images.unsplash.com/photo-1506976785307-8732e854ad03?auto=format&fit=crop&w=900&q=80'
    is_available = $true
    unavailable_until = $null
  },
  @{
    id = '88888888-8888-8888-8888-888888888898'
    store_id = $freshStoreId
    name = 'Fresh Tomatoes Basket'
    description = 'Ripe tomatoes packed for stews, sauces, and bulk kitchen prep.'
    price = 5000
    category = 'grocery'
    image_url = 'https://images.unsplash.com/photo-1592924357228-91a4daadcfea?auto=format&fit=crop&w=900&q=80'
    is_available = $true
    unavailable_until = $null
  }
)

Upsert-Rows `
  -SupabaseUrl $supabaseUrl `
  -ServiceHeaders $serviceHeaders `
  -Table 'products' `
  -Conflict 'id' `
  -Rows @($blueProducts + $freshProducts)

Upsert-Rows `
  -SupabaseUrl $supabaseUrl `
  -ServiceHeaders $serviceHeaders `
  -Table 'inventory_items' `
  -Conflict 'product_id' `
  -Rows @(
    @{ product_id = '88888888-8888-8888-8888-888888888891'; sku = 'BLUE-JOLLOF-BOWL'; quantity_on_hand = 60; reorder_level = 12 },
    @{ product_id = '88888888-8888-8888-8888-888888888892'; sku = 'BLUE-SUYA-WRAP'; quantity_on_hand = 45; reorder_level = 10 },
    @{ product_id = '88888888-8888-8888-8888-888888888893'; sku = 'BLUE-BEANS-PLANTAIN'; quantity_on_hand = 35; reorder_level = 8 },
    @{ product_id = '88888888-8888-8888-8888-888888888894'; sku = 'BLUE-ZOBO-COOLER'; quantity_on_hand = 80; reorder_level = 15 },
    @{ product_id = '88888888-8888-8888-8888-888888888895'; sku = 'FRESH-WATER-12PK'; quantity_on_hand = 90; reorder_level = 20 },
    @{ product_id = '88888888-8888-8888-8888-888888888896'; sku = 'FRESH-RICE-5KG'; quantity_on_hand = 40; reorder_level = 8 },
    @{ product_id = '88888888-8888-8888-8888-888888888897'; sku = 'FRESH-EGGS-CRATE'; quantity_on_hand = 55; reorder_level = 10 },
    @{ product_id = '88888888-8888-8888-8888-888888888898'; sku = 'FRESH-TOMATO-BASKET'; quantity_on_hand = 50; reorder_level = 10 }
  )

$openingRows = @()
foreach ($storeId in @($blueStoreId, $freshStoreId)) {
  foreach ($day in 0..6) {
    $openingRows += @{
      store_id = $storeId
      day_of_week = $day
      opens_at = '00:00:00'
      closes_at = '23:59:59'
      is_closed = $false
    }
  }
}

Upsert-Rows `
  -SupabaseUrl $supabaseUrl `
  -ServiceHeaders $serviceHeaders `
  -Table 'store_opening_hours' `
  -Conflict 'store_id,day_of_week' `
  -Rows $openingRows

$createdOrders = @()
if (!$SkipOrders) {
  $customerSession = Sign-In `
    -SupabaseUrl $supabaseUrl `
    -PublishableKey $publishableKey `
    -Email 'customer.orderflow@luumoh.test' `
    -Password $Password

  $createdOrders += New-PaidOrder `
    -SupabaseUrl $supabaseUrl `
    -PublishableKey $publishableKey `
    -ServiceHeaders $serviceHeaders `
    -CustomerToken $customerSession.access_token `
    -StoreId $blueStoreId `
    -Items @(
      @{ product_id = '88888888-8888-8888-8888-888888888891'; quantity = 1 },
      @{ product_id = '88888888-8888-8888-8888-888888888894'; quantity = 2 }
    ) `
    -Address 'Order Flow Test Address, Victoria Island, Lagos' `
    -Latitude 6.4281 `
    -Longitude 3.4219 `
    -ReferencePrefix 'SEED-BLUE'

  $createdOrders += New-PaidOrder `
    -SupabaseUrl $supabaseUrl `
    -PublishableKey $publishableKey `
    -ServiceHeaders $serviceHeaders `
    -CustomerToken $customerSession.access_token `
    -StoreId $freshStoreId `
    -Items @(
      @{ product_id = '88888888-8888-8888-8888-888888888895'; quantity = 1 },
      @{ product_id = '88888888-8888-8888-8888-888888888897'; quantity = 1 }
    ) `
    -Address 'Order Flow Test Address, Lekki Phase 1, Lagos' `
    -Latitude 6.4460 `
    -Longitude 3.4695 `
    -ReferencePrefix 'SEED-FRESH'
}

Write-Host ''
Write-Host 'Store order-flow seed complete.'
Write-Host ''
Write-Host 'Test logins:'
@(
  [pscustomobject]@{ role = 'store manager'; email = 'blueplate.manager@luumoh.test'; password = $Password; store = 'Blue Plate Kitchen' },
  [pscustomobject]@{ role = 'store staff'; email = 'blueplate.staff@luumoh.test'; password = $Password; store = 'Blue Plate Kitchen' },
  [pscustomobject]@{ role = 'store manager'; email = 'freshbasket.manager@luumoh.test'; password = $Password; store = 'Fresh Basket Market' },
  [pscustomobject]@{ role = 'store staff'; email = 'freshbasket.staff@luumoh.test'; password = $Password; store = 'Fresh Basket Market' },
  [pscustomobject]@{ role = 'customer'; email = 'customer.orderflow@luumoh.test'; password = $Password; store = '-' }
) | Format-Table -AutoSize

if ($createdOrders.Count -gt 0) {
  Write-Host 'Seeded paid order IDs for New order testing:'
  $createdOrders | ForEach-Object { Write-Host "  $_" }
}
