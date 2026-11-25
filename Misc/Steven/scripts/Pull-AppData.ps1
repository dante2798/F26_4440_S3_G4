# Collect an app's data folder as one tar, hash it on the device and on the PC, and log it.
# Works on the rooted phone (Magisk su) and on a userdebug emulator (adb root).
# Usage (project folder):
#   Phone   : powershell -ExecutionPolicy Bypass -File scripts\Pull-AppData.ps1 -Serial 2c3f64eb -Package com.valvesoftware.android.steam.community -Prefix steam_phone -Stage 01_baseline
#   Emulator: powershell -ExecutionPolicy Bypass -File scripts\Pull-AppData.ps1 -Serial emulator-5556 -AdbRoot -Package com.valvesoftware.android.steam.community -Prefix steam_emu -Stage 01_baseline
# Writes <OutDir>\<Prefix>_<Stage>.tar and appends to <OutDir>\collection_log.csv.
# -IncludeExternal also archives /sdcard/Android/data/<Package> (as <Prefix>_<Stage>_external.tar).
param(
    [Parameter(Mandatory)][string]$Serial,
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_\-]+$')][string]$Prefix,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_\-]+$')][string]$Stage,
    [switch]$AdbRoot,
    [switch]$IncludeExternal,
    [string]$OutDir = 'collected'
)
$ErrorActionPreference = 'Stop'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) { $adb = 'adb' }

if ($AdbRoot) { & $adb -s $Serial root | Out-Null; & $adb -s $Serial wait-for-device }
$state = ((& $adb -s $Serial get-state) -join '').Trim()
if ($state -ne 'device') { throw "Device $Serial not ready (get-state = '$state')" }

function Invoke-Device([string]$cmd) {
    if ($AdbRoot) { $out = & $adb -s $Serial shell $cmd } else { $out = & $adb -s $Serial shell "su -c '$cmd'" }
    if ($LASTEXITCODE -ne 0) { throw "Device command failed (exit $LASTEXITCODE): $cmd" }
    return $out
}

$who = ((Invoke-Device 'id -u') -join '').Trim()
if ($who -ne '0') { throw "Not root on $Serial (id -u = $who). Phone: allow Shell in Magisk. Emulator: use -AdbRoot on a Google APIs (userdebug) image." }

$bb = ''
# Probe must not fail when Magisk is absent (emulator), so always exit 0.
if ((Invoke-Device '[ -x /data/adb/magisk/busybox ] && echo busybox || true') -match 'busybox') { $bb = '/data/adb/magisk/busybox ' }
foreach ($tool in 'tar', 'sha256sum') {
    if (-not $bb -and -not ((Invoke-Device "which $tool") -match $tool)) { throw "$tool not found on $Serial" }
}

New-Item -ItemType Directory $OutDir -Force | Out-Null
$logPath = Join-Path $OutDir 'collection_log.csv'

function Get-Archive([string]$name, [string]$parent, [string]$folder) {
    $local = Join-Path $OutDir $name
    if (Test-Path $local) { throw "$local already exists - pick a new stage name, do not overwrite evidence." }
    $remote = "/data/local/tmp/$name"
    # Must exit 0 when the folder is missing (e.g. after Clear data), so the warning below is reached.
    $exists = ((Invoke-Device "[ -d $parent/$folder ] && echo yes || echo no") -join '').Trim()
    if ($exists -ne 'yes') { Write-Warning "$parent/$folder does not exist on the device - skipped."; return }
    Invoke-Device "cd $parent && ${bb}tar -cf $remote $folder && chmod 644 $remote" | Out-Null
    $devHash = (((Invoke-Device "${bb}sha256sum $remote") -join '') -split '\s+')[0].ToUpper()
    & $adb -s $Serial pull $remote $local
    if ($LASTEXITCODE -ne 0) { throw "adb pull failed for $remote" }
    Invoke-Device "rm $remote" | Out-Null
    $pcHash = (Get-FileHash $local -Algorithm SHA256).Hash
    [pscustomobject]@{
        prefix = $Prefix; stage = $Stage; serial = $Serial; package = $Package; source = "$parent/$folder"
        pc_utc = $script:pcUtc; device_utc = $script:devUtc; file = $name; bytes = (Get-Item $local).Length
        sha256_device = $devHash; sha256_pc = $pcHash; hashes_match = ($devHash -eq $pcHash)
    } | Export-Csv $logPath -Append -NoTypeInformation -Encoding UTF8
    "Saved      : $local ($((Get-Item $local).Length) bytes)"
    "SHA-256    : $pcHash"
    if ($devHash -eq $pcHash) { "Hash check : MATCH (device = PC)" } else { Write-Warning "Hash MISMATCH for $name - pull again with a new stage name." }
}

$script:pcUtc  = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
$script:devUtc = ((Invoke-Device 'date -u +%Y-%m-%d\ %H:%M:%S') -join '').Trim()
& $adb -s $Serial shell am force-stop $Package | Out-Null

"Stage      : $Stage   ($Prefix on $Serial)"
"PC UTC     : $script:pcUtc    Device UTC: $script:devUtc"
Get-Archive "${Prefix}_$Stage.tar" '/data/data' $Package
if ($IncludeExternal) { Get-Archive "${Prefix}_${Stage}_external.tar" '/sdcard/Android/data' $Package }
"$Package was force-stopped. Open it again before the next step."
