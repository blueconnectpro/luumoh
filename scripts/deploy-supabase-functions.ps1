param(
  [string]$CliVersion = "2.26.9",
  [switch]$SkipSecrets
)

$ErrorActionPreference = "Stop"

function Read-DotEnv {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return
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

    $name = $parts[0].Trim()
    $value = $parts[1].Trim().Trim('"').Trim("'")
    if ($name -and -not [Environment]::GetEnvironmentVariable($name, "Process")) {
      [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
  }
}

function Invoke-NpxSupabase {
  param([string[]]$Arguments)

  function Invoke-Npx {
    param([string[]]$CommandArgs)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      $result = & npx @CommandArgs 2>&1
      $code = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorActionPreference
    }

    return @{
      Output = $result
      ExitCode = $code
    }
  }

  $run = Invoke-Npx $Arguments
  $output = $run.Output
  $exitCode = $run.ExitCode

  $outputText = $output | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) {
      $_.Exception.Message
    } else {
      $_.ToString()
    }
  }
  $outputText | ForEach-Object { Write-Host $_ }

  if (
    ($exitCode -ne 0 -or ($outputText -match "Error|Failed|failed|Cannot|invalid|Try rerunning")) -and
    ($outputText -match "dns-query|context deadline exceeded") -and
    ($Arguments -contains "--dns-resolver")
  ) {
    Write-Host "Supabase DNS-over-HTTPS failed. Retrying with system DNS..."
    $fallbackArgs = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Arguments.Length; $i++) {
      if ($Arguments[$i] -eq "--dns-resolver") {
        $i++
        continue
      }
      $fallbackArgs.Add($Arguments[$i])
    }

    $run = Invoke-Npx $fallbackArgs.ToArray()
    $output = $run.Output
    $exitCode = $run.ExitCode
    $outputText = $output | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) {
        $_.Exception.Message
      } else {
        $_.ToString()
      }
    }
    $outputText | ForEach-Object { Write-Host $_ }
  }

  if ($exitCode -ne 0 -or ($outputText -match "Error|Failed|failed|Cannot|invalid|Try rerunning")) {
    throw "Supabase command failed. Review the output above for the CLI error."
  }
}

Read-DotEnv ".env"

$required = @(
  "SUPABASE_PROJECT_REF",
  "SUPABASE_ACCESS_TOKEN"
)

if (-not $SkipSecrets) {
  $required += @(
  "MONNIFY_BASE_URL",
  "MONNIFY_API_KEY",
  "MONNIFY_SECRET_KEY",
  "MONNIFY_CONTRACT_CODE",
  "MONNIFY_REDIRECT_URL",
  "MONNIFY_APP_RETURN_URL"
  )
}

foreach ($name in $required) {
  if (-not [Environment]::GetEnvironmentVariable($name, "Process")) {
    throw "$name is required in .env or the current shell."
  }
}

$tempDir = Join-Path "supabase" ".temp"
if (-not (Test-Path $tempDir)) {
  New-Item -ItemType Directory -Path $tempDir | Out-Null
}

Set-Content -Path (Join-Path $tempDir "project-ref") -Value $env:SUPABASE_PROJECT_REF -NoNewline

if (-not $SkipSecrets) {
  $secretArgs = @(
    "supabase@$CliVersion",
    "--dns-resolver",
    "https",
    "secrets",
    "set",
    "--project-ref",
    $env:SUPABASE_PROJECT_REF,
    "MONNIFY_BASE_URL=$env:MONNIFY_BASE_URL",
    "MONNIFY_API_KEY=$env:MONNIFY_API_KEY",
    "MONNIFY_SECRET_KEY=$env:MONNIFY_SECRET_KEY",
    "MONNIFY_CONTRACT_CODE=$env:MONNIFY_CONTRACT_CODE",
    "MONNIFY_REDIRECT_URL=$env:MONNIFY_REDIRECT_URL",
    "MONNIFY_APP_RETURN_URL=$env:MONNIFY_APP_RETURN_URL"
  )

  Write-Host "Setting Edge Function secrets..."
  Invoke-NpxSupabase $secretArgs
} else {
  Write-Host "Skipping Edge Function secret updates; deploying function source only."
}

Write-Host "Deploying monnify-initiate..."
Invoke-NpxSupabase @(
  "supabase@$CliVersion",
  "--dns-resolver",
  "https",
  "functions",
  "deploy",
  "monnify-initiate",
  "--project-ref",
  $env:SUPABASE_PROJECT_REF
)

Write-Host "Deploying monnify-confirm..."
Invoke-NpxSupabase @(
  "supabase@$CliVersion",
  "--dns-resolver",
  "https",
  "functions",
  "deploy",
  "monnify-confirm",
  "--project-ref",
  $env:SUPABASE_PROJECT_REF
)

Write-Host "Deploying monnify-webhook..."
Invoke-NpxSupabase @(
  "supabase@$CliVersion",
  "--dns-resolver",
  "https",
  "functions",
  "deploy",
  "monnify-webhook",
  "--project-ref",
  $env:SUPABASE_PROJECT_REF,
  "--no-verify-jwt"
)

Write-Host "Deploying monnify-return..."
Invoke-NpxSupabase @(
  "supabase@$CliVersion",
  "--dns-resolver",
  "https",
  "functions",
  "deploy",
  "monnify-return",
  "--project-ref",
  $env:SUPABASE_PROJECT_REF,
  "--no-verify-jwt"
)

Write-Host "Deploying admin-upsert-user..."
Invoke-NpxSupabase @(
  "supabase@$CliVersion",
  "--dns-resolver",
  "https",
  "functions",
  "deploy",
  "admin-upsert-user",
  "--project-ref",
  $env:SUPABASE_PROJECT_REF
)

Write-Host "Supabase Edge Functions deployed."
