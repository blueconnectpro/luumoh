$ErrorActionPreference = "Stop"

function Read-DotEnv {
  param([string]$Path)

  $values = @{}
  if (-not (Test-Path $Path)) {
    return ,$values
  }

  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith("#")) {
      return
    }

    $parts = $line.Split("=", 2)
    if ($parts.Length -ne 2) {
      return
    }

    $values[$parts[0].Trim()] = $parts[1].Trim().Trim('"').Trim("'")
  }

  return ,$values
}

$envValues = Read-DotEnv ".env"
$supabaseUrl = [string]$envValues["SUPABASE_URL"]
$publishableKey = [string]$envValues["SUPABASE_PUBLISHABLE_KEY"]

if (-not $supabaseUrl -or -not $publishableKey) {
  throw "SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required in .env."
}

$functionBaseUrl = "$($supabaseUrl.TrimEnd('/'))/functions/v1"

function Test-FunctionEndpoint {
  param(
    [string]$Name,
    [string]$Method = 'Options',
    [int[]]$ExpectedStatusCodes,
    [hashtable]$Headers = @{},
    [object]$Body = $null,
    [string]$ExpectedContent = $null
  )

  $params = @{
    Uri             = "$functionBaseUrl/$Name"
    Method          = $Method
    Headers         = $Headers
    UseBasicParsing = $true
    TimeoutSec      = 20
  }

  if ($null -ne $Body) {
    $params.ContentType = 'application/json'
    $params.Body = ($Body | ConvertTo-Json -Depth 8)
  }

  try {
    $response = Invoke-WebRequest @params
    $statusCode = [int]$response.StatusCode
    $content = [string]$response.Content
  } catch {
    $response = $_.Exception.Response
    $statusCode = if ($response) { [int]$response.StatusCode } else { 0 }
    $content = ''
  }

  if ($ExpectedStatusCodes -notcontains $statusCode) {
    throw "$Name health check failed. Expected $($ExpectedStatusCodes -join ', '), got $statusCode for $Method."
  }

  if ($ExpectedContent -and $content -notmatch [regex]::Escape($ExpectedContent)) {
    throw "$Name health check failed. Response did not contain expected content '$ExpectedContent'."
  }

  Write-Host "$Name $Method responded with expected status $statusCode."
}

Test-FunctionEndpoint `
  -Name "monnify-initiate" `
  -Method "Post" `
  -ExpectedStatusCodes @(401) `
  -Headers @{ Authorization = "Bearer invalid-smoke-token"; apikey = $publishableKey } `
  -Body @{ orderId = "00000000-0000-0000-0000-000000000000" }

Test-FunctionEndpoint `
  -Name "monnify-confirm" `
  -Method "Post" `
  -ExpectedStatusCodes @(401) `
  -Headers @{ Authorization = "Bearer invalid-smoke-token"; apikey = $publishableKey } `
  -Body @{ paymentReference = "luumoh-smoke-health" }

Test-FunctionEndpoint `
  -Name "monnify-webhook" `
  -Method "Options" `
  -ExpectedStatusCodes @(200)

Test-FunctionEndpoint `
  -Name "monnify-return" `
  -Method "Get" `
  -ExpectedStatusCodes @(200) `
  -ExpectedContent "luumoh://payment-return"

Test-FunctionEndpoint `
  -Name "admin-upsert-user" `
  -Method "Post" `
  -ExpectedStatusCodes @(401) `
  -Headers @{ Authorization = "Bearer invalid-smoke-token"; apikey = $publishableKey } `
  -Body @{ email = "health@luumoh.test"; role = "customer"; fullName = "Health Check" }

Write-Host "Cloud health checks passed."
