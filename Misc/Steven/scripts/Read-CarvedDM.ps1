param(
    [Parameter(Mandatory)][string]$JsonlPath,   # output of: sqlite4n6 carve ... -f jsonl
    [Parameter(Mandatory)][string]$Channel,     # DM channel ID to keep
    [Parameter(Mandatory)][string]$OutPrefix    # e.g. work\carved_testing_dm  -> .csv and .txt
)

# Return the first complete {...} JSON object that starts at '{"id"' in $text.
function Get-JsonObject([string]$text) {
    $start = $text.IndexOf('{"id"')
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
    return $null   # record was cut off
}

$types = @{ 0 = 'message'; 3 = 'call'; 7 = 'member join'; 19 = 'reply' }
$table = @(); $pretty = @()

foreach ($line in Get-Content -LiteralPath $JsonlPath -Encoding UTF8) {
    $r = $line | ConvertFrom-Json
    $txt = ($r.values | Where-Object { $_.blob_base64 } |
            ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_.blob_base64)) }) -join ' '
    if ($txt -notmatch $Channel -or $txt -notmatch '"message"') { continue }

    $json = Get-JsonObject $txt
    $m = $null
    if ($json) { try { $m = ($json | ConvertFrom-Json).message } catch { } }

    if ($m) {
        $id = [decimal]$(if ($m.id) { $m.id } else { ($json | ConvertFrom-Json).id })
        $sentUtc = [DateTimeOffset]::FromUnixTimeMilliseconds([long]([Math]::Floor($id / 4194304) + 1420070400000)).UtcDateTime
        $t = [int]$m.type
        $table += [pscustomobject]@{
            page            = $r.page
            recovery_source = $r.recovery_source
            confidence      = $r.confidence
            sent_utc        = $sentUtc.ToString('yyyy-MM-dd HH:mm:ss')
            type            = $(if ($types.ContainsKey($t)) { "$t ($($types[$t]))" } else { "$t" })
            author          = $m.author.username
            content         = $m.content
            link_preview    = (@($m.embeds) | Where-Object { $_.url } | ForEach-Object { "$($_.url) - $($_.title)" }) -join '; '
            call_ended_utc  = $(if ($m.call.ended_timestamp) { ([datetime]$m.call.ended_timestamp).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') } else { '' })
            call_participants = (@($m.call.participants)) -join ', '
            message_id      = "$id"
        }
        $pretty += "=== page $($r.page) | $($r.recovery_source) | confidence $($r.confidence)"
        $pretty += ($json | ConvertFrom-Json | ConvertTo-Json -Depth 20)
        $pretty += ''
    } else {
        $pretty += "=== page $($r.page) | $($r.recovery_source) | confidence $($r.confidence) | could not parse (record incomplete), raw text:"
        $pretty += ($txt -replace '[^\x20-\x7E]', '.')
        $pretty += ''
    }
}

$table | Sort-Object sent_utc | Export-Csv "$OutPrefix.csv" -NoTypeInformation -Encoding UTF8
$pretty | Out-File "$OutPrefix.txt" -Encoding utf8
$table | Sort-Object sent_utc | Format-Table page, confidence, sent_utc, type, author, content, call_ended_utc -AutoSize
"Saved $OutPrefix.csv (summary) and $OutPrefix.txt (full records)."
