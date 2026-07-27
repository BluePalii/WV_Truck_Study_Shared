# Builds wv-truck-parking-summary.html (print-styled) from wv-truck-parking-master.csv,
# then prints it to wv-truck-parking-summary.pdf with headless Microsoft Edge.
# Rerun after any master CSV edit:
#   powershell -ExecutionPolicy Bypass -File tools\build-summary-pdf.ps1
#
# Capacity midpoint estimates below are analyst-assigned midpoints of the ranges in the
# "Truck spaces" column (see CSV for the underlying text and source). class:
#   public / private / paid  = operating designated truck parking (counted in totals)
#   informal                 = usable but undesignated (counted separately)
#   candidate                = satellite-identified sites, not operating facilities
#   none                     = no truck capacity / closed / ghost

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$csvPath = Join-Path $root 'wv-truck-parking-master.csv'
$htmlPath = Join-Path $root 'wv-truck-parking-summary.html'
$pdfPath = Join-Path $root 'wv-truck-parking-summary.pdf'
$rows = Import-Csv $csvPath

# capacity table + classification helpers shared with build-dashboard.ps1
. (Join-Path $PSScriptRoot 'facility-classify.ps1')

# ---- computed aggregates ----
$total = $rows.Count
$corrOrder = @('I-64','I-77 (incl. Turnpike)','I-79','US-19 (Corridor L)','US-19 / I-79 junction')
$byCorr = @{}; foreach ($c in $corrOrder) { $byCorr[$c] = @() }
foreach ($r in $rows) { $byCorr[(Get-CorridorGroup $r.Corridor)] += ,$r }

$classSum = @{public=0; private=0; paid=0; informal=0; candidate=0}
$classCnt = @{public=0; private=0; paid=0; informal=0; candidate=0; none=0}
$classUnk = @{public=0; private=0; paid=0; informal=0; candidate=0}
foreach ($r in $rows) {
  $e = $cap[$r.Name]
  if ($null -eq $e) { throw "No capacity entry for: $($r.Name)" }
  $classCnt[$e.class]++
  if ($e.class -ne 'none') {
    if ($null -ne $e.mid) { $classSum[$e.class] += $e.mid } else { $classUnk[$e.class]++ }
  }
}
$designated = $classSum.public + $classSum.private + $classSum.paid
$operatingCnt = $classCnt.public + $classCnt.private + $classCnt.paid

# corridor capacity (designated classes only)
$corrCap = @{}
foreach ($c in $corrOrder) {
  $s = 0; $u = 0
  foreach ($r in $byCorr[$c]) {
    $e = $cap[$r.Name]
    if ($e.class -in 'public','private','paid') {
      if ($null -ne $e.mid) { $s += $e.mid } else { $u++ }
    }
  }
  $corrCap[$c] = @{sum=$s; unk=$u}
}

# status + confidence counts
$statusCounts = $rows | ForEach-Object { Get-StatusShort $_.Status } | Group-Object | Sort-Object Count -Descending
$confCounts = $rows | Group-Object Confidence | Sort-Object Count -Descending
$openCnt = ($rows | Where-Object { (Get-StatusShort $_.Status) -like 'Open*' }).Count

# ---- HTML fragments ----
function TableRows($pairs) {
  ($pairs | ForEach-Object { "<tr><td>$($_[0])</td><td class='num'>$($_[1])</td></tr>" }) -join "`n"
}

$corrTable = ($corrOrder | ForEach-Object {
  $n = $byCorr[$_].Count
  $capS = $corrCap[$_].sum
  $unkNote = if ($corrCap[$_].unk -gt 0) { " (+$($corrCap[$_].unk) facility count not published)" } else { '' }
  $capCell = if ($capS -gt 0) { "~$capS$unkNote" } else { 'candidate site only' }
  "<tr><td>$(Esc $_)</td><td class='num'>$n</td><td>$capCell</td></tr>"
}) -join "`n"

