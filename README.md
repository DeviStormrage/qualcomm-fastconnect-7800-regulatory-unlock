# Fix China WiFi Regulatory Domain

Unblock 5GHz channels (36–64, 100–144) on **Chinese-region laptops** with **Qualcomm FastConnect 7800 (WCN785x)** WiFi cards.

## The Problem

Chinese-region laptops (Lenovo, HP, Dell, etc.) using Qualcomm FastConnect 7800 are hard-locked to the **China regulatory domain** (`EnableCustomizedRegdomain = 3`). The firmware (`ncm825.elf`) restricts available 5GHz channels, even when Windows is set to a different country.

| 5GHz Channel Range | China | US / EU / VN | After Fix |
|-------------------|-------|--------------|-----------|
| 36–48 (UNII-1)     | ✅    | ✅           | ✅        |
| 52–64 (UNII-2)     | ✅    | ✅           | ✅        |
| **100–144 (UNII-2e)** | **❌ BLOCKED** | **✅**   | **✅**    |
| 149–165 (UNII-3)   | ✅    | ✅           | ✅        |

**Symptoms:**
- You can only see 5GHz networks on channels 149–161
- Channels 36–64 and 100–144 are invisible
- The card connects at 2.4GHz speeds despite good 5GHz signal
- Country/region in Windows settings is ignored (Qualcomm self-managed regulatory domain)

## Solution

This PowerShell script automatically:

| Setting | Before | After |
|---------|--------|-------|
| `EnableCustomizedRegdomain` | 3 (China) | **4** (Global) |
| `DisableNetBand` | 0x6E00000 | **0** |
| `BDFileName` | `ncm825.elf` (China firmware) | **`ncm865a.elf`** (Global firmware) |
| `StaPreferredBand` | 1 (No Preference) | **2** (Prefer 5GHz) |
| `roamPolicy` | 3 (Medium) | **1** (Lowest) |
| Registry backup | — | ✅ Auto-backup before changes |
| Adapter restart | — | ✅ Auto restart |

## Usage

```powershell
# Clone
git clone https://github.com/DeviStormrage/fix-china-wifi-regulatory.git
cd fix-china-wifi-regulatory

# Run (must be Administrator)
Right-click Fix-ChinaWifiRegulatory.ps1 → "Run with PowerShell"

# Or from command line
powershell -ExecutionPolicy Bypass -File .\Fix-ChinaWifiRegulatory.ps1
```

### Requirements

- Windows 10 or 11
- Qualcomm FastConnect 7800 (WCN785x / QCNCM865) WiFi card
- Administrator privileges

### Rollback

1. Open Registry Editor
2. File → Import → navigate to `%USERPROFILE%\.hermes\wifi-regbackup\`
3. Pick the `.reg` backup file and import
4. Reboot

## Verify Before Running

Open PowerShell (Admin) and run:

```powershell
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\0000" |
    Select-Object DriverDesc, EnableCustomizedRegdomain, BDFileName
```

If you see `EnableCustomizedRegdomain = 3` and `BDFileName` contains `ncm825`, this script will fix it.

## How It Works

Qualcomm FastConnect 7800 cards have a **self-managed regulatory domain** — the firmware decides which channels are legal, ignoring the Windows country setting. The card ships with two firmware variants:

| Firmware | Used In | Channels |
|----------|---------|----------|
| `ncm825.elf` | China-region laptops | 2.4GHz + 5GHz ch 149–165 only |
| `ncm865a.elf` | Global laptops | 2.4GHz + 5GHz ch 36–165 + 6GHz |

The script switches the registry pointers from the China firmware to the Global firmware, then tells the driver to use the global regulatory table.

## Disclaimer

**Use at your own risk.** While tested on actual hardware (Lenovo laptop with FastConnect 7800), modifying firmware pointers in the registry may cause instability on some configurations. The script creates a full backup before making changes so you can always roll back.

## Author

[DeviStormrage](https://github.com/DeviStormrage) — generated with Hermes Agent (Nous Research).
