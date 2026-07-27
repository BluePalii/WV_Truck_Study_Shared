# Fetches and parses truckstopsandservices.com (TSS) data for the WV truck-parking study.
#
# Downloads the TSS West Virginia category list pages (Truck Stops id=19, Rest Areas
# id=26, Secure Trailer Drop Yard & Parking id=107) and every location_details.php
# page they link, caching raw HTML under tss-cache\ (skipped when already cached;
# use -Force to refetch). Parses the labeled fields and joins TSS ids to master
# facility names via tools\tss-map.csv, writing wv-truck-parking-tss.csv.
# Also writes tss-cache\parsed.csv (every TSS listing, mapped or not) and prints
# TSS WV listings with no master match (expected: off-corridor panhandle sites).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\fetch-tss.ps1 [-Force] [-NoDownload]
param(
  [switch]$Force,
  [switch]$NoDownload
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$cache = Join-Path $root 'tss-cache'
$mapPath = Join-Path $PSScriptRoot 'tss-map.csv'
$outPath = Join-Path $root 'wv-truck-parking-tss.csv'
$base = 'https://www.truckstopsandservices.com'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
$cats = @{ '19' = 'Truck Stops'; '26' = 'Rest Areas'; '107' = 'Secure Trailer Drop Yard & Parking' }
if (-not (Test-Path $cache)) { New-Item -ItemType Directory $cache | Out-Null }

function Get-Page($url, $path) {
  if ($Force -or -not (Test-Path $path) -or (Get-Item $path).Length -eq 0) {
    if ($NoDownload) { return $false }
    Invoke-WebRequest -Uri $url -UserAgent $ua -OutFile $path -UseBasicParsing | Out-Null
    Start-Sleep -Milliseconds 400
  }
  return $true
}

# --- 1. list pages -> listing index (id, category, list-row name/hwy/exit/city) ---
$listings = @{}
foreach ($cid in $cats.Keys) {
  $lp = Join-Path $cache "list-$cid.html"
  Get-Page "$base/listcatbusinesses.php?id=$cid&state=50" $lp | Out-Null
  $html = Get-Content $lp -Raw
  $rowRe = "(?s)<tr><td class='producttext'[^>]*>(?:<img[^>]*>)?\s*</td><td class='producttext'[^>]*>" +
           "<a href='location_details\.php\?id=(\d+)'>([^<]*)</a></td>" +
           "<td class='producttext'[^>]*>([^<]*)</td><td class='producttext'[^>]*>([^<]*)</td>" +
           "<td class='producttext'[^>]*>([^<]*)</td>"
  foreach ($m in [regex]::Matches($html, $rowRe)) {
    $id = $m.Groups[1].Value
    if (-not $listings.ContainsKey($id)) {
      $listings[$id] = [pscustomobject]@{
        TssId = $id; Category = $cats[$cid]; ListName = $m.Groups[2].Value.Trim()
        ListHighway = $m.Groups[3].Value.Trim(); ListExit = $m.Groups[4].Value.Trim(); ListCity = $m.Groups[5].Value.Trim()
      }
    }
  }
}
Write-Host "TSS WV listings found: $($listings.Count)"

# --- 2. detail pages -> parsed records ---
function Get-Field($fields, $label) { if ($fields.ContainsKey($label)) { $fields[$label] } else { '' } }
$parsed = @{}
foreach ($id in $listings.Keys) {
  $dp = Join-Path $cache "$id.html"
  Get-Page "$base/location_details.php?id=$id" $dp | Out-Null
  if (-not (Test-Path $dp)) { continue }
  $html = Get-Content $dp -Raw
  $fields = @{}
  foreach ($m in [regex]::Matches($html, "<div class='locdetinfo'><b>([^:<]+):</b>\s*([^<]*)</div>")) {
    $fields[$m.Groups[1].Value.Trim()] = $m.Groups[2].Value.Trim()
  }
  $name = ''
  $m = [regex]::Match($html, "<h1 class='h2 locdetupper'>\s*([^<]+)")
  if ($m.Success) { $name = $m.Groups[1].Value.Trim() }
  $ratAvg = ''; $ratCnt = ''
  $m = [regex]::Match($html, 'Average Rating: ([0-9.]+) - Total Ratings: (\d+)')
  if ($m.Success) { $ratAvg = $m.Groups[1].Value; $ratCnt = $m.Groups[2].Value }
  $lat = ''; $lon = ''
  $m = [regex]::Match($html, 'staticmap\?center=(-?\d+\.\d+),(-?\d+\.\d+)')
  if ($m.Success) { $lat = $m.Groups[1].Value; $lon = $m.Groups[2].Value }
  $amen = ''
  $m = [regex]::Match($html, "(?s)<h3>Amenities</h3>\s*<p[^>]*>(.*?)</p>")
  if ($m.Success) { $amen = ($m.Groups[1].Value -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim() }
  $pay = ''
  $m = [regex]::Match($html, "(?s)<h3>Payment Methods Accepted</h3>\s*<p[^>]*>(.*?)</p>")
  if ($m.Success) { $pay = ($m.Groups[1].Value -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim() }
  $fb = ''
  $m = [regex]::Match($html, "(?s)<div class='custfeedback'><b>Customer Feedback:</b><br\s*/>(.*?)</div>")
  if ($m.Success) { $fb = ($m.Groups[1].Value -replace '<br\s*/?>', ' | ' -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim() }
  $l = $listings[$id]
  $parsed[$id] = [pscustomobject]@{
    TssId = $id; Category = $l.Category
    TssName = $(if ($name) { $name } else { $l.ListName })
    Highway = $(if (Get-Field $fields 'Highway') { Get-Field $fields 'Highway' } else { $l.ListHighway })
    Exit = $(if (Get-Field $fields 'Exit') { Get-Field $fields 'Exit' } else { $l.ListExit })
    StreetAddress = Get-Field $fields 'Street Address'
    City = $(if (Get-Field $fields 'City') { Get-Field $fields 'City' } else { $l.ListCity })
    State = Get-Field $fields 'State'
    PostalCode = Get-Field $fields 'Postal Code'
    Phone = Get-Field $fields 'Phone'
    Fax = Get-Field $fields 'Fax'
    Hours = Get-Field $fields 'Hours of Operation'
    ParkingSpots = Get-Field $fields '# of Parking Spots'
    ReservedSpots = Get-Field $fields '# of Reserved Parking Spots'
    PaidSpots = Get-Field $fields '# of Paid Parking Spots'
    FuelLanes = Get-Field $fields '# of Fuel Lanes'
    Showers = Get-Field $fields '# of Showers'
    ServiceBays = Get-Field $fields '# of Truck Service Bays'
    RatingAvg = $ratAvg; RatingCount = $ratCnt
    Latitude = $lat; Longitude = $lon
    Amenities = $amen; Payments = $pay; Feedback = $fb
    Url = "$base/location_details.php?id=$id"
  }
}
$parsed.Values | Sort-Object Category, TssName |
  Export-Csv (Join-Path $cache 'parsed.csv') -NoTypeInformation -Encoding UTF8
Write-Host "Parsed detail pages: $($parsed.Count) (full dump: tss-cache\parsed.csv)"

# --- 3. join to master facilities via tools\tss-map.csv ---
if (-not (Test-Path $mapPath)) {
  Write-Host 'tools\tss-map.csv not found - skipping master join (review tss-cache\parsed.csv to build it).'
  exit 0
}
$map = Import-Csv $mapPath
$today = Get-Date -Format 'yyyy-MM-dd'
$rows = @()
$mappedIds = @{}
foreach ($e in $map) {
  if (-not $e.TssId) { continue }
  $mappedIds[$e.TssId] = $true
  if (-not $parsed.ContainsKey($e.TssId)) { Write-Warning "Mapped TSS id $($e.TssId) ($($e.MasterName)) not in parsed listings"; continue }
  $p = $parsed[$e.TssId]
  $row = [ordered]@{ MasterName = $e.MasterName; MatchNote = $e.MatchNote; FetchedDate = $today }
  foreach ($prop in $p.PSObject.Properties) { $row[$prop.Name] = $prop.Value }
  $rows += [pscustomobject]$row
}
$rows | Sort-Object MasterName | Export-Csv $outPath -NoTypeInformation -Encoding UTF8
Write-Host "Wrote $outPath ($($rows.Count) facilities mapped to TSS records)"

$unmatched = $parsed.Values | Where-Object { -not $mappedIds.ContainsKey($_.TssId) } | Sort-Object Category, TssName
Write-Host "`nTSS WV listings with no master facility match ($(@($unmatched).Count)) - expected off-corridor or out-of-scope:"
foreach ($u in $unmatched) { Write-Host ("  [{0}] {1} {2} {3} exit {4} ({5})" -f $u.TssId, $u.TssName, $u.City, $u.Highway, $u.Exit, $u.Category) }
