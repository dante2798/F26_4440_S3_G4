# Turn Discord's telemetry_ring.db into a readable activity timeline.
# Works on a throw-away copy (opening the database can merge its -wal file).
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\Export-DiscordTelemetry.ps1 -Stage testing
#   (optional) -From "2026-11-24 07:20" -To "2026-11-24 07:50"   (UTC)  -All  (keep every event)
param(
    [Parameter(Mandatory)][string]$Stage,      # login / testing / logout ... (folder emu_discord_after_<Stage>)
    [string]$From = '', [string]$To = '',       # UTC range filter, "yyyy-MM-dd HH:mm"
    [switch]$All,                               # include events without a plain-language label
    [string]$Root = ''                          # app folder to read instead, e.g. work_phone\03_after_send\com.discord
)
$ErrorActionPreference = 'Stop'
$src = if ($Root) { Join-Path $Root 'databases\telemetry_ring.db' } else { "emu_discord_after_$Stage\databases\telemetry_ring.db" }
if (-not (Test-Path $src)) { throw "Not found: $src" }

$tmp = "work\query_telemetry_$Stage"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory $tmp -Force | Out-Null
Copy-Item "$src*" $tmp

$sql = "SELECT json_extract(payload_json,'$.timestamp') AS ms, payload_json FROM telemetry_ring_slots WHERE payload_json IS NOT NULL ORDER BY ms;"
$rows = sqlite3 -separator "`t" "$tmp\telemetry_ring.db" $sql

function Get-Label($e) {
    $k = $e.key; $d = $e.data
    if ($k -eq 'http_request') {
        $u = $d.url -replace '^https://discord\.com/api/v#', ''
        switch -regex ("$($d.method) $u") {
            '^POST /channels/#/messages$'            { return 'Sent a message' }
            '^DELETE /channels/#/messages/#$'        { return 'Deleted a message' }
            '^PATCH /channels/#/messages/#$'         { return 'Edited a message' }
            '^PUT /channels/#/messages/#/reactions'  { return 'Added a reaction' }
            '^DELETE /channels/#/messages/#/reactions' { return 'Removed a reaction' }
            '^POST /channels/#/typing$'              { return 'Typing' }
            '^POST /channels/#/messages/#/ack$'      { return 'Marked messages as read' }
            '^GET /channels/#/messages$'             { return 'Loaded messages in a chat' }
            '^DELETE /channels/#$'                   { return 'Closed DM / left channel' }
            '^POST /users/@me/channels$'             { return 'Opened a DM' }
            '^POST /channels/#/call/ring$'           { return 'Started a call (ringing the other user)' }
            '^POST /channels/#/attachments$'         { return 'Uploading an attachment' }
            '^GET /invites/'                         { return "Loaded invite preview ($($u -replace '^/invites/', ''))" }
            '^POST /auth/login'                      { return 'Logged in' }
            '^POST /auth/logout'                     { return 'Logged out' }
            '^GET /users/#/profile$'                 { return 'Viewed a user profile' }
            default                                  { return $null }
        }
    }
    if ($k -eq 'Kotlin NotificationClient received Notification.') {
        switch ($d.type) {
            'MESSAGE_CREATE' { return 'Notification: new message' }
            'CALL_RING'      { return 'Notification: incoming call' }
            'CALL_ACK'       { return 'Notification: call acknowledged' }
            'CHANNEL_ACK'    { return 'Notification: chat marked as read' }
            default          { return "Notification: $($d.type)" }
        }
    }
    if ($k -eq 'Create or update service with configuration type VOICE_CALL') { return 'Call service started (call connected)' }
    if ($k -eq 'On service destroyed.') { return 'Call service stopped (call ended)' }
    if ($k -eq 'app_lifecycle' -and $d.state -eq 'foreground') { return 'App came to the foreground' }
    if ($k -eq 'app_lifecycle' -and $d.state -eq 'background') { return 'App went to the background' }
    return $null
}

$fromMs = if ($From) { [DateTimeOffset]::new([datetime]::ParseExact($From, 'yyyy-MM-dd HH:mm', $null), [TimeSpan]::Zero).ToUnixTimeMilliseconds() } else { 0 }
$toMs   = if ($To)   { [DateTimeOffset]::new([datetime]::ParseExact($To,   'yyyy-MM-dd HH:mm', $null), [TimeSpan]::Zero).ToUnixTimeMilliseconds() } else { [long]::MaxValue }

$out = foreach ($line in $rows) {
    $ms, $json = $line -split "`t", 2
    if (-not $ms -or [long]$ms -lt $fromMs -or [long]$ms -gt $toMs) { continue }
    try { $e = $json | ConvertFrom-Json } catch { continue }
    $label = Get-Label $e
    if (-not $label -and -not $All) { continue }
    $t = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ms)
    [pscustomobject]@{
        utc        = $t.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')
        local_time = $t.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
        action     = $(if ($label) { $label } else { $e.key })
        detail     = $(if ($e.data.url) { "$($e.data.method) $($e.data.url) -> $($e.data.status_code)" } elseif ($e.data.type) { $e.data.type } else { '' })
        raw_ms     = $ms
    }
}

# Collapse runs of the same "Typing" event within 30 s to keep the list short.
$final = @(); $prev = $null
foreach ($r in $out) {
    if ($prev -and $r.action -eq 'Typing' -and $prev.action -eq 'Typing' -and ([long]$r.raw_ms - [long]$prev.raw_ms) -lt 30000) { $prev = $r; continue }
    $final += $r; $prev = $r
}

$csv = "work\telemetry_$Stage.csv"
$final | Select-Object utc, local_time, action, detail | Export-Csv $csv -NoTypeInformation -Encoding UTF8
$final | Format-Table local_time, utc, action -AutoSize
"$($final.Count) events saved to $csv (local time = this PC's time zone)."
