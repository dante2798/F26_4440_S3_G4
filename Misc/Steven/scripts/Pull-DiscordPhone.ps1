# Collect com.discord app data from the rooted phone (USB) as one tar archive,
# hash it on the phone and on the PC, and log the result.
# Usage (project folder):
#   powershell -ExecutionPolicy Bypass -File scripts\Pull-DiscordPhone.ps1 -Stage 01_baseline
# Writes:  phone\discord_<Stage>.tar  and appends a line to phone\collection_log.csv
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_\-]+$')][string]$Stage,
    [string]$Package = 'com.discord',
    [string]$OutDir  = 'phone'
)
$ErrorActionPreference = 'Stop'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) { $adb = 'adb' }

function Invoke-Phone([string]$cmd) {          # run a command on the phone as root, return stdout lines
    $out = & $adb -d shell "su -c '$cmd'"
    if ($LASTEXITCODE -ne 0) { throw "Phone command failed (exit $LASTEXITCODE): $cmd" }
    return $out
}

# 0. Phone connected?
$state = (& $adb -d get-state).Trim()
if ($state -ne 'device') { throw "Phone not connected over USB (adb -d get-state = '$state')" }

$tarName = "discord_$Stage.tar"
$remote  = "/data/local/tmp/$tarName"
New-Item -ItemType Directory $OutDir -Force | Out-Null
$local = Join-Path $OutDir $tarName
if (Test-Path $local) { throw "$local already exists - pick a new stage name, do not overwrite evidence." }

# 1. Pick tools: Magisk's busybox if present (Android 8 toybox may lack tar/sha256sum)
$bb = ''
if ((Invoke-Phone 'ls /data/adb/magisk/busybox 2>/dev/null') -match 'busybox') { $bb = '/data/adb/magisk/busybox ' }

# 2. Clocks
$pcUtc    = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
$phoneUtc = ((Invoke-Phone 'date -u +%Y-%m-%d\ %H:%M:%S') -join '').Trim()

# 3. Stop the app so files are not changing, then archive the whole app folder (keeps -wal/-shm and file times)
& $adb -d shell am force-stop $Package | Out-Null
Invoke-Phone "cd /data/data && ${bb}tar -cf $remote $Package && chmod 644 $remote" | Out-Null
$phoneHash = (((Invoke-Phone "${bb}sha256sum $remote") -join '') -split '\s+')[0].ToUpper()

# 4. Copy to PC and hash again
& $adb -d pull $remote $local
if ($LASTEXITCODE -ne 0) { throw "adb pull failed" }
$pcHash = (Get-FileHash $local -Algorithm SHA256).Hash
$match  = $pcHash -eq $phoneHash

# 5. Remove the temporary archive from the phone
Invoke-Phone "rm $remote" | Out-Null

# 6. Log
$logPath = Join-Path $OutDir 'collection_log.csv'
[pscustomobject]@{
    stage = $Stage; pc_utc = $pcUtc; phone_utc = $phoneUtc; package = $Package
    file = $tarName; bytes = (Get-Item $local).Length
    sha256_phone = $phoneHash; sha256_pc = $pcHash; hashes_match = $match
    tools = $(if ($bb) { 'magisk busybox' } else { 'toybox' })
} | Export-Csv $logPath -Append -NoTypeInformation -Encoding UTF8

"Stage      : $Stage"
"PC UTC     : $pcUtc    Phone UTC: $phoneUtc"
"Saved      : $local ($((Get-Item $local).Length) bytes)"
"SHA-256    : $pcHash"
if ($match) { "Hash check : MATCH (phone = PC)" } else { Write-Warning "Hash check: MISMATCH - phone $phoneHash vs PC $pcHash. Pull again." }
"Discord was force-stopped. Open it again before the next step."
