# Compare extracted stage folders file-by-file (SHA-1) and list added / deleted / modified files.
# SQLite -wal / -shm / -journal files are skipped (they churn on every open).
# Usage (project folder):
#   powershell -ExecutionPolicy Bypass -File scripts\Compare-Stages.ps1 -Root work_steam -Prefix steam_emu `
#       -Stages 01_baseline,02_after_guard,03_after_activity -Out work_steam\changes_by_stage.csv
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Prefix,
    [Parameter(Mandatory)][string[]]$Stages,
    [Parameter(Mandatory)][string]$Out
)
$ErrorActionPreference = 'Stop'
# powershell -File passes "a,b,c" as one string; split it.
$Stages = @($Stages | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

function Get-Manifest([string]$dir) {
    $base = (Resolve-Path $dir).Path
    $map = @{}
    foreach ($f in Get-ChildItem $base -Recurse -File -Force) {
        if ($f.Name -match '-(wal|shm|journal)$') { continue }
        $map[$f.FullName.Substring($base.Length + 1)] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA1).Hash
    }
    return ,$map
}

$manifests = @{}
foreach ($s in $Stages) { $manifests[$s] = Get-Manifest (Join-Path $Root "${Prefix}_$s") }

$rows = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $Stages.Count - 1; $i++) {
    $fromStage = $Stages[$i]; $toStage = $Stages[$i + 1]
    $fromMap = $manifests[$fromStage]; $toMap = $manifests[$toStage]
    $keys = @($fromMap.Keys) + @($toMap.Keys) | Sort-Object -Unique
    foreach ($k in $keys) {
        $status = $null
        if (-not $fromMap.ContainsKey($k)) { $status = 'added' }
        elseif (-not $toMap.ContainsKey($k)) { $status = 'deleted' }
        elseif ($fromMap[$k] -ne $toMap[$k]) { $status = 'modified' }
        if ($status) {
            $parts = $k.Split('\')
            $area = if ($parts.Count -gt 2) { $parts[1] } else { '(root)' }
            $rows.Add([pscustomobject]@{ from = $fromStage; to = $toStage; status = $status; area = $area; path = $k })
        }
    }
}
$rows | Export-Csv $Out -NoTypeInformation -Encoding UTF8
$rows | Group-Object from, to, status | ForEach-Object { '{0,-60} {1,5}' -f $_.Name, $_.Count }
"Saved: $Out ($($rows.Count) rows)"
