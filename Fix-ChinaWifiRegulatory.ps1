# Fix-ChinaWifiRegulatory.ps1
# ============================
# Fix 5GHz channel restrictions on Chinese-region laptops with
# Qualcomm FastConnect 7800 (WCN785x / QCNCM865) WiFi cards.
#
# Usage:
#   Right-click → "Run with PowerShell" (as Administrator)
#   or: powershell -ExecutionPolicy Bypass -File .\Fix-ChinaWifiRegulatory.ps1
#
# What it does:
#   - Detects Qualcomm FastConnect 7800 adapters
#   - Backs up current registry settings
#   - Changes EnableCustomizedRegdomain from 3 (China) → 4 (Global)
#   - Changes firmware from ncm825.elf (China) → ncm865a.elf (Global)
#   - Clears DisableNetBand bitmask
#   - Sets Preferred Band to 5GHz
#   - Reduces roaming aggressiveness
#   - Restarts the WiFi adapter
#
# Rollback: import the .reg backup from %USERPROFILE%\.hermes\wifi-regbackup\
#           then reboot.

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ---- Console helpers ----
function Write-Info  { Write-Host "ℹ️  $args" -ForegroundColor Cyan }
function Write-Ok    { Write-Host "✅ $args" -ForegroundColor Green }
function Write-Warn  { Write-Host "⚠️  $args" -ForegroundColor Yellow }
function Write-Err   { Write-Host "❌ $args" -ForegroundColor Red }

Write-Info "===== Fix China WiFi Regulatory Domain ====="
Write-Info ""

# ---- 1. Admin check (enforced by #Requires) ----
Write-Info "Checking admin privileges..."

# ---- 2. Find Qualcomm FastConnect adapters ----
$adapterGuid = '{4d36e972-e325-11ce-bfc1-08002be10318}'
$regBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$adapterGuid"
$found = $false

Get-ChildItem $regBase -ErrorAction SilentlyContinue | ForEach-Object {
    $desc = (Get-ItemProperty -Path $_.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue).DriverDesc
    $enableCR = (Get-ItemProperty -Path $_.PSPath -Name "EnableCustomizedRegdomain" -ErrorAction SilentlyContinue).EnableCustomizedRegdomain
    $bdFile   = (Get-ItemProperty -Path $_.PSPath -Name "BDFileName" -ErrorAction SilentlyContinue).BDFileName

    if ($desc -and $desc -match "Qualcomm.*FastConnect") {
        $adapterKey = $_.PSChildName
        $adapterPath = $_.PSPath
        $found = $true

        Write-Ok "Found: $desc"
        Write-Info "  Registry key: $adapterKey"
        Write-Info "  EnableCustomizedRegdomain = $enableCR"
        Write-Info "  BDFileName = $bdFile"

        if ($enableCR -ne 3) {
            Write-Warn "EnableCustomizedRegdomain is $enableCR (not 3)."
            Write-Warn "This adapter doesn't appear to be China-locked. Skipping..."
            return
        }

        # ---- 3. Backup current registry ----
        $backupDir = "$env:USERPROFILE\.hermes\wifi-regbackup"
        if (-not (Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
        $backupFile = "$backupDir\regbackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"

        Write-Info "Backing up registry to: $backupFile"
        $adapterKeyFull = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\$adapterGuid\$adapterKey"
        reg export $adapterKeyFull "`"$backupFile`"" /y 2>&1 | Out-Null
        Write-Ok "Backup saved: $backupFile"

        # ---- 4. Build changeset ----
        Write-Info ""
        Write-Info "Applying fixes..."

        $changes = @(
            @{Name="EnableCustomizedRegdomain"; Value=4;  Type="DWord"; Desc="Switch China regdomain → Global"},
            @{Name="DisableNetBand";            Value=0;  Type="DWord"; Desc="Clear band disable bitmask"},
            @{Name="StaPreferredBand";          Value=2;  Type="DWord"; Desc="Prefer 5GHz band"},
            @{Name="roamPolicy";                Value=1;  Type="DWord"; Desc="Reduce roaming aggressiveness"}
        )

        # Only switch firmware if currently a China variant
        if ($bdFile -and $bdFile -match "ncm825") {
            $newBdFile = $bdFile -replace "ncm825", "ncm865a"
            $changes += @{Name="BDFileName"; Value=$newBdFile; Type="String"; Desc="Switch China firmware → Global firmware"}
        }

        foreach ($c in $changes) {
            try {
                if ($c.Type -eq "String") {
                    Set-ItemProperty -Path $adapterPath -Name $c.Name -Value $c.Value -Type String -ErrorAction Stop
                } else {
                    Set-ItemProperty -Path $adapterPath -Name $c.Name -Value $c.Value -Type DWord -ErrorAction Stop
                }
                Write-Ok "  $($c.Name) → $($c.Value)  ($($c.Desc))"
            } catch {
                Write-Err "  Failed to set $($c.Name): $_"
            }
        }

        # ---- 5. Verify changes ----
        Write-Info ""
        Write-Info "Verifying..."
        $props = Get-ItemProperty -Path $adapterPath
        foreach ($k in @("EnableCustomizedRegdomain","DisableNetBand","BDFileName","StaPreferredBand","roamPolicy")) {
            $val = $props.$k
            if ($null -ne $val) {
                Write-Ok "  $k = $val"
            }
        }

        # ---- 6. Restart adapter ----
        Write-Info ""
        Write-Info "Restarting WiFi adapter..."
        try {
            Get-NetAdapter -Name "*Wi-Fi*","*WLAN*","*Wireless*" -ErrorAction Stop |
                Restart-NetAdapter -Confirm:$false -ErrorAction Stop
            Write-Ok "Adapter restarted."
        } catch {
            Write-Warn "Could not restart adapter automatically. Please restart manually or reboot."
        }

        Write-Info ""
        Write-Ok "===== DONE ====="
        Write-Info ""
        Write-Info "Recommended post-fix steps:"
        Write-Info "  1. Reboot to let the driver load the new firmware"
        Write-Info "  2. Scan for WiFi networks — you should now see 5GHz channels 36-64 and 100-144"
        Write-Info "  3. In Device Manager → Network Adapter → Properties → Advanced:"
        Write-Info "     • Preferred Band: 5 GHz First"
        Write-Info "     • Roaming Aggressiveness: Lowest"
        Write-Info ""
        Write-Info " To roll back: import the .reg file from $backupDir then reboot."
    }
}

if (-not $found) {
    Write-Err "No Qualcomm FastConnect 7800 adapter found on this system."
    Write-Info "This script targets laptops with Qualcomm FastConnect 7800 (WCN785x) cards."
}
