param(
  [string]$AdminEmail = 'admin.onboarding@luumoh.test',
  [string]$StoreEmail = 'store.onboarding@luumoh.test',
  [string]$RiderEmail = 'rider.onboarding@luumoh.test',
  [string]$Password = 'Password123!',
  [string]$StoreId = '77777777-7777-7777-7777-777777777771'
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

  return Invoke-RestMethod @params
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

function Ensure-Test-Admin {
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
          full_name = 'Onboarding Smoke Admin'
          phone     = '+2348000000944'
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
          full_name = 'Onboarding Smoke Admin'
          phone     = '+2348000000944'
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
        role      = 'admin'
        full_name = 'Onboarding Smoke Admin'
        phone     = '+2348000000944'
      }
    ) | Out-Null

  return $userId
}

function Invoke-AdminUpsertUser {
  param(
    [string]$SupabaseUrl,
    [string]$PublishableKey,
    [string]$AccessToken,
    [hashtable]$Body
  )

  return Invoke-SupabaseJson `
    -Method 'POST' `
    -Uri "$SupabaseUrl/functions/v1/admin-upsert-user" `
    -Headers @{
      apikey        = $PublishableKey
      Authorization = "Bearer $AccessToken"
    } `
    -Body $Body
}

function Get-Profile {
  param(
    [string]$SupabaseUrl,
    [hashtable]$ServiceHeaders,
    [string]$UserId
  )

  $rows = Invoke-SupabaseJson `
    -Method 'GET' `
    -Uri "$SupabaseUrl/rest/v1/profiles?id=eq.$UserId&select=id,role,full_name,phone" `
    -Headers $ServiceHeaders

  if (@($rows).Count -ne 1) {
    throw "Profile $UserId was not found."
  }

  return @($rows)[0]
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

$adminId = Ensure-Test-Admin `
  -SupabaseUrl $supabaseUrl `
  -ServiceHeaders $serviceHeaders `
  -Email $AdminEmail `
  -Password $Password

$adminSession = Sign-In `
  -SupabaseUrl $supabaseUrl `
  -PublishableKey $publishableKey `
  -Email $AdminEmail `
  -Password $Password

$storeUser = Invoke-AdminUpsertUser `
  -SupabaseUrl $supabaseUrl `
  -PublishableKey $publishableKey `
  -AccessToken $adminSession.access_token `
  -Body @{
    email                = $StoreEmail
    password             = $Password
    role                 = 'store_admin'
    fullName             = 'Onboarding Smoke Store Staff'
    phone                = '+2348000000955'
    storeId              = $StoreId
    canManageInventory   = $true
    canManageOrders      = $true
  }

$riderUser = Invoke-AdminUpsertUser `
  -SupabaseUrl $supabaseUrl `
  -PublishableKey $publishableKey `
  -AccessToken $adminSession.access_token `
  -Body @{
    email    = $RiderEmail
    password = $Password
    role     = 'rider'
    fullName = 'Onboarding Smoke Rider'
    phone    = '+2348000000966'
  }

$storeProfile = Get-Profile -SupabaseUrl $supabaseUrl -ServiceHeaders $serviceHeaders -UserId $storeUser.userId
$riderProfile = Get-Profile -SupabaseUrl $supabaseUrl -ServiceHeaders $serviceHeaders -UserId $riderUser.userId

if ($storeProfile.role -ne 'store_admin') {
  throw "Expected store staff role store_admin, got $($storeProfile.role)."
}

if ($riderProfile.role -ne 'rider') {
  throw "Expected rider role rider, got $($riderProfile.role)."
}

$members = Invoke-SupabaseJson `
  -Method 'GET' `
  -Uri "$supabaseUrl/rest/v1/store_members?store_id=eq.$StoreId&user_id=eq.$($storeUser.userId)&select=store_id,user_id,can_manage_inventory,can_manage_orders" `
  -Headers $serviceHeaders

if (@($members).Count -ne 1) {
  throw 'Store staff membership was not created.'
}

$member = @($members)[0]
if (!$member.can_manage_inventory -or !$member.can_manage_orders) {
  throw 'Store staff permissions were not created correctly.'
}

Sign-In -SupabaseUrl $supabaseUrl -PublishableKey $publishableKey -Email $StoreEmail -Password $Password | Out-Null
Sign-In -SupabaseUrl $supabaseUrl -PublishableKey $publishableKey -Email $RiderEmail -Password $Password | Out-Null

@(
  [pscustomobject]@{
    kind  = 'admin'
    email = $AdminEmail
    id    = $adminId
  }
  [pscustomobject]@{
    kind  = 'store_admin'
    email = $StoreEmail
    id    = $storeUser.userId
  }
  [pscustomobject]@{
    kind  = 'rider'
    email = $RiderEmail
    id    = $riderUser.userId
  }
) | Format-Table -AutoSize

Write-Host 'Admin onboarding smoke test passed.'
