param(
  [switch]$RequireProduction
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

$envValues = Read-DotEnv '.env'
$supabaseUrl = ([string]$envValues['SUPABASE_URL']).Trim().TrimEnd('/')
$baseUrl = ([string]$envValues['MONNIFY_BASE_URL']).Trim().TrimEnd('/')
$apiKey = ([string]$envValues['MONNIFY_API_KEY']).Trim()
$secretKey = ([string]$envValues['MONNIFY_SECRET_KEY']).Trim()
$contractCode = ([string]$envValues['MONNIFY_CONTRACT_CODE']).Trim()
$redirectUrl = ([string]$envValues['MONNIFY_REDIRECT_URL']).Trim()
$appReturnUrl = ([string]$envValues['MONNIFY_APP_RETURN_URL']).Trim()

foreach ($pair in @{
  SUPABASE_URL           = $supabaseUrl
  MONNIFY_BASE_URL      = $baseUrl
  MONNIFY_API_KEY       = $apiKey
  MONNIFY_SECRET_KEY    = $secretKey
  MONNIFY_CONTRACT_CODE = $contractCode
  MONNIFY_REDIRECT_URL  = $redirectUrl
  MONNIFY_APP_RETURN_URL = $appReturnUrl
}.GetEnumerator()) {
  if (!$pair.Value -or $pair.Value -match '^your-|from-dashboard|server-side-only') {
    throw "$($pair.Key) is missing or still a placeholder."
  }
}

if ($supabaseUrl -notmatch '^https://[a-z0-9-]+\.supabase\.co$') {
  throw 'SUPABASE_URL must be a cloud Supabase URL like https://project-ref.supabase.co.'
}

try {
  [void][Uri]$baseUrl
} catch {
  throw "MONNIFY_BASE_URL is not a valid URL: $baseUrl"
}

if ($RequireProduction -and $baseUrl -match 'sandbox') {
  throw 'MONNIFY_BASE_URL points to sandbox. Use production Monnify base URL for production readiness.'
}

if ($redirectUrl -notmatch '^https?://') {
  Write-Warning "MONNIFY_REDIRECT_URL is '$redirectUrl'. Monnify requires HTTP(S); monnify-initiate will fall back to the hosted return page."
} else {
  $expectedRedirectUrl = "$supabaseUrl/functions/v1/monnify-return"
  if ($redirectUrl.TrimEnd('/') -ne $expectedRedirectUrl) {
    throw "MONNIFY_REDIRECT_URL must be $expectedRedirectUrl so hosted checkout can return to the app."
  }
}

if ($appReturnUrl -ne 'luumoh://payment-return') {
  throw "MONNIFY_APP_RETURN_URL must be luumoh://payment-return."
}

$basicToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$apiKey`:$secretKey"))
$response = Invoke-RestMethod `
  -Method 'POST' `
  -Uri "$baseUrl/api/v1/auth/login" `
  -Headers @{ Authorization = "Basic $basicToken" } `
  -ContentType 'application/json' `
  -TimeoutSec 30

$accessToken = $response.responseBody.accessToken
if (!$accessToken) {
  $response | ConvertTo-Json -Depth 8
  throw 'Monnify auth succeeded but no access token was returned.'
}

[pscustomobject]@{
  BaseUrl       = $baseUrl
  ContractCode = if ($contractCode.Length -le 4) { 'set' } else { "****$($contractCode.Substring($contractCode.Length - 4))" }
  RedirectUrl  = $redirectUrl
  AppReturnUrl = $appReturnUrl
  WebhookUrl   = "$supabaseUrl/functions/v1/monnify-webhook"
  Environment  = if ($baseUrl -match 'sandbox') { 'sandbox' } else { 'production_candidate' }
  Auth          = 'ok'
} | Format-List

Write-Host 'Monnify readiness check passed.'
