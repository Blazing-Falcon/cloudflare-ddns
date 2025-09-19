#requires -Version 5.1
param(
  [string]$ConfigPath = ".\cloudflare-ddns.json"
)

if (!(Test-Path $ConfigPath)) { Write-Error "Config not found: $ConfigPath"; exit 1 }
$config = Get-Content $ConfigPath | ConvertFrom-Json
$cacheFile = Join-Path (Split-Path $ConfigPath -Parent) "ip-cache.json"

$Headers = @{
  "Authorization" = "Bearer $($config.CF_API_TOKEN)"
  "Content-Type"  = "application/json"
}

function Get-PublicIP {
  param([switch]$IPv6)
  $urls = if ($IPv6) {
    @("https://api64.ipify.org","https://ifconfig.co")
  } else {
    @("https://api.ipify.org","https://ifconfig.me")
  }
  foreach ($u in $urls) {
    try {
      $ip = Invoke-RestMethod -Uri $u -UseBasicParsing -TimeoutSec 5
      if ($ip -match '^[0-9a-fA-F\.:]+$') { return $ip }
    } catch { }
  }
  throw "Unable to fetch public IP."
}

function Get-CachedIP {
  param([string]$recordName, [string]$recordType)
  
  if (Test-Path $cacheFile) {
    try {
      $cache = Get-Content $cacheFile | ConvertFrom-Json
      $key = "$recordName-$recordType"
      if ($cache.PSObject.Properties.Name -contains $key) {
        return $cache.$key
      }
    } catch {
      Write-Host "Warning: Failed to read cache file"
    }
  }
  return $null
}

function Set-CachedIP {
  param([string]$recordName, [string]$recordType, [string]$ip)
  
  $cache = @{}
  if (Test-Path $cacheFile) {
    try {
      $cache = Get-Content $cacheFile | ConvertFrom-Json -AsHashtable
    } catch {
      Write-Host "Warning: Failed to read existing cache, creating new one"
      $cache = @{}
    }
  }
  
  $key = "$recordName-$recordType"
  $cache[$key] = $ip
  
  try {
    $cache | ConvertTo-Json | Set-Content $cacheFile
  } catch {
    Write-Host "Warning: Failed to write cache file"
  }
}

$ipv6 = ($config.CF_RECORD_TYPE -eq "AAAA")
$curIP = Get-PublicIP -IPv6:$ipv6

$cachedIP = Get-CachedIP -recordName $config.CF_RECORD_NAME -recordType $config.CF_RECORD_TYPE
if ($cachedIP -eq $curIP) {
  Write-Host "IP unchanged ($curIP), skipping update for $($config.CF_RECORD_NAME)"
  exit 0
}

Write-Host "IP changed from [$cachedIP] to [$curIP] for $($config.CF_RECORD_NAME)"

# 1) Get Zone ID
$zoneResp = Invoke-RestMethod -Method GET -Uri "https://api.cloudflare.com/client/v4/zones?name=$($config.CF_ZONE_NAME)" -Headers $Headers
$zoneId = $zoneResp.result[0].id
if (-not $zoneId) { throw "Failed to get Zone ID for $($config.CF_ZONE_NAME)" }

# 2) Lookup existing record
$recUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?type=$($config.CF_RECORD_TYPE)&name=$($config.CF_RECORD_NAME)"
$recResp = Invoke-RestMethod -Method GET -Uri $recUri -Headers $Headers
$record = $recResp.result | Select-Object -First 1

if (-not $record) {
  Write-Host "Record not found; creating $($config.CF_RECORD_TYPE) $($config.CF_RECORD_NAME) -> $curIP"
  $payload = @{
    type    = $config.CF_RECORD_TYPE
    name    = $config.CF_RECORD_NAME
    content = $curIP
    proxied = [bool]$config.CF_PROXIED
    ttl     = [int]$config.CF_TTL
  } | ConvertTo-Json
  $createUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records"
  $createResp = Invoke-RestMethod -Method POST -Uri $createUri -Headers $Headers -Body $payload
  $ok = $createResp.success
} else {
  Write-Host "Updating $($config.CF_RECORD_NAME) from $($record.content) -> $curIP"
  $payload = @{
    type    = $config.CF_RECORD_TYPE
    name    = $config.CF_RECORD_NAME
    content = $curIP
    proxied = [bool]$config.CF_PROXIED
    ttl     = [int]$config.CF_TTL
  } | ConvertTo-Json
  $updateUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$($record.id)"
  $updateResp = Invoke-RestMethod -Method PUT -Uri $updateUri -Headers $Headers -Body $payload
  $ok = $updateResp.success
}

if ($ok) {
  Write-Host "Done."
  Set-CachedIP -recordName $config.CF_RECORD_NAME -recordType $config.CF_RECORD_TYPE -ip $curIP
} else {
  throw "API call failed."
}