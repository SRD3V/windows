# IONOS Dynamic DNS Updater for Windows

A lightweight PowerShell script that automatically keeps your IONOS DNS A-Record in sync with your current public IP address - silently running in the background via Windows Task Scheduler.

No third-party tools, no installations, no GUI. Just PowerShell.

---

## How it works

Every hour (and on every system startup), the script:

1. Fetches your current public IPv4 address via [api4.ipify.org](https://api4.ipify.org)
2. Compares it to the last known IP stored locally in `lastip.txt`
3. **If the IP is unchanged** -> exits immediately, no API call is made
4. **If the IP has changed** -> updates the A-Record at IONOS via their DNS API
5. Logs the result with a timestamp to `ionos-ddns.log`

This approach avoids unnecessary API requests and keeps things efficient.

---

## Requirements

- Windows 10 / 11 (or Windows Server 2016+)
- PowerShell 5.1 or newer (included in Windows by default)
- An [IONOS API key](https://developer.hosting.ionos.de/keys)
- A domain managed by IONOS with a DNS A-Record you want to keep updated

---

## Setup

### Step 1 - Get your IONOS API credentials

1. Log in to [developer.hosting.ionos.de/keys](https://developer.hosting.ionos.de/keys)
2. Create a new API key
3. Copy the **Prefix** and **Secret** - you will need both

### Step 2 - Download the scripts

Download both files and place them in `C:\DNS\`:

```
C:\DNS\ionos-ddns.ps1
C:\DNS\setup-task.ps1
```

### Step 3 - Configure ionos-ddns.ps1

Open `ionos-ddns.ps1` in Notepad or any text editor and fill in your details at the top of the file:

```powershell
$PREFIX = "YOUR_API_PREFIX"        # The prefix part of your IONOS API key
$SECRET = "YOUR_API_SECRET"        # The secret part of your IONOS API key
$FQDN   = "subdomain.yourdomain.de" # The full hostname you want to update
$TTL    = 60                        # DNS TTL in seconds (60 recommended)
```

**Where to find PREFIX and SECRET:**
IONOS gives you an API key in the format `prefix.secret` - split at the dot and paste each part separately.

**What is FQDN?**
The fully qualified domain name of the record you want to update, for example `home.example.com` or `myserver.example.de`.

### Step 4 - Run the setup script (once, as Administrator)

1. Open **PowerShell as Administrator**
   - Press `Win + X` and choose **Windows PowerShell (Admin)**
   - Or search for `powershell`, right-click -> **Run as administrator**

2. Allow the scripts to run (one-time):
```powershell
Set-ExecutionPolicy -Scope LocalMachine RemoteSigned -Force
```

3. Unblock the downloaded files:
```powershell
Unblock-File -Path "C:\DNS\ionos-ddns.ps1"
Unblock-File -Path "C:\DNS\setup-task.ps1"
```

4. Navigate to the folder and run the setup:
```powershell
cd C:\DNS
.\setup-task.ps1
```

The setup script will:
- Register a scheduled task under `\Custom\IONOS-DDNS-Updater`
- Set two triggers: **at system startup** and **every hour**
- Run as the `SYSTEM` account (no user login required)
- Immediately run a first test and show the log output

---

## Task Scheduler - what gets configured

| Setting | Value |
|---|---|
| Task name | IONOS-DDNS-Updater |
| Location | Task Scheduler Library -> Custom |
| Trigger 1 | At system startup |
| Trigger 2 | Every 1 hour |
| Run as | SYSTEM |
| Window | Hidden (no visible window) |
| On missed run | Start as soon as possible |
| Network required | Yes |

To verify in the UI: open `taskschd.msc` -> expand **Task Scheduler Library** -> open **Custom** -> find `IONOS-DDNS-Updater`.

---

## Verifying it works

**Check the log file:**
```powershell
Get-Content "C:\DNS\ionos-ddns.log"
```

A successful update looks like:
```
2026-04-19 11:23:26 PATCH home.example.com -> 192.168.137.137 HTTP=200
```

A first-time record creation looks like:
```
2026-04-19 11:23:26 POST home.example.com -> 192.168.137.137 HTTP=201
```

**If the log has no new entries** - this is normal and means your IP has not changed. The script exits silently without writing anything when the IP is unchanged.

**Check task status:**
```powershell
Get-ScheduledTaskInfo -TaskPath "\Custom\" -TaskName "IONOS-DDNS-Updater"
```

`LastTaskResult: 0` means the last run was successful.

**Trigger a manual test run:**
```powershell
Start-ScheduledTask -TaskPath "\Custom\" -TaskName "IONOS-DDNS-Updater"
Start-Sleep -Seconds 5
Get-Content "C:\DNS\ionos-ddns.log"
```

---

## Files

| File | Description |
|---|---|
| `ionos-ddns.ps1` | The main DDNS updater script |
| `setup-task.ps1` | One-time setup script for Task Scheduler |
| `C:\DNS\lastip.txt` | Stores the last known public IP (auto-created) |
| `C:\DNS\ionos-ddns.log` | Log file with timestamped update history (auto-created) |

---

## Removing the task

To uninstall, run as Administrator:
```powershell
Unregister-ScheduledTask -TaskPath "\Custom\" -TaskName "IONOS-DDNS-Updater" -Confirm:$false
```

---

## License

MIT - do whatever you want with it.
