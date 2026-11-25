# Raw byte search: find text anywhere in an extracted app folder, including unused
# space inside databases and WAL files that SQL tools and carvers do not show.
# Read-only. Searches UTF-8 and UTF-16LE. For Discord message hits it also reports the
# record key that comes BEFORE the text (messages.<channel id>.<message id>) - always
# use that key, not IDs that follow the text (they may belong to a newer record).
#
# Examples (project folder):
#   powershell -ExecutionPolicy Bypass -File scripts\Search-RawText.ps1 -Path work_phone\06_after_logout\com.discord -Text TEST06,TEST16
#   powershell -ExecutionPolicy Bypass -File scripts\Search-RawText.ps1 -Path work_phone\06_after_logout\com.discord\files\kv-storage -Pattern '\x22content\x22:\x22[^\x22]{1,200}\x22'
#   (write double quotes in -Pattern as \x22: powershell -File strips real quotes)
#   The pattern form finds every message text, live or leftover, without knowing the words.
param(
    [Parameter(Mandatory)][string]$Path,          # folder to search (recursively)
    [string[]]$Text = @(),                        # exact strings, e.g. markers
    [string]$Pattern = '',                        # or a regular expression (UTF-8 / ASCII only)
    [string]$OutCsv = '',                         # optional: save hits
    [string]$Exclude = '\\otas\\|\\lib\\'         # paths to skip (Discord's code bundle)
)
$Text = @($Text | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # -File passes "A,B" as one string
if (-not $Text -and -not $Pattern) { throw 'Give -Text or -Pattern.' }
$latin = [Text.Encoding]::GetEncoding(28591); $u8 = [Text.Encoding]::UTF8
$root = (Resolve-Path $Path).Path

function Get-Context([byte[]]$b, [string]$s, [int]$i) {
    $pre = $s.Substring([Math]::Max(0, $i - 400), [Math]::Min(400, $i))
    $km = [regex]::Matches($pre, 'messages\W(\d{15,20})\W(\d{15,20})')
    $key = if ($km.Count) { "$($km[$km.Count - 1].Groups[1].Value)/$($km[$km.Count - 1].Groups[2].Value)" } else { '' }
    $txt = ($u8.GetString($b, $i, [Math]::Min(120, $b.Length - $i)) -replace '[\x00-\x1F]', '.')
    $q = $txt.IndexOf('","'); if ($q -gt 0) { $txt = $txt.Substring(0, $q) }
    return $key, $txt
}

$hits = foreach ($f in Get-ChildItem $root -Recurse -File -Force | Where-Object { $_.Length -gt 0 -and $_.FullName -notmatch $Exclude }) {
    $b = [IO.File]::ReadAllBytes($f.FullName); $s = $latin.GetString($b)
    $rel = $f.FullName.Substring($root.Length + 1)
    foreach ($t in $Text) {
        foreach ($enc in 'utf8', 'utf16') {
            $needle = if ($enc -eq 'utf8') { $latin.GetString($u8.GetBytes($t)) } else { $latin.GetString([Text.Encoding]::Unicode.GetBytes($t)) }
            $i = $s.IndexOf($needle, [StringComparison]::Ordinal)
            while ($i -ge 0) {
                $key, $txt = Get-Context $b $s $i
                [pscustomobject]@{ file = $rel; offset = $i; page4k = [Math]::Floor($i / 4096) + 1; search = $t; encoding = $enc; key_channel_message = $key; text = $txt }
                $i = $s.IndexOf($needle, $i + 1, [StringComparison]::Ordinal)
            }
        }
    }
    if ($Pattern) {
        foreach ($m in [regex]::Matches($s, $Pattern)) {
            $key, $txt = Get-Context $b $s $m.Index
            [pscustomobject]@{ file = $rel; offset = $m.Index; page4k = [Math]::Floor($m.Index / 4096) + 1; search = 'pattern'; encoding = 'utf8'; key_channel_message = $key; text = $txt }
        }
    }
}
if ($OutCsv) { $hits | Export-Csv $OutCsv -NoTypeInformation -Encoding UTF8 }
$hits | Format-Table file, page4k, search, key_channel_message, text -AutoSize | Out-String -Width 220
"$(@($hits).Count) hit(s)."