$confTable = ($confCounts | ForEach-Object { "<tr><td>$(Esc $_.Name)</td><td class='num'>$($_.Count)</td></tr>" }) -join "`n"
$statusTable = ($statusCounts | ForEach-Object { "<tr><td>$(Esc $_.Name)</td><td class='num'>$($_.Count)</td></tr>" }) -join "`n"

# roster grouped by corridor; data-* attributes drive the interactive filters in the HTML
$roster = ''
foreach ($c in $corrOrder) {
  $roster += "<tr class='corr-head' data-corr=`"$(Esc $c)`" data-total='$($byCorr[$c].Count)'><td colspan='8'>$(Esc $c) — $($byCorr[$c].Count) facilities</td></tr>`n"
  foreach ($r in $byCorr[$c]) {
    $sp = $r.'Truck spaces'; if ($sp.Length -gt 58) { $sp = $sp.Substring(0,55) + '…' }
    $ty = $r.'Facility type'; if ($ty.Length -gt 34) { $ty = $ty.Substring(0,31) + '…' }
    $mp = $r.'Milepost / exit'; if ($mp.Length -gt 34) { $mp = $mp.Substring(0,31) + '…' }
    $ac = $r.'Direction access' -replace ' \(field-verified.*?\)','' -replace 'field-verified: access and facilities both directions','field-verified'
    if ($ac.Length -gt 26) { $ac = $ac.Substring(0,23) + '…' }
    $attrs = "class='fac' data-corr=`"$(Esc $c)`" data-type=`"$(Esc (Get-TypeGroup $r.'Facility type'))`" data-own=`"$(Esc (Get-OwnerShort $r.Ownership))`" data-status=`"$(Esc (Get-StatusShort $r.Status))`" data-conf=`"$(Esc $r.Confidence)`""
    $roster += "<tr $attrs><td class='name'>$(Esc $r.Name)</td><td>$(Esc $mp)</td><td>$(Esc $ac)</td><td>$(Esc $ty)</td><td>$(Esc (Get-OwnerShort $r.Ownership))</td><td>$(Esc $sp)</td><td>$(Esc (Get-StatusShort $r.Status))</td><td>$(Esc $r.Confidence)</td></tr>`n"
  }
}

# filter bar + script (single-quoted here-string: no PowerShell interpolation inside)
$filterUi = @'
<div class="filters">
  <input type="text" id="f-search" placeholder="Search name / exit&hellip;">
  <select id="f-type" data-key="type"><option value="">All types</option></select>
  <select id="f-corr" data-key="corr"><option value="">All corridors</option></select>
  <select id="f-own" data-key="own"><option value="">All ownership</option></select>
  <select id="f-status" data-key="status"><option value="">All statuses</option></select>
  <select id="f-conf" data-key="conf"><option value="">All confidence</option></select>
  <button type="button" id="f-reset">Reset</button>
  <span id="f-count"></span>
</div>
<script>
// runs after DOM load: this block is emitted above the roster table, so the
// rows do not exist yet at script-parse time
document.addEventListener('DOMContentLoaded', function () {
  var facRows = Array.prototype.slice.call(document.querySelectorAll('table.roster tr.fac'));
  var headRows = Array.prototype.slice.call(document.querySelectorAll('table.roster tr.corr-head'));
  var selects = Array.prototype.slice.call(document.querySelectorAll('.filters select'));
  var search = document.getElementById('f-search');
  var count = document.getElementById('f-count');

  selects.forEach(function (sel) {
    var key = sel.getAttribute('data-key'), seen = {};
    facRows.forEach(function (r) { seen[r.getAttribute('data-' + key)] = true; });
    Object.keys(seen).sort().forEach(function (v) {
      var o = document.createElement('option');
      o.value = v; o.textContent = v; sel.appendChild(o);
    });
  });

  function apply() {
    var q = search.value.toLowerCase();
    var shown = 0;
    facRows.forEach(function (r) {
      var ok = selects.every(function (sel) {
        return !sel.value || r.getAttribute('data-' + sel.getAttribute('data-key')) === sel.value;
      });
      if (ok && q) { ok = r.textContent.toLowerCase().indexOf(q) !== -1; }
      r.style.display = ok ? '' : 'none';
      if (ok) { shown++; }
    });
    headRows.forEach(function (h) {
      var c = h.getAttribute('data-corr');
      var vis = facRows.filter(function (r) {
        return r.getAttribute('data-corr') === c && r.style.display !== 'none';
      }).length;
      h.style.display = vis ? '' : 'none';
      h.firstChild.textContent = c + ' — ' + vis + ' of ' + h.getAttribute('data-total') + ' facilities';
    });
    count.textContent = 'Showing ' + shown + ' of ' + facRows.length + ' locations';
  }

  selects.forEach(function (sel) { sel.addEventListener('change', apply); });
  search.addEventListener('input', apply);
  document.getElementById('f-reset').addEventListener('click', function () {
    selects.forEach(function (sel) { sel.value = ''; });
    search.value = '';
    apply();
  });
  apply();
});
</script>
'@

