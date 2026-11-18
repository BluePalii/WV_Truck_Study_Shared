# Per-facility truck-space figures from every source, in a fixed order:
#   1. Public sources   (study-team field counts, WVDOT, WV Parkways Authority, NPS,
#                        WVDOT reports, the study corridor sketch)  - capacity-sources.csv
#   2. Private sources  (operator websites, Truck Parking Club, directories, press)
#                        - capacity-sources.csv, then TruckStopsAndServices.com
#                        (wv-truck-parking-tss.csv, refreshed by tools\fetch-tss.ps1)
#   3. Satellite count  (tools\satcount\ algorithm; satellite-count\study-summary.csv)
# and whether the numbers agree. Dot-sourced by facility-classify.ps1, so every
# build (dashboard, report, summary PDF) and tools\sync-capacity.ps1 (which writes
# the master CSV "Truck spaces" / "Count source" columns) use the same figures.
#
# capacity-sources.csv columns: Name (master Name), Group (Public|Private), Source,
# Spaces (integer total used for comparison; blank = no number published), Figure
# (as published), Retrieved (date checked), Url, Note. Edit that file -- not the
# master CSV columns -- when a source changes, then run tools\sync-capacity.ps1
# and tools\build-outputs.ps1 / tools\build-dashboard.ps1.
#
# Study capacity estimate ($cap mid) is derived from these figures, in priority:
#   study-team field count > operator's own site/listing > WV Parkways Authority/NPS
#   > WVDOT Rest Areas GIS layer > satellite row count > median of directories.
# The corridor sketch and area-based satellite maxima are never used. Facilities
# with class 'none' stay 0; a $cap entry with fixed=$true keeps its hand-set mid.

function Get-CapKind($src) {
  if ($src -match 'field count') { 'field' }
  elseif ($src -match 'official site|Truck Parking Club') { 'operator' }
  elseif ($src -match 'Parkways Authority|National Park') { 'agency' }
  elseif ($src -match '^WVDOT Rest Areas') { 'wvdot' }
  elseif ($src -match 'corridor sketch') { 'sketch' }
  elseif ($src -match '^WVDOT') { 'report' }
  else { 'directory' }
}

function Get-CapacitySources($Root) {
  $by = @{}
  function Add-E($name, $e) { if (-not $by.ContainsKey($name)) { $by[$name] = New-Object System.Collections.ArrayList }; [void]$by[$name].Add($e) }
  $toInt = { param($v) if ("$v" -match '^\s*\d+\s*$') { [int]$v } else { $null } }

  $man = @(); $p = Join-Path $Root 'capacity-sources.csv'
  if (Test-Path $p) { $man = @(Import-Csv $p) }
  foreach ($g in 'Public', 'Private') {
    foreach ($m in ($man | Where-Object { $_.Group -eq $g })) {
      Add-E $m.Name ([ordered]@{ group = $g; source = $m.Source; spaces = (& $toInt $m.Spaces); figure = $m.Figure
        retrieved = $m.Retrieved; url = $m.Url; note = $m.Note; kind = (Get-CapKind $m.Source) })
    }
    if ($g -eq 'Private') {
      $tp = Join-Path $Root 'wv-truck-parking-tss.csv'
      if (Test-Path $tp) {
        foreach ($t in Import-Csv $tp) {
          $n = & $toInt $t.ParkingSpots
          $fig = $(if ($null -ne $n) { "$n" } else { 'listed; no parking count published' })
          if ($t.ReservedSpots -match '^[1-9]') { $fig += " ($($t.ReservedSpots) reserved)" }
          if ($t.PaidSpots -match '^[1-9]') { $fig += " ($($t.PaidSpots) paid)" }
          Add-E $t.MasterName ([ordered]@{ group = 'Private'; source = 'TruckStopsAndServices.com (TSS)'; spaces = $n; figure = $fig
            retrieved = $t.FetchedDate; url = $t.Url; note = ''; kind = 'directory' })
        }
      }
    }
  }
  $sp = Join-Path $Root 'satellite-count\study-summary.csv'
  if (Test-Path $sp) {
    foreach ($c in Import-Csv $sp) {
      $rows = & $toInt $c.satellite_row_spots; $area = & $toInt $c.satellite_area_spots
      if ($null -eq $rows -and $null -eq $area) { continue }
      if ($null -ne $rows) {
        $fig = "$rows spots counted along parking rows"
        if ($c.satellite_occupied_spots -ne '') { $fig += " ($($c.satellite_occupied_spots) occupied, $($c.satellite_empty_spots) empty on the image)" }
        if ($null -ne $area) { $fig += "; open pad: up to $area more (area-based maximum, not a count)" }
      } else { $fig = "up to $area (area-based maximum, not a count)" }
      Add-E $c.location ([ordered]@{ group = 'Satellite'; source = "Satellite count (Esri World Imagery dated $($c.image_date))"; spaces = $rows
        figure = $fig; retrieved = '2026-11 (counted)'; url = ''; note = 'counting aid, not yet accepted (methodology.md section 2b)'; kind = 'satellite'
        image_date = $c.image_date })
    }
  }
  $by
}

