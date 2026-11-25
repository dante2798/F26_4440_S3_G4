# Hide Steam's slide-out web menu panel that shows as a black box in old WebViews.
# Why: Steam's web CSS hides .responsive_page_menu_ctn with inset-inline-start (Chrome 87+).
#      The emulator's WebView is Chrome 69, ignores it, and draws the empty panel over the page.
# How: through WebView remote debugging (userdebug emulator), adds one <style> to each open page.
#      Display-only: nothing is written to Steam's app data and nothing is sent to Steam.
# Usage (project folder):
#   Once : powershell -ExecutionPolicy Bypass -File scripts\Fix-SteamMenu.ps1 -Serial emulator-5554
#   Keep : powershell -ExecutionPolicy Bypass -File scripts\Fix-SteamMenu.ps1 -Serial emulator-5554 -Watch
#          (re-applies every 2 s after page changes or a Steam restart; Ctrl+C to stop)
param(
    [Parameter(Mandatory)][string]$Serial,
    [string]$Package = 'com.valvesoftware.android.steam.community',
    [int]$Port = 9333,
    [switch]$Watch
)
$ErrorActionPreference = 'Stop'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) { $adb = 'adb' }

$css = '.responsive_page_menu_ctn{left:-320px !important;right:auto !important;}'
$js = "(function(){if(document.getElementById('g4-menu-fix'))return 'present';" +
      "var s=document.createElement('style');s.id='g4-menu-fix';s.textContent='$css';" +
      "(document.head||document.documentElement).appendChild(s);return 'applied';})()"

function Invoke-PageEval([string]$wsUrl, [string]$expression) {
    $ct = [Threading.CancellationToken]::None
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try {
        if (-not $ws.ConnectAsync([Uri]$wsUrl, $ct).Wait(5000)) { return 'timeout' }
        $msg = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expression; returnByValue = $true } } | ConvertTo-Json -Compress -Depth 5
        $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
        $ws.SendAsync([ArraySegment[byte]]$bytes, 'Text', $true, $ct).Wait()
        $buf = New-Object byte[] 65536; $sb = New-Object Text.StringBuilder
        do { $r = $ws.ReceiveAsync([ArraySegment[byte]]$buf, $ct).Result; [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)) } while (-not $r.EndOfMessage)
        return ($sb.ToString() | ConvertFrom-Json).result.result.value
    } catch { return "error: $($_.Exception.Message)" } finally { $ws.Dispose() }
}

$lastPid = ''
do {
    $appPid = ((& $adb -s $Serial shell pidof $Package) -join '').Trim()
    if (-not $appPid) {
        if (-not $Watch) { throw "$Package is not running on $Serial - open Steam first." }
    } else {
        if ($appPid -ne $lastPid) {
            & $adb -s $Serial forward "tcp:$Port" "localabstract:webview_devtools_remote_$appPid" | Out-Null
            $lastPid = $appPid
        }
        try { $pages = (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$Port/json" -TimeoutSec 5).Content | ConvertFrom-Json } catch { $pages = @() }
        foreach ($p in @($pages | Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl })) {
            $res = Invoke-PageEval $p.webSocketDebuggerUrl $js
            if ($res -ne 'present') { "{0}  {1,-8} {2}" -f (Get-Date -Format 'HH:mm:ss'), $res, $p.url }
        }
    }
    if ($Watch) { Start-Sleep -Seconds 2 }
} while ($Watch)
