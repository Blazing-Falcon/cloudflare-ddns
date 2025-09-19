# Cloudflare Dynamic DNS Updater

A PowerShell script that automatically updates a Cloudflare DNS record with your current public IP address.

## Features

- Supports both IPv4 (A) and IPv6 (AAAA) records
- Automatically creates DNS records if they don't exist
- Updates existing records with current public IP
- Configurable via JSON file
- Multiple IP detection services for reliability

## TODO
- Update multiple records

## Setup

1. **Get Cloudflare API Token**
   - Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
   - Create a token with `Zone:Zone:Read` and `Zone:DNS:Edit` permissions for your domain

2. **Configure the script**
   - Copy `cloudflare-ddns.json` and update with your settings:
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

To run automatically, set up a scheduled task:

## Configuration Options

| Field | Description | Example |
|-------|-------------|---------|
| `CF_API_TOKEN` | Cloudflare API token | `your-token-here` |
| `CF_ZONE_NAME` | Your domain name | `example.com` |
| `CF_RECORD_NAME` | Full DNS record name | `home.example.com` |
| `CF_RECORD_TYPE` | Record type (A for IPv4, AAAA for IPv6) | `A` |
| `CF_PROXIED` | Enable Cloudflare proxy | `false` |
| `CF_TTL` | Time to live in seconds | `300` |

## Requirements

- PowerShell 5.1 or later
- Internet connection
- Valid Cloudflare API token