$today = Get-Date -Format 'MMMM d, yyyy'

$html = @"
<!doctype html>
<html><head><meta charset="utf-8">
<title>WV Truck Parking Study — Comprehensive Summary</title>
<style>
  @page { size: letter; margin: 0.55in 0.6in; }
  * { box-sizing: border-box; }
  body { font-family: 'Segoe UI', Arial, sans-serif; color: #1a2332; font-size: 10.5pt; line-height: 1.45; margin: 0; }
  h1 { font-size: 21pt; margin: 0 0 2px; color: #0f2a4a; letter-spacing: -0.3px; }
  h2 { font-size: 13.5pt; color: #0f2a4a; border-bottom: 2px solid #0f2a4a; padding-bottom: 3px; margin: 26px 0 10px; }
  h3 { font-size: 11pt; color: #0f2a4a; margin: 16px 0 6px; }
  .subtitle { color: #4a5a70; font-size: 11pt; margin-bottom: 2px; }
  .meta { color: #6b7a90; font-size: 9pt; margin-bottom: 18px; }
  .band { border-top: 5px solid #0f2a4a; padding-top: 14px; }
  table { border-collapse: collapse; width: 100%; margin: 6px 0 14px; }
  th { background: #0f2a4a; color: #fff; text-align: left; font-size: 8.5pt; text-transform: uppercase; letter-spacing: 0.4px; padding: 5px 8px; }
  td { border-bottom: 1px solid #d7dde6; padding: 4.5px 8px; vertical-align: top; font-size: 9.5pt; }
  tr:nth-child(even) td { background: #f4f6f9; }
  td.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .kf { width: 100%; border-collapse: collapse; margin: 12px 0 6px; }
  .kf td { border: 1px solid #d7dde6; background: #f4f6f9 !important; padding: 10px 12px; width: 25%; }
  .kf .v { font-size: 17pt; font-weight: 700; color: #0f2a4a; display: block; line-height: 1.15; }
  .kf .l { font-size: 8.5pt; color: #4a5a70; text-transform: uppercase; letter-spacing: 0.4px; }
  ul { margin: 6px 0 12px; padding-left: 20px; }
  li { margin-bottom: 5px; }
  .note { font-size: 9pt; color: #4a5a70; font-style: italic; }
  .two-col { display: flex; gap: 24px; }
  .two-col > div { flex: 1; }
  .roster td { font-size: 8pt; padding: 3.5px 6px; }
  .roster th { font-size: 7.5pt; padding: 4px 6px; }
  .roster .name { font-weight: 600; }
  .corr-head td { background: #dfe6ef !important; font-weight: 700; color: #0f2a4a; font-size: 9pt; }
  .page-break { page-break-before: always; }
  .filters { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin: 10px 0 4px; }
  .filters input, .filters select, .filters button { font-family: inherit; font-size: 9.5pt; padding: 4px 8px; border: 1px solid #b9c4d3; border-radius: 4px; background: #fff; color: #1a2332; }
  .filters input { width: 190px; }
  .filters button { cursor: pointer; background: #0f2a4a; color: #fff; border-color: #0f2a4a; }
  #f-count { font-size: 9pt; color: #4a5a70; margin-left: auto; }
  @media print { .filters { display: none; } }
  tr { page-break-inside: avoid; }
  .footer { margin-top: 24px; padding-top: 8px; border-top: 1px solid #d7dde6; font-size: 8.5pt; color: #6b7a90; }
</style></head><body>

<div class="band">
<h1>West Virginia Truck Parking Study</h1>
<div class="subtitle">Comprehensive inventory summary — semi-truck parking on I-64, I-77 (WV Turnpike), I-79, and US-19 (Corridor L)</div>
<div class="meta">Generated $today from wv-truck-parking-master.csv · $total facilities inventoried across 17 counties</div>
</div>

<h2>Executive summary</h2>
<p>This study inventoried <b>$total locations</b> relevant to semi-truck parking on the four target corridors, spanning 17 West Virginia counties from the Kentucky, Virginia, Ohio, and Pennsylvania lines. Of these, <b>$operatingCnt are operating facilities with designated truck parking</b>, providing an estimated <b>~$designated truck spaces</b> ($($classSum.public) public, $($classSum.private) at private truck stops, $($classSum.paid) in paid reservable lots). The remainder are informal/big-box locations (~$($classSum.informal)+ undesignated spaces), satellite-identified candidate sites (~$($classSum.candidate)+ potential spaces), fuel-only stops, and resolved closures or directory ghosts. Three sites were field-verified by the study team in July 2026; all other counts derive from operator publications, directories, or satellite imagery analysis and are flagged accordingly.</p>

<table class="kf"><tr>
<td><span class="v">$total</span><span class="l">Locations inventoried</span></td>
<td><span class="v">$operatingCnt</span><span class="l">Operating facilities w/ designated truck parking</span></td>
<td><span class="v">~$designated</span><span class="l">Estimated designated truck spaces</span></td>
<td><span class="v">3</span><span class="l">Field-verified (July 2026)</span></td>
</tr></table>
<p class="note">Space totals use analyst midpoints of published/imagery ranges; two public facilities (I-64 Welcome Center East, I-79 SB Welcome Center) have truck parking with no published count and add to the total. No WV state facility charges for parking.</p>

<h2>Facilities and capacity by corridor</h2>
<table><tr><th>Corridor</th><th>Facilities inventoried</th><th>Est. designated truck spaces (operating)</th></tr>
$corrTable
<tr><td><b>Total</b></td><td class="num"><b>$total</b></td><td><b>~$designated</b></td></tr>
</table>

<h2>Capacity by category</h2>
<table><tr><th>Category</th><th>Facilities</th><th>Est. spaces</th><th>Notes</th></tr>
<tr><td>Public (state / federal) — open</td><td class="num">$($classCnt.public)</td><td class="num">~$($classSum.public)</td><td>Welcome centers, rest areas, Turnpike travel plazas, waysides; all free; 2 counts unpublished</td></tr>
<tr><td>Private truck stops — open</td><td class="num">$($classCnt.private)</td><td class="num">~$($classSum.private)</td><td>Free general parking; 7 offer paid reserved spots (TA Reserve-It, Pilot Prime, Love's app); 2 unverified</td></tr>
<tr><td>Paid reservable lots (Truck Parking Club)</td><td class="num">$($classCnt.paid)</td><td class="num">~$($classSum.paid)</td><td>Clarksburg (&#36;15/day), Oak Hill ×2 (~&#36;25/day); app-booked; no amenities</td></tr>
<tr><td>Informal / big-box (undesignated)</td><td class="num">$($classCnt.informal)</td><td class="num">~$($classSum.informal)+</td><td>Walmart lots (manager discretion), gravel aprons; not designated truck parking</td></tr>
<tr><td>Candidate sites (satellite-identified)</td><td class="num">$($classCnt.candidate)</td><td class="num">~$($classSum.candidate)+</td><td>Not operating facilities; strongest: US-19/I-79 Exit 57 gravel pads (40–60 semis)</td></tr>
<tr><td>No usable capacity (closed / ghost / fuel-only / day-use)</td><td class="num">$($classCnt.none)</td><td class="num">0</td><td>Incl. Morton Travel Plaza (rebuild, due Oct 2026), Dawson (closed), Princeton Exit 9 ghost listing</td></tr>
</table>

<div class="two-col">
<div>
<h2>Operational status</h2>
<table><tr><th>Status</th><th>Facilities</th></tr>
$statusTable
</table>
</div>
<div>
<h2>Data confidence</h2>
<table><tr><th>Confidence level</th><th>Facilities</th></tr>
$confTable
</table>
</div>
</div>

<h2>Amenities at the $operatingCnt operating designated facilities</h2>
<table><tr><th>Amenity</th><th>Yes</th><th>No</th><th>Unknown / conflicting</th><th>Notes</th></tr>
<tr><td>Restrooms</td><td class="num">37</td><td class="num">2</td><td class="num">3</td><td>No: Camp Creek Wayside (parking only), TPC Clarksburg</td></tr>
<tr><td>Showers</td><td class="num">10</td><td class="num">27</td><td class="num">5</td><td>All at private truck stops (TA ×3, Pilot ×3, Love's, K&amp;T, U-Save, Go-Mart #44); no public facility has showers</td></tr>
<tr><td>24/7 staffing</td><td class="num">17</td><td class="num">21</td><td class="num">4</td><td>Incl. rebuilt Bluestone &amp; Beckley plazas (24/7 Mountain State Market); welcome centers staffed daytime only</td></tr>
<tr><td>Truck diesel</td><td class="num">22</td><td class="num">20</td><td class="num">0</td><td>All 20 truck stops + Bluestone and Beckley plazas (separated tractor-trailer fueling)</td></tr>
<tr><td>Lighting confirmed</td><td class="num">13</td><td class="num">0</td><td class="num">29</td><td>Largest data gap in the inventory — flag for field verification</td></tr>
<tr><td>Paid reservation option</td><td class="num">10</td><td class="num">32</td><td class="num">0</td><td>Reservation apps cover only reserved spots, never whole-lot vacancy</td></tr>
</table>

<h2>Directional access</h2>
<p><b>17 facilities are single-direction only</b> — all of them public: EB-only (I-64 Welcome Center East, Hurricane Rest Area East), WB-only (Hurricane West, I-64 Welcome Center West), NB-only (Bluestone Travel Plaza, Morton, Mineral Wells NB, Servia NB, Burnsville NB, Meadowbrook NB), and SB-only (Camp Creek Wayside, Burnwell, Mineral Wells SB, Servia SB, Burnsville SB, Meadowbrook SB, I-79 SB Welcome Center). Every private truck stop offers both-direction access via its exit. Beckley Travel Plaza serves both directions via the Exit 45 ramps despite sitting on the SB side.</p>

<h2 class="page-break">Key findings and coverage gaps</h2>
<ul>
<li><b>Morton Travel Plaza is demolished</b> (rebuild contract completion Oct 31, 2026): zero interim spaces at NB MM 72. NB Turnpike trucks have no public facility between Beckley MM 45 and the GoMart at Exit 95 — a 50-mile gap with only Burnwell (SB-only) between.</li>
<li><b>I-64 east of Nitro is nearly empty:</b> Alta Truck Plaza (Exit 161, field-verified open, ~19 spaces) is the only truck stop between Pilot Nitro (Exit 45) and the Virginia line outside the Turnpike. One directory wrongly lists Alta as closed.</li>
<li><b>Known congestion:</b> WVDOT's 2023 Truck Parking Profile flags Pilot Morgantown as "always full" and TA Hurricane / Pilot Nitro as "typically very congested." Pilot #474 Sutton is frequently cited as filling overnight.</li>
<li><b>Servia rest areas (I-79 MM 49, both directions)</b> have a &#36;21M renovation contract awarded June 30, 2026 — expect closures during construction; they are the nearest public parking to the north end of US-19 Corridor L.</li>
<li><b>Turnpike rebuilds complete except Morton:</b> Beckley Travel Plaza reopened Dec 30, 2024 with 165 truck spaces (largest lot on the corridor, +35); Bluestone reopened mid-Jan 2025 with 79 (+10).</li>
<li><b>Directory ghosts and stale data resolved:</b> "I-77 Truck Stop Princeton" (Exit 9) does not exist; Camp Creek Exxon's 104-space listing was stale data from old Bluestone; GoMart Parkersburg's 10-space claim is unsupported by imagery; Go-Mart #33 Fairplain's 15-space claim is doubtful on imagery.</li>
<li><b>Formalization candidates found by satellite:</b> US-19/I-79 Exit 57 gravel pads (strongest — two ~200×250 ft pads, 40–60 semis, visible gore-area parking nearby), Mink Shoals I-79 Exit 1 frontage yard (~25–35 trucks, WVDOT-flagged area), Hico US-19/US-60 yard, and Sam Black Church I-64 Exit 156 pads.</li>
<li><b>Largest facilities:</b> Beckley Travel Plaza (165, public), U-Save/Mabel's Mount Nebo (~100–150, largest on Corridor L), TA Mineral Wells (104), Love's Ripley (80), Bluestone (79), TA Hurricane (76), TA Jane Lew (75), Pilot Sutton (67).</li>
<li><b>Princeton Lowe's/Walmart informal parking is excluded</b> by study ground rules; Princeton public facilities (Bluestone, Camp Creek Wayside, Princeton Welcome Center) are included.</li>
</ul>

<h2>Field-verified data points (study team, July 2026)</h2>
<table><tr><th>Facility</th><th>Verified findings</th></tr>
<tr><td>GoMart Truck Stop Beckley — I-77 Exit 44 (Harper Rd), Raleigh Co.</td><td>28 dedicated truck spots; both-direction access and facilities; 24 hr (directory figure of 18 is outdated)</td></tr>
<tr><td>Camp Creek Wayside — I-77 SB MM 18, Mercer Co.</td><td>12 truck spots; SB access only; no facilities (parking only)</td></tr>
<tr><td>Alta Truck Plaza (Mobil) — I-64 Exit 161, Greenbrier Co.</td><td>Open (contradicting one directory); 12 marked spots + gravel for ~6–8 more; both-direction access and facilities</td></tr>
</table>

<h2 class="page-break">Full facility roster ($total locations)</h2>
$filterUi
<table class="roster"><tr><th>Facility</th><th>Milepost / exit</th><th>Access</th><th>Type</th><th>Ownership</th><th>Truck spaces (as recorded)</th><th>Status</th><th>Confidence</th></tr>
$roster
</table>

<div class="footer">
Source: wv-truck-parking-master.csv (this study's master inventory). Primary public sources: WV511 Facilities (wv511.org), WVDOT Rest Areas GIS layer, WVDOT Truck Parking Profile 2023, WV Parkways Authority, operator sites (TA, Pilot, Love's), truck-stop directories (AllStays and others), Esri World Imagery satellite analysis (July 2026), and study-team field visits (July 2026). Companion outputs: illustrated HTML report, Google Earth KML, and Google My Maps shareable CSV, all generated from the same master CSV.
</div>

</body></html>
"@

Set-Content -Path $htmlPath -Value $html -Encoding UTF8

# print to PDF with headless Edge
$edge = @(
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'msedge.exe not found' }
$uri = 'file:///' + ($htmlPath -replace '\\','/')
Start-Process -FilePath $edge -ArgumentList @('--headless','--disable-gpu',"--print-to-pdf=`"$pdfPath`"",'--no-pdf-header-footer',$uri) -Wait -NoNewWindow
if (Test-Path $pdfPath) { Write-Host "Wrote $pdfPath" } else { throw 'PDF was not produced' }
