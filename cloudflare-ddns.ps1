#requires -Version 5.1
param(
  [string]$ConfigPath = ".\config.json"
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
      $existingCache = Get-Content $cacheFile | ConvertFrom-Json
      $existingCache.PSObject.Properties | ForEach-Object {
        $cache[$_.Name] = $_.Value
      }
    } catch {
      Write-Host "Warning: Failed to read existing cache, creating new one"
      $cache = @{}
    }
  }
  
  $key = "$recordName-$recordType"
  $cache[$key] = $ip
  
  try {
    $cacheObject = New-Object PSObject
    $cache.Keys | ForEach-Object {
      $cacheObject | Add-Member -MemberType NoteProperty -Name $_ -Value $cache[$_]
    }
    $cacheObject | ConvertTo-Json | Set-Content $cacheFile
  } catch {
    Write-Host "Warning: Failed to write cache file"
  }
}

function Update-DNSRecord {
  param(
    [object]$record,
    [string]$zoneId,
    [string]$currentIP
  )
  
  $cachedIP = Get-CachedIP -recordName $record.CF_RECORD_NAME -recordType $record.CF_RECORD_TYPE
  if ($cachedIP -eq $currentIP) {
    Write-Host "IP unchanged ($currentIP), skipping update for $($record.CF_RECORD_NAME)"
    return $true
  }

  Write-Host "IP changed from [$cachedIP] to [$currentIP] for $($record.CF_RECORD_NAME)"

  # Lookup existing record
  $recUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?type=$($record.CF_RECORD_TYPE)&name=$($record.CF_RECORD_NAME)"
  $recResp = Invoke-RestMethod -Method GET -Uri $recUri -Headers $Headers
  $existingRecord = $recResp.result | Select-Object -First 1

  $payload = @{
    type    = $record.CF_RECORD_TYPE
    name    = $record.CF_RECORD_NAME
    content = $currentIP
    proxied = [bool]$record.CF_PROXIED
    ttl     = [int]$record.CF_TTL
  } | ConvertTo-Json

  if (-not $existingRecord) {
    Write-Host "Record not found; creating $($record.CF_RECORD_TYPE) $($record.CF_RECORD_NAME) -> $currentIP"
    $createUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records"
    $createResp = Invoke-RestMethod -Method POST -Uri $createUri -Headers $Headers -Body $payload
    $success = $createResp.success
  } else {
    Write-Host "Updating $($record.CF_RECORD_NAME) from $($existingRecord.content) -> $currentIP"
    $updateUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$($existingRecord.id)"
    $updateResp = Invoke-RestMethod -Method PUT -Uri $updateUri -Headers $Headers -Body $payload
    $success = $updateResp.success
  }

  if ($success) {
    Write-Host "Successfully updated $($record.CF_RECORD_NAME)"
    Set-CachedIP -recordName $record.CF_RECORD_NAME -recordType $record.CF_RECORD_TYPE -ip $currentIP
    return $true
  } else {
    Write-Error "Failed to update $($record.CF_RECORD_NAME)"
    return $false
  }
}

# Get Zone ID
$zoneResp = Invoke-RestMethod -Method GET -Uri "https://api.cloudflare.com/client/v4/zones?name=$($config.CF_ZONE_NAME)" -Headers $Headers
$zoneId = $zoneResp.result[0].id
if (-not $zoneId) { throw "Failed to get Zone ID for $($config.CF_ZONE_NAME)" }

# Check if config uses single record format (backward compatibility)
if ($config.CF_RECORD_NAME) {
  Write-Host "Processing single record: $($config.CF_RECORD_NAME)"
  $ipv6 = ($config.CF_RECORD_TYPE -eq "AAAA")
  $curIP = Get-PublicIP -IPv6:$ipv6
  $success = Update-DNSRecord -record $config -zoneId $zoneId -currentIP $curIP
  if (-not $success) { exit 1 }
} elseif ($config.CF_RECORDS) {
  Write-Host "Processing multiple records: $($config.CF_RECORDS.Count) record(s)"
  $ipv4 = $null
  $ipv6 = $null
  $allSuccess = $true
  
  foreach ($record in $config.CF_RECORDS) {
    Write-Host "`nProcessing record: $($record.CF_RECORD_NAME) ($($record.CF_RECORD_TYPE))"
    
    if ($record.CF_RECORD_TYPE -eq "AAAA") {
      if (-not $ipv6) { $ipv6 = Get-PublicIP -IPv6 }
      $currentIP = $ipv6
    } else {
      if (-not $ipv4) { $ipv4 = Get-PublicIP }
      $currentIP = $ipv4
    }
    
    $success = Update-DNSRecord -record $record -zoneId $zoneId -currentIP $currentIP
    if (-not $success) { $allSuccess = $false }
  }
  
  if (-not $allSuccess) { exit 1 }
} else {
  throw "Invalid config format. Must contain either CF_RECORD_NAME or CF_RECORDS array."
}

Write-Host "`nAll DNS records processed successfully."