#Requires -Version 5.1
<#
.SYNOPSIS
    IONOS Dynamic DNS Updater for Windows

.DESCRIPTION
    Automatically updates a DNS A-Record at IONOS with your current public IP address.
    Runs silently in the background via Windows Task Scheduler.
    Only sends an API request if the IP has actually changed.

.NOTES
    Author:  github.com/SRD3V
    License: MIT
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==============================================================================
# CONFIGURATION - Edit these values before first use
# ==============================================================================

# Your IONOS API credentials (from: https://developer.hosting.ionos.com/)
$PREFIX = "YOUR_API_PREFIX"       # e.g. lkjh245lkjh234lkj5h23lk4f1eade069958a2
$SECRET = "YOUR_API_SECRET"       # e.g. ASDJK4lkjkjhb23k4lh52klj3h45lkjhFDGSDFN345hjk23h4NAKSJHKL234234

# The fully qualified domain name you want to update
$FQDN = "dns.yourdomain.de" # e.g. dns.example.com

# DNS Time-To-Live in seconds (60 = 1 minute, recommended for dynamic IPs)
$TTL = 60

# Folder where the log and last-IP file will be stored
$STATE_DIR = "C:\DNS"

# ==============================================================================
# DO NOT EDIT BELOW THIS LINE
# ==============================================================================

$API_URL    = "https://api.hosting.ionos.com/dns/v1/zones"
$API_KEY    = "$PREFIX.$SECRET"
$STATE_FILE = "$STATE_DIR\lastip.txt"
$LOG_FILE   = "$STATE_DIR\ionos-ddns.log"

# Create state directory if it does not exist
if (-not (Test-Path $STATE_DIR)) {
    New-Item -ItemType Directory -Path $STATE_DIR | Out-Null
}

# ------------------------------------------------------------------------------
# Function: Write-Log
# Appends a timestamped message to the log file.
# ------------------------------------------------------------------------------
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $Message" | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
}

# ------------------------------------------------------------------------------
# Function: Get-PublicIP
# Retrieves the current public IPv4 address via api4.ipify.org.
# ------------------------------------------------------------------------------
function Get-PublicIP {
    try {
        $ip = Invoke-RestMethod -Uri "https://api4.ipify.org" -UseBasicParsing -TimeoutSec 10
        return $ip.Trim()
    } catch {
        throw "Failed to retrieve public IP: $_"
    }
}

# ------------------------------------------------------------------------------
# Function: Get-DomainFromFQDN
# Extracts the root domain from a fully qualified domain name.
# Example: "home.example.com" -> "example.com"
# ------------------------------------------------------------------------------
function Get-DomainFromFQDN {
    param([string]$Fqdn)
    return ($Fqdn -split "\.", 2)[1]
}

# ==============================================================================
# MAIN
# ==============================================================================
try {
    $DOMAIN     = Get-DomainFromFQDN $FQDN
    $CURRENT_IP = Get-PublicIP

    # --- IP change check ------------------------------------------------------
    # Read the last known IP from disk. If it matches the current IP, exit early.
    # This prevents unnecessary API calls to IONOS.
    $LAST_IP = ""
    if (Test-Path $STATE_FILE) {
        $LAST_IP = (Get-Content $STATE_FILE -TotalCount 1).Trim()
    }

    if ($LAST_IP -ne "" -and $CURRENT_IP -eq $LAST_IP) {
        exit 0  # IP unchanged - nothing to do
    }

    $headers = @{
        "accept"    = "application/json"
        "X-API-Key" = $API_KEY
    }

    # --- Find the DNS zone ----------------------------------------------------
    $zones = Invoke-RestMethod -Uri $API_URL -UseBasicParsing -Headers $headers -TimeoutSec 20
    $zone  = $zones | Where-Object { $_.name -eq $DOMAIN } | Select-Object -First 1

    if (-not $zone) {
        Write-Log "ERROR Zone not found for domain: $DOMAIN"
        exit 1
    }

    $ZONE_ID = $zone.id

    # --- Check if an A-Record already exists ----------------------------------
    $zoneDetail = Invoke-RestMethod -Uri "$API_URL/$ZONE_ID" -UseBasicParsing -Headers $headers -TimeoutSec 20
    $aRecord    = $zoneDetail.records | Where-Object { $_.name -eq $FQDN -and $_.type -eq "A" } | Select-Object -First 1

    $payload = @(
        @{
            name    = $FQDN
            type    = "A"
            content = $CURRENT_IP
            ttl     = $TTL
        }
    ) | ConvertTo-Json

    $postHeaders = $headers + @{ "Content-Type" = "application/json" }

    if ($aRecord) {
        # Record exists -> update it (PATCH)
        $response = Invoke-WebRequest -UseBasicParsing -Method Patch `
            -Uri "$API_URL/$ZONE_ID" `
            -Headers $postHeaders `
            -Body $payload `
            -TimeoutSec 20
        $ACTION = "PATCH"
    } else {
        # Record does not exist -> create it (POST)
        $response = Invoke-WebRequest -UseBasicParsing -Method Post `
            -Uri "$API_URL/$ZONE_ID/records" `
            -Headers $postHeaders `
            -Body $payload `
            -TimeoutSec 20
        $ACTION = "POST"
    }

    # Save the new IP to disk
    $CURRENT_IP | Out-File -FilePath $STATE_FILE -Encoding ASCII -NoNewline

    Write-Log "$ACTION $FQDN -> $CURRENT_IP HTTP=$($response.StatusCode)"

} catch {
    Write-Log "ERROR $_"
    exit 1
}
