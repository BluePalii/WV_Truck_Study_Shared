# Builds wv-truck-parking-report.html and wv-truck-parking-master.kml
# from wv-truck-parking-master.csv. Rerun after any CSV edit:
#   powershell -ExecutionPolicy Bypass -File tools\build-outputs.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$rows = Import-Csv (Join-Path $root 'wv-truck-parking-master.csv')

function Esc($s) {
    if ($null -eq $s) { return '' }
    $s = "$s" -replace '&', '&amp;'
    $s = $s -replace '<', '&lt;'
    $s = $s -replace '>', '&gt;'
    return $s
}

function CorridorGroup($c) {
    if ($c -like 'I-64*') { return 'I-64' }
    if ($c -like 'I-77*') { return 'I-77 (incl. WV Turnpike)' }
    if ($c -like 'I-79*') { return 'I-79' }
    return 'US-19 (Corridor L)'
}

# ---------- KML ----------
$kmlPlacemarks = New-Object System.Text.StringBuilder
foreach ($r in $rows) {
    if (-not $r.Latitude -or -not $r.Longitude) { continue }
    $style = 'private'
    if ($r.Ownership -like 'Public*') { $style = 'public' }
    if ($r.Confidence -eq 'Unresolved') { $style = 'uncertain' }
    $desc = Esc ("{0}. {1} | Access: {2} | Spaces: {3} | Status: {4} | Cost: {5} | Restrooms: {6} | Showers: {7} | 24/7 staff: {8} | Lighting: {9} | {10}" -f `
        $r.'Milepost / exit', $r.Ownership, $r.'Direction access', $r.'Truck spaces', $r.Status, $r.'Cost / reservation', $r.Restrooms, $r.Showers, $r.'24/7 staff', $r.Lighting, $r.Notes)
    $null = $kmlPlacemarks.AppendLine(("      <Placemark><name>{0}</name><styleUrl>#{1}</styleUrl><description>{2}</description><Point><coordinates>{3},{4},0</coordinates></Point></Placemark>" -f (Esc $r.Name), $style, $desc, $r.Longitude, $r.Latitude))
}

$corridorLines = @'
    <Folder>
      <name>Target corridors - dark lines</name>
      <Placemark><name>I-64</name><styleUrl>#targetRoute</styleUrl><LineString><tessellate>1</tessellate><altitudeMode>clampToGround</altitudeMode><coordinates>
        -82.612,38.414,0 -82.445,38.409,0 -82.270,38.425,0 -82.090,38.433,0 -81.947,38.414,0 -81.832,38.385,0 -81.633,38.349,0 -81.590,38.337,0 -81.459,38.305,0 -81.348,38.212,0 -81.258,38.095,0 -81.190,37.995,0 -81.114,37.886,0 -81.022,37.789,0 -80.920,37.777,0 -80.810,37.789,0 -80.650,37.826,0 -80.520,37.857,0 -80.385,37.853,0 -80.248,37.814,0 -80.087,37.792,0 -79.985,37.786,0 -79.850,37.778,0 -79.705,37.755,0
      </coordinates></LineString></Placemark>
      <Placemark><name>I-77</name><styleUrl>#targetRoute</styleUrl><LineString><tessellate>1</tessellate><altitudeMode>clampToGround</altitudeMode><coordinates>
        -81.127,37.225,0 -81.083,37.331,0 -81.072,37.493,0 -81.100,37.680,0 -81.156,37.778,0 -81.285,37.948,0 -81.420,38.115,0 -81.560,38.276,0 -81.633,38.349,0 -81.690,38.510,0 -81.725,38.695,0 -81.760,38.865,0 -81.770,39.030,0 -81.690,39.195,0 -81.565,39.335,0 -81.485,39.455,0
      </coordinates></LineString></Placemark>
      <Placemark><name>I-79</name><styleUrl>#targetRoute</styleUrl><LineString><tessellate>1</tessellate><altitudeMode>clampToGround</altitudeMode><coordinates>
        -81.633,38.349,0 -81.600,38.470,0 -81.500,38.620,0 -81.345,38.790,0 -81.230,38.930,0 -81.120,39.075,0 -80.930,39.170,0 -80.760,39.285,0 -80.620,39.420,0 -80.430,39.520,0 -80.280,39.635,0 -80.120,39.675,0 -79.970,39.655,0
      </coordinates></LineString></Placemark>
      <Placemark><name>US-19</name><styleUrl>#targetRoute</styleUrl><LineString><tessellate>1</tessellate><altitudeMode>clampToGround</altitudeMode><coordinates>
        -81.155,37.780,0 -81.100,37.915,0 -81.065,38.045,0 -80.985,38.175,0 -80.900,38.285,0 -80.860,38.405,0 -80.780,38.665,0 -80.720,38.780,0 -80.670,38.910,0
      </coordinates></LineString></Placemark>
    </Folder>
'@

$kml = @"
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>WV Truck Parking - Master Inventory</name>
    <description>Truck parking on I-64, I-77, I-79 and US-19 in West Virginia. Princeton Lowe's/Walmart parking excluded. Generated from wv-truck-parking-master.csv.</description>
    <Style id="public"><IconStyle><color>ff2e8b57</color><scale>1.1</scale><Icon><href>http://maps.google.com/mapfiles/kml/paddle/P.png</href></Icon></IconStyle></Style>
    <Style id="private"><IconStyle><color>ff1673c7</color><scale>1.1</scale><Icon><href>http://maps.google.com/mapfiles/kml/paddle/T.png</href></Icon></IconStyle></Style>
    <Style id="uncertain"><IconStyle><color>ff00a5ff</color><scale>1.1</scale><Icon><href>http://maps.google.com/mapfiles/kml/paddle/red-circle.png</href></Icon></IconStyle></Style>
    <Style id="targetRoute"><LineStyle><color>ff282828</color><width>7</width></LineStyle></Style>
$corridorLines
    <Folder><name>Facilities</name>
$($kmlPlacemarks.ToString())
    </Folder>
  </Document>
</kml>
"@
$kml | Out-File -Encoding utf8 (Join-Path $root 'wv-truck-parking-master.kml')
# Legacy Google Earth / My Maps deliverable stays in sync with master
$kml | Out-File -Encoding utf8 (Join-Path $root 'wv-truck-parking-google-earth.kml')

# ---------- Shareable CSV (Google My Maps import; Location column = coordinates) ----------
$shareable = foreach ($r in $rows) {
    $loc = if ($r.Latitude -and $r.Longitude) { "$($r.Latitude), $($r.Longitude)" } else { "$($r.Name), $($r.County) County, WV" }
    [pscustomobject]@{
        'Name'               = $r.Name
        'Location'           = $loc
        'Corridor'           = $r.Corridor
        'Milepost / exit'    = $r.'Milepost / exit'
        'Direction access'   = $r.'Direction access'
        'Facility type'      = $r.'Facility type'
        'Ownership'          = $r.Ownership
        'Truck spaces'       = $r.'Truck spaces'
        'Status'             = $r.Status
        'Cost / reservation' = $r.'Cost / reservation'
        'Restrooms'          = $r.Restrooms
        'Showers'            = $r.Showers
        '24/7 staff'         = $r.'24/7 staff'
        'Lighting'           = $r.Lighting
        'Fuel / diesel'      = $r.'Fuel / diesel'
        'Confidence'         = $r.Confidence
        'Notes'              = $r.Notes
    }
}
$shareable | Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $root 'wv-truck-parking-shareable.csv')

# ---------- HTML ----------
$groups = 'I-64', 'I-77 (incl. WV Turnpike)', 'I-79', 'US-19 (Corridor L)'
$sections = New-Object System.Text.StringBuilder

foreach ($g in $groups) {
    $inGroup = @($rows | Where-Object { (CorridorGroup $_.Corridor) -eq $g })
    if ($inGroup.Count -eq 0) { continue }
    $null = $sections.AppendLine("<h2 id=""$(($g -split ' ')[0])"">$(Esc $g) &mdash; $($inGroup.Count) locations</h2>")
    foreach ($r in $inGroup) {
        $badgeClass = 'b-dir'
        switch ($r.Confidence) {
            'Field-verified'       { $badgeClass = 'b-field' }
            'Official'             { $badgeClass = 'b-off' }
            'Operator-published'   { $badgeClass = 'b-off' }
            'Unresolved'           { $badgeClass = 'b-unres' }
            'Directory-conflicting'{ $badgeClass = 'b-conf' }
        }
        $statusHtml = Esc $r.Status
        if ($r.Status -match 'CONSTRUCTION|closed') { $statusHtml = "<span class=""warn"">$statusHtml</span>" }
        $img = ''
        if ($r.'Satellite image' -and (Test-Path (Join-Path $root "satellite\$($r.'Satellite image')"))) {
            $img = "<a href=""satellite/$($r.'Satellite image')"" target=""_blank""><img src=""satellite/$($r.'Satellite image')"" alt=""Satellite view of $(Esc $r.Name)"" loading=""lazy""></a>"
        } else {
            $img = '<div class="noimg">No satellite image (coordinates unresolved)</div>'
        }
        $mapLink = ''
        if ($r.Latitude -and $r.Longitude) {
            $mapLink = "<a href=""https://www.google.com/maps/search/?api=1&amp;query=$($r.Latitude)%2C$($r.Longitude)"" target=""_blank"">$($r.Latitude), $($r.Longitude) &mdash; open in Google Maps</a>"
        } else {
            $mapLink = 'coordinates not yet established'
        }
        $card = @"
<div class="card">
  <div class="imgcol">$img</div>
  <div class="info">
    <h3>$(Esc $r.Name) <span class="badge $badgeClass">$(Esc $r.Confidence)</span></h3>
    <p class="loc">$(Esc $r.Corridor) &middot; $(Esc $r.'Milepost / exit') &middot; $(Esc $r.County) County &middot; $mapLink</p>
    <table>
      <tr><th>Type / ownership</th><td>$(Esc $r.'Facility type') &middot; $(Esc $r.Ownership)</td><th>Direction access</th><td>$(Esc $r.'Direction access')</td></tr>
      <tr><th>Truck spaces</th><td><b>$(Esc $r.'Truck spaces')</b> <span class="src">($(Esc $r.'Count source'))</span></td><th>Status</th><td>$statusHtml</td></tr>
      <tr><th>Cost / reservation</th><td>$(Esc $r.'Cost / reservation')</td><th>Fuel / diesel</th><td>$(Esc $r.'Fuel / diesel')</td></tr>
      <tr><th>Restrooms</th><td>$(Esc $r.Restrooms)</td><th>Showers</th><td>$(Esc $r.Showers)</td></tr>
      <tr><th>24/7 staff</th><td>$(Esc $r.'24/7 staff')</td><th>Lighting</th><td>$(Esc $r.Lighting)</td></tr>
    </table>
    <p class="notes">$(Esc $r.Notes)</p>
    <p class="src">Sources: $(Esc $r.Sources)</p>
  </div>
</div>
"@
        $null = $sections.AppendLine($card)
    }
}

$generated = Get-Date -Format 'MMMM d, yyyy'
$total = $rows.Count

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>West Virginia Truck Parking Inventory - I-64, I-77, I-79, US-19</title>
<style>
  :root { color-scheme: light; }
  body { font-family: 'Segoe UI', system-ui, sans-serif; margin: 0; background:#f4f5f7; color:#1a2733; }
  header { background:#14304a; color:#fff; padding:28px 40px; }
  header h1 { margin:0 0 6px; font-size:26px; }
  header p { margin:2px 0; color:#c8d6e2; max-width:1100px; }
  nav { background:#0e2436; padding:10px 40px; }
  nav a { color:#9fc3e0; margin-right:22px; text-decoration:none; font-weight:600; }
  main { padding: 10px 40px 60px; max-width:1400px; margin:0 auto; }
  h2 { border-bottom:3px solid #14304a; padding-bottom:6px; margin-top:44px; }
  .card { display:flex; gap:18px; background:#fff; border:1px solid #dde3e9; border-radius:10px; padding:16px; margin:16px 0; box-shadow:0 1px 3px rgba(20,48,74,.08); }
  .imgcol { flex:0 0 380px; }
  .imgcol img { width:380px; border-radius:6px; display:block; }
  .noimg { width:380px; height:200px; display:flex; align-items:center; justify-content:center; background:#e9edf1; color:#7a8894; border-radius:6px; font-size:13px; text-align:center; }
  .info { flex:1; min-width:0; }
  .info h3 { margin:0 0 4px; font-size:18px; }
  .loc { color:#4a5b6a; font-size:13px; margin:0 0 10px; }
  table { border-collapse:collapse; width:100%; font-size:13px; }
  th { text-align:left; color:#4a5b6a; font-weight:600; padding:4px 10px 4px 0; white-space:nowrap; vertical-align:top; width:130px;}
  td { padding:4px 16px 4px 0; vertical-align:top; }
  tr { border-bottom:1px solid #eef1f4; }
  .notes { font-size:13px; margin:10px 0 4px; }
  .src { font-size:11.5px; color:#7a8894; }
  .badge { font-size:11px; padding:2px 9px; border-radius:20px; vertical-align:middle; font-weight:600; }
  .b-field { background:#d9f2e0; color:#166534; }
  .b-off   { background:#dbeafe; color:#1e40af; }
  .b-dir   { background:#eef1f4; color:#4a5b6a; }
  .b-unres { background:#fde8e8; color:#b91c1c; }
  .b-conf  { background:#fef3c7; color:#92400e; }
  .warn { color:#b91c1c; font-weight:700; }
  .intro { background:#fff; border:1px solid #dde3e9; border-radius:10px; padding:18px 22px; margin-top:24px; font-size:14px; }
  .intro ul { margin:8px 0; }
  a { color:#155e94; }
  @media (max-width: 900px){ .card{flex-direction:column;} .imgcol, .imgcol img, .noimg {width:100%; flex:none;} }
</style>
</head>
<body>
<header>
  <h1>West Virginia Truck Parking Inventory</h1>
  <p>Semi-truck parking on I-64, I-77 (WV Turnpike), I-79 and US-19 (Corridor L) &mdash; $total locations &middot; compiled $generated</p>
  <p>Each location reviewed for the criteria truckers weigh when choosing a lot: functionality, number/size of spaces, public vs. private, cost (pay-to-reserve is secondary; no WV state facility charges for parking), construction status, restrooms, showers, 24/7 staffing, lighting, and directional access.</p>
</header>
<nav><a href="#I-64">I-64</a><a href="#I-77">I-77 / Turnpike</a><a href="#I-79">I-79</a><a href="#US-19">US-19</a><a href="#gaps">Gaps &amp; candidates</a></nav>
<main>
<div class="intro">
  <b>How to read this document.</b> Every location card includes a current aerial/satellite image (Esri World Imagery; click to open full size) and a Google Maps link at the exact coordinates. Badges show data quality:
  <span class="badge b-field">Field-verified</span> visited by the study team &middot;
  <span class="badge b-off">Official / operator</span> state or operator-published &middot;
  <span class="badge b-dir">Directory</span> trucker directories, unconfirmed &middot;
  <span class="badge b-conf">Conflicting</span> sources disagree &middot;
  <span class="badge b-unres">Unresolved</span> existence or location uncertain &mdash; needs field check.
  Princeton Lowe's/Walmart informal parking is excluded by study scope.
</div>
$($sections.ToString())
<h2 id="gaps">Coverage gaps &amp; candidate sites for field review</h2>
<div class="intro">
<ul>
<li><b>I-64 Exit 1 Kenova/Ceredo:</b> WVDOT 2023 Truck Parking Profile flags recurring shoulder/ramp parking; no legal facility exists.</li>
<li><b>I-64 Exits 121-139 (Beckley east to Sandstone):</b> no designated facility on I-64 proper; Walmart Beckley (37.8056,-81.1768) absorbs informal demand.</li>
<li><b>I-64 Exit 150 "Dawson":</b> named on the study sketch but no directory lists any facility at Exits 139-156 &mdash; see Unresolved card; candidate for field visit.</li>
<li><b>I-77 Turnpike Morton gap:</b> with Morton Travel Plaza closed until ~Oct 31, 2026, northbound trucks have no public facility between Beckley MM 45 and Charleston.</li>
<li><b>I-77 free section Exits 99-124:</b> ~35-mile stretch with zero documented facilities; Ripley Exit 138 has only car-oriented stations.</li>
<li><b>I-79 Mink Shoals (Exits 1-9):</b> WVDOT documents recurring undesignated truck parking. July 2026 satellite sweep of Exits 0-2 found one linear truck/trailer yard NW of Exit 1 (~25-35 units; see Unresolved card) and no other truck-capable site; ramps and shoulders remain the only informal option &mdash; field-check.</li>
<li><b>I-79 Exits 91-99 (Weston):</b> July 2026 satellite scan of the Weston / US-33 area found no truck-capable facility; between the Burnsville rest areas (MM 84) and TA Jane Lew (Exit 105) there is no commercial truck parking on this corridor.</li>
<li><b>I-79 Clarksburg/Bridgeport Exits 119-125 and Fairmont/Morgantown Exits 132-155:</b> no branded truck stop despite heavy commercial development (except K&amp;T Exit 139 and Pilot Exit 146, both small relative to demand).</li>
<li><b>US-19 south half (Beckley to Oak Hill, ~20 mi):</b> zero documented truck parking; only paid reservable lots off-corridor in Oak Hill.</li>
<li><b>US-19 Hico (US-60 junction):</b> Sunoco + truck repair yard; suspected informal parking, undocumented.</li>
<li><b>US-19 at I-79 Exit 57:</b> truckers report shoulder/ramp parking at the junction; no facility exists.</li>
<li><b>Utilization context:</b> WVDOT measured I-79 truck parking at 83% peak utilization; Pilot Morgantown described as "always full"; TA Hurricane and Pilot Nitro "typically very congested" &mdash; expect overflow at every gap above.</li>
</ul>
</div>
<p class="src">Primary sources: WV511 Facilities; WVDOT Truck Parking Profile (Nov 2023); WV Parkways Authority / wvturnpike.com; operator sites (TA, Pilot, Love's, GoMart); trucker directories (AllStays, Trucker Path, TruckMap, Truck Parking Club); field visits July 2026. Satellite imagery: Esri World Imagery. Generated from wv-truck-parking-master.csv &mdash; edit the CSV and rerun tools/build-outputs.ps1 to update this page.</p>
</main>
</body>
</html>
"@
$html | Out-File -Encoding utf8 (Join-Path $root 'wv-truck-parking-report.html')
Write-Host "Wrote wv-truck-parking-report.html and wv-truck-parking-master.kml ($total facilities)"