# agreement across every numeric figure (sketch included -- it is a listed figure; area maxima are not numbers)
function Get-CapAgreement($entries) {
  $vals = @($entries | Where-Object { $null -ne $_.spaces } | ForEach-Object { $_.spaces })
  $u = @($vals | Sort-Object -Unique)
  if ($vals.Count -eq 0) { [ordered]@{ status = 'none'; n = 0; min = $null; max = $null; text = 'No published count found' } }
  elseif ($vals.Count -eq 1) { [ordered]@{ status = 'single'; n = 1; min = $u[0]; max = $u[0]; text = "Single source: $($u[0])" } }
  elseif ($u.Count -eq 1) { [ordered]@{ status = 'agree'; n = $vals.Count; min = $u[0]; max = $u[0]; text = "All $($vals.Count) sources agree: $($u[0])" } }
  else { [ordered]@{ status = 'differ'; n = $vals.Count; min = $u[0]; max = $u[-1]; text = "Sources differ: $($u[0]) to $($u[-1])" } }
}

function Get-CapMid($entries) {
  foreach ($k in 'field', 'operator', 'agency', 'wvdot', 'satellite') {
    $e = @($entries | Where-Object { $_.kind -eq $k -and $null -ne $_.spaces })
    if ($e.Count) { return $e[0].spaces }
  }
  $d = @($entries | Where-Object { $_.kind -eq 'directory' -and $null -ne $_.spaces } | ForEach-Object { $_.spaces } | Sort-Object)
  if ($d.Count) { return [int][Math]::Round(($d[[Math]::Floor(($d.Count - 1) / 2)] + $d[[Math]::Ceiling(($d.Count - 1) / 2)]) / 2) }
  $null
}

# text for the master CSV columns
function Format-CapText($entries) {
  if (-not $entries -or $entries.Count -eq 0) { return @{ spaces = 'No published count found'; source = 'none found' } }
  $parts = @(); $srcs = @()
  foreach ($g in 'Public', 'Private', 'Satellite') {
    $ge = @($entries | Where-Object { $_.group -eq $g })
    if (-not $ge.Count) { continue }
    $parts += $(if ($g -eq 'Satellite') { '' } else { "$g - " }) +(($ge | ForEach-Object { "$($_.source): $($_.figure)" }) -join '; ')
    $srcs += ($ge | ForEach-Object { $_.source })
  }
  $a = Get-CapAgreement $entries
  @{ spaces = (($parts -join ' | ') + ' | ' + $a.text); source = ($srcs -join '; ') }
}

$capRoot = Split-Path -Parent $PSScriptRoot
$capSources = Get-CapacitySources $capRoot
foreach ($k in @($cap.Keys)) {
  $e = $cap[$k]
  if ($e.class -eq 'none' -or $e.fixed) { continue }
  if ($capSources.ContainsKey($k)) {
    $m = Get-CapMid $capSources[$k]
    $e.mid = $m
  } else { $e.mid = $null }
}
