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

function Escape-DartString {
  param([string]$Value)
  return $Value.Replace("\", "\\").Replace("'", "\'")
}

function Normalize-SupabaseUrl {
  param([string]$Value)

  $trimmed = $Value.Trim().Trim('"').Trim("'")
  $match = [regex]::Match($trimmed, "https://[^\s/]+")
  if ($match.Success) {
    return $match.Value.TrimEnd("/")
  }

  return $trimmed.TrimEnd("/")
}

$envValues = Read-DotEnv ".env"
$supabaseUrl = Escape-DartString (Normalize-SupabaseUrl ([string]$envValues["SUPABASE_URL"]))
$publishableKey = Escape-DartString ([string]$envValues["SUPABASE_PUBLISHABLE_KEY"])
$storeId = Escape-DartString ([string]$envValues["STORE_ID"])
$mapboxAccessToken = Escape-DartString ([string]$envValues["MAPBOX_ACCESS_TOKEN"])

if (-not $supabaseUrl -or -not $publishableKey) {
  throw "SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required in .env."
}

$content = @"
class LocalEnv {
  static const supabaseUrl = '$supabaseUrl';
  static const supabasePublishableKey = '$publishableKey';
  static const storeId = '$storeId';
  static const mapboxAccessToken = '$mapboxAccessToken';
}
"@

Set-Content -Path "packages/luumoh_core/lib/src/config/local_env.dart" -Value $content -NoNewline
Write-Host "Updated packages/luumoh_core/lib/src/config/local_env.dart from .env."
