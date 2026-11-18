# Rewrites the master CSV "Truck spaces" and "Count source" columns from the
# per-source figures (capacity-sources.csv + wv-truck-parking-tss.csv +
# satellite-count\study-summary.csv; see tools\capacity-sources.ps1), listed
# Public -> Private -> Satellite count, ending with whether the numbers agree.
# Every other column is left untouched; the file keeps its quoting (header bare,
# every field quoted) and LF line endings. Then rerun the builds:
#   powershell -ExecutionPolicy Bypass -File tools\sync-capacity.ps1
#   powershell -ExecutionPolicy Bypass -File tools\build-outputs.ps1
#   powershell -ExecutionPolicy Bypass -File tools\build-dashboard.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'facility-classify.ps1')
$root = Split-Path -Parent $PSScriptRoot
$path = Join-Path $root 'wv-truck-parking-master.csv'
$rows = @(Import-Csv $path)
$headers = $rows[0].psobject.Properties.Name
$names = @{}; foreach ($r in $rows) { $names[$r.Name] = $true }
foreach ($k in $capSources.Keys) { if (-not $names.ContainsKey($k)) { Write-Warning "capacity source for '$k' has no master CSV row" } }
$changed = 0
foreach ($r in $rows) {
  $t = Format-CapText $(if ($capSources.ContainsKey($r.Name)) { $capSources[$r.Name] } else { $null })
  if ($r.'Truck spaces' -ne $t.spaces -or $r.'Count source' -ne $t.source) { $changed++ }
  $r.'Truck spaces' = $t.spaces; $r.'Count source' = $t.source
}
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append(($headers -join ',') + "`n")
foreach ($r in $rows) {
  [void]$sb.Append((($headers | ForEach-Object { '"' + ([string]$r.$_).Replace('"', '""') + '"' }) -join ',') + "`n")
}
[IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
Write-Host "sync-capacity: $changed of $($rows.Count) rows updated"
