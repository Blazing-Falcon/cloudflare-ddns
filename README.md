# Cloudflare Dynamic DNS Updater

A PowerShell script that automatically updates Cloudflare DNS records with your current public IP address.

## Features

- Supports both IPv4 (A) and IPv6 (AAAA) records
- Supports multiple DNS records in a single run
- Automatically creates DNS records if they don't exist
- Updates existing records with current public IP
- Configurable via JSON file
- Multiple IP detection services for reliability
- IP caching to avoid unnecessary updates

## Setup

1. **Get Cloudflare API Token**
   - Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
   - Create a token with `Zone:Zone:Read` and `Zone:DNS:Edit` permissions for your domain

2. **Configure the script**
   - Create a `config.json` file in the same directory as the script
   - Use the format from `cloudflare-ddns.json` as a template:

   **For multiple records (recommended):**
   ```json
   {
     "CF_API_TOKEN": "your-api-token-here",
     "CF_ZONE_NAME": "yourdomain.com",
     "CF_RECORDS": [
       {
         "CF_RECORD_NAME": "ssh.yourdomain.com",
         "CF_RECORD_TYPE": "A",
         "CF_PROXIED": false,
         "CF_TTL": 300
       },
       {
         "CF_RECORD_NAME": "home.yourdomain.com",
         "CF_RECORD_TYPE": "A",
         "CF_PROXIED": false,
         "CF_TTL": 300
       },
       {
         "CF_RECORD_NAME": "ipv6.yourdomain.com",
         "CF_RECORD_TYPE": "AAAA",
         "CF_PROXIED": false,
         "CF_TTL": 300
       }
     ]
   }
   ```

   **For single record (legacy format):**
   ```json
   {
     "CF_API_TOKEN": "your-api-token-here",
     "CF_ZONE_NAME": "yourdomain.com",
     "CF_RECORD_NAME": "subdomain.yourdomain.com",
     "CF_RECORD_TYPE": "A",
     "CF_PROXIED": false,
     "CF_TTL": 300
   }
   ```

## Usage

Run the script manually:
```powershell
.\cloudflare-ddns.ps1
```

Or specify a custom config path:
```powershell
.\cloudflare-ddns.ps1 -ConfigPath "C:\path\to\your\config.json"
```

## Automation

To run automatically, set up a scheduled task in Windows Task Scheduler to run the script at your desired interval (e.g., every 5 minutes).

## Configuration Options

| Field | Description | Example |
|-------|-------------|---------|
| `CF_API_TOKEN` | Cloudflare API token | `your-token-here` |
| `CF_ZONE_NAME` | Your domain name | `example.com` |
| `CF_RECORDS` | Array of DNS records (multiple records format) | See example above |
| `CF_RECORD_NAME` | Full DNS record name (single record format) | `home.example.com` |
| `CF_RECORD_TYPE` | Record type (A for IPv4, AAAA for IPv6) | `A` |
| `CF_PROXIED` | Enable Cloudflare proxy | `false` |
| `CF_TTL` | Time to live in seconds | `300` |

## Requirements

- PowerShell 5.1 or later
- Internet connection
- Valid Cloudflare API token

## Notes

- The script maintains an IP cache (`ip-cache.json`) to avoid unnecessary API calls when the IP hasn't changed
- IPv4 and IPv6 addresses are fetched only once per script run, even when updating multiple records
- The script supports both single record and multiple records configuration formats for backward compatibility