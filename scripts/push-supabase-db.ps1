param(
  [string]$CliVersion = "2.26.9"
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

Read-DotEnv ".env"

if (-not $env:SUPABASE_PROJECT_REF) {
  throw "SUPABASE_PROJECT_REF is required in .env or the current shell."
}

if (-not $env:SUPABASE_ACCESS_TOKEN) {
  throw "SUPABASE_ACCESS_TOKEN is required in .env or the current shell."
}

$tempDir = Join-Path "supabase" ".temp"
if (-not (Test-Path $tempDir)) {
  New-Item -ItemType Directory -Path $tempDir | Out-Null
}

Set-Content -Path (Join-Path $tempDir "project-ref") -Value $env:SUPABASE_PROJECT_REF -NoNewline

$command = @("supabase@$CliVersion", "db", "push", "--linked")

if ($env:SUPABASE_DB_PASSWORD) {
  $command += @("--password", $env:SUPABASE_DB_PASSWORD)
} else {
  Write-Host "SUPABASE_DB_PASSWORD is not set. The Supabase CLI will prompt for the database password."
}

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
  $output = & npx @command 2>&1
  $exitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousErrorActionPreference
}

$outputText = $output | ForEach-Object {
  if ($_ -is [System.Management.Automation.ErrorRecord]) {
    $_.Exception.Message
  } else {
    $_.ToString()
  }
}
$outputText | ForEach-Object { Write-Host $_ }

if ($exitCode -ne 0 -or ($outputText -match "failed to connect|password authentication failed|unknown flag|Try rerunning")) {
  throw "Supabase db push failed. Check SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF, and especially SUPABASE_DB_PASSWORD."
}
