# Decode every record in a sqlite4n6 JSONL carve (sqlite4n6 carve <db> -f jsonl -o <file>)
# into a readable CSV (one row per record) and TXT (full records, indented).
# Read-only on the input; writes <OutPrefix>.csv and <OutPrefix>.txt.
param(
    [Parameter(Mandatory)][string]$JsonlPath,
    [Parameter(Mandatory)][string]$OutPrefix,
    [string]$Filter = ''          # optional: keep only records whose decoded text contains this
)

function Get-JsonObject([string]$text) {
    # First complete {...} object in $text, or $null if none / cut off.
    $start = $text.IndexOf('{')
    if ($start -lt 0) { return $null }
    $depth = 0; $inStr = $false; $esc = $false
    for ($i = $start; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($inStr) {
            if ($esc) { $esc = $false } elseif ($ch -eq '\') { $esc = $true } elseif ($ch -eq '"') { $inStr = $false }
            continue
        }
        if ($ch -eq '"') { $inStr = $true }
        elseif ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($start, $i - $start + 1) } }
    }
    return $null
}

function Get-Printable([string]$s) { ($s -replace '[\x00-\x1F\x7F]', ' ' -replace '�', '' -replace ' {2,}', ' ').Trim() }

$msgTypes = @{ 0 = 'message'; 3 = 'call'; 7 = 'member join'; 19 = 'reply' }
$table = @(); $pretty = @()

foreach ($line in Get-Content -LiteralPath $JsonlPath -Encoding UTF8) {
    if (-not $line.Trim()) { continue }
    $r = $line | ConvertFrom-Json

    # Decode each column: blobs from base64, others as-is.
    $cols = @(foreach ($v in $r.values) {
        if ($null -eq $v) { '' }
        elseif ($v.PSObject.Properties.Name -contains 'blob_base64') { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($v.blob_base64)) }
        else { "$v" }
    })
    $all = $cols -join ' '
    if ($Filter -and -not $all.Contains($Filter)) { continue }

    $key  = (@($cols | Select-Object -First 3 | ForEach-Object { Get-Printable $_ }) | Where-Object { $_ -and $_ -ne 'NULL' }) -join ' / '
    $json = Get-JsonObject $all
    $obj  = $null
    if ($json) { try { $obj = $json | ConvertFrom-Json } catch { $obj = $null } }

    $row = [ordered]@{
        page = $r.page; offset = $r.offset; rowid = $r.rowid
        recovery_source = $r.recovery_source; confidence = $r.confidence; wal_frame = $r.wal.frame_index
        key = $key; kind = ''; sent_utc = ''; author = ''; content = ''; link_preview = ''; call_ended_utc = ''
        summary = ''
    }

    $m = $null
    if ($obj -and $obj.PSObject.Properties.Name -contains 'message') { $m = $obj.message }
    if ($m) {
        $idText = $(if ($m.id) { $m.id } else { $obj.id })
        if ($idText -match '^\d+$') {
            $ms = [long]([Math]::Floor([decimal]$idText / 4194304) + 1420070400000)
            $row.sent_utc = [DateTimeOffset]::FromUnixTimeMilliseconds($ms).UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')
        }
        $t = [int]$m.type
        $row.kind = 'message type ' + $(if ($msgTypes.ContainsKey($t)) { "$t ($($msgTypes[$t]))" } else { "$t" })
        $row.author = $m.author.username
        $row.content = $m.content
        $row.link_preview = (@($m.embeds) | Where-Object { $_.url } | ForEach-Object { "$($_.url) - $($_.title)" }) -join '; '
        if ($m.call.ended_timestamp) { $row.call_ended_utc = ([datetime]$m.call.ended_timestamp).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') }
        $row.summary = "channel $($obj.channelId)"
    } elseif ($obj) {
        $row.kind = 'json'
        $row.summary = (Get-Printable $json); if ($row.summary.Length -gt 300) { $row.summary = $row.summary.Substring(0, 300) + ' ...' }
    } else {
        $row.kind = $(if ($json -eq $null -and $all.Contains('{')) { 'json (cut off)' } else { 'other' })
        $row.summary = Get-Printable $all; if ($row.summary.Length -gt 300) { $row.summary = $row.summary.Substring(0, 300) + ' ...' }
    }
    $table += [pscustomobject]$row

    $pretty += "=== page $($r.page) offset $($r.offset) | $($r.recovery_source) | confidence $($r.confidence) | key: $key"
    if ($obj) { $pretty += ($obj | ConvertTo-Json -Depth 20) } else { $pretty += (Get-Printable $all) }
    $pretty += ''
}

$table | Export-Csv "$OutPrefix.csv" -NoTypeInformation -Encoding UTF8
$pretty | Out-File "$OutPrefix.txt" -Encoding utf8
"Decoded $($table.Count) record(s)."
$table | Group-Object { ($_.key -split ' / ')[0] } | Sort-Object Count -Descending | Select-Object Count, @{n='record type (first key)'; e={ $_.Name }} | Format-Table -AutoSize
"Saved $OutPrefix.csv (one row per record) and $OutPrefix.txt (full records)."
