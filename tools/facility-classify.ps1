# Shared classification data/functions for wv-truck-parking outputs.
# Dot-sourced by build-summary-pdf.ps1 and build-dashboard.ps1.
#
# Capacity figures mirror the master CSV "Truck spaces" column: published/field
# counts where available, otherwise satellite counts of all positions (occupied
# and open): the Nov 2026 algorithmic row counts (tools\satcount\) for the study
# locations that have them, else July 2026 by-eye counts. Open-apron area maxima
# are never used here. Only genuine ranges keep an analyst midpoint. class:
#   public / private / paid  = operating designated truck parking (counted in totals)
#   informal                 = usable but undesignated (counted separately)
#   candidate                = satellite-identified sites, not operating facilities
#   none                     = no truck capacity / closed / ghost

$cap = @{
  'I-64 Welcome Center East'                                    = @{mid=23;  class='public'}
  'Go-Mart #59 Huntington'                                      = @{mid=27;  class='private'}
  'Hurricane Rest Area East'                                    = @{mid=9;  class='public'}
  'Hurricane Rest Area West'                                    = @{mid=20;  class='public'}
  'TA Hurricane #149 (Teays Valley)'                            = @{mid=76;  class='private'}
  'Go-Mart #43 Teays Valley'                                    = @{mid=17;  class='private'}
  'Pilot Travel Center #243 Nitro'                              = @{mid=60;  class='private'}
  'Sandstone Visitor Center (NPS)'                              = @{mid=0;   class='none'}
  'Dawson truck stop (Exit 150 - CLOSED former facility)'       = @{mid=0;   class='none'}
  'Sam Black Church gravel pads (candidate - Exit 156)'         = @{mid=$null; class='candidate'}
  'Alta Truck Plaza / Alta Station (Mobil)'                     = @{mid=19;  class='private'; fixed=$true}  # field: 12 marked + 6-8 on gravel
  'Walmart Supercenter Lewisburg'                               = @{mid=$null; class='informal'}
  'Stop In Food Store #132 Caldwell (Exxon)'                    = @{mid=0;   class='none'}
  "Dixon's Truck Stop (legacy - Exit 175 area)"                 = @{mid=$null; class='none'}
  'I-64 Welcome Center West'                                    = @{mid=9;   class='public'}
  'Princeton Welcome Center'                                    = @{mid=10;  class='public'}
  'I-77 Truck Stop Princeton (NOT FOUND)'                       = @{mid=0;   class='none'}
  'Bluestone Travel Plaza'                                      = @{mid=79;  class='public'}
  'Camp Creek Wayside (I-77 SB MM 18 parking area)'             = @{mid=12;  class='public'}
  'Camp Creek Exxon (Exit 20)'                                  = @{mid=6;   class='informal'}
  'GoMart Truck Stop Beckley (Harper Rd)'                       = @{mid=28;  class='private'}
  'Beckley Travel Plaza'                                        = @{mid=165; class='public'}
  'Burnwell Rest Area (MM 69)'                                  = @{mid=8;  class='public'}
  'Morton Travel Plaza'                                         = @{mid=0;   class='none'}
  'GoMart #31 Charleston (W.U.T.S.)'                            = @{mid=31;  class='private'}
  'Go-Mart #33 Fairplain'                                       = @{mid=15;  class='private'}
  "Love's Travel Stop #378 Ripley/Fairplain"                    = @{mid=80;  class='private'}
  'Mineral Wells Rest Area NB'                                  = @{mid=10;  class='public'}
  'Mineral Wells Rest Area SB'                                  = @{mid=10;  class='public'}
  'TA Mineral Wells (Par Mar; former Liberty Truck Stop)'       = @{mid=104; class='private'}
  'GoMart Parkersburg (Camden Ave)'                             = @{mid=0;   class='none'}
  'Williamstown Welcome Center'                                 = @{mid=18;  class='public'}
  'US-19 / I-79 Exit 57 gravel pads (candidate)'                = @{mid=$null;  class='candidate'}
  'Mink Shoals frontage yard (candidate - I-79 Exit 1)'         = @{mid=30;  class='candidate'}
  'Go-Mart #86 Big Otter'                                       = @{mid=15;  class='private'}
  'Servia Rest Area North (Frametown)'                          = @{mid=16;  class='public'}
  'Servia Rest Area South (Frametown)'                          = @{mid=14;  class='public'}
  'Go-Mart Sutton (Exit 62 - UNVERIFIED)'                       = @{mid=8;   class='private'}
  'Pilot Travel Center #474 Sutton/Flatwoods'                   = @{mid=67;  class='private'}
  'Go-Mart #44 Flatwoods'                                       = @{mid=25;  class='private'}
  'Burnsville Rest Area South (Aspinall)'                       = @{mid=10;  class='public'}
  'Burnsville Rest Area North (Aspinall)'                       = @{mid=12;  class='public'}
  'TA Jane Lew (former Roady''s Jane Lew Truck Stop)'           = @{mid=75;  class='private'}
  'Bridgeport Hill Truck Stop (UNVERIFIED)'                     = @{mid=5;   class='private'}
  'Truck Parking Club lot Clarksburg (1800 N 12th St)'          = @{mid=10;  class='paid'}
  'Meadowbrook Rest Area South (Bridgeport)'                    = @{mid=14;  class='public'}
  'Meadowbrook Rest Area North (Bridgeport)'                    = @{mid=17;  class='public'}
  'K&T Truck Stop (Clark Travel Plaza) Fairmont'                = @{mid=20;  class='private'}
  'Pilot Travel Center #503 Morgantown'                         = @{mid=44;  class='private'}
  'I-79 Southbound Welcome Center (Morgantown/Star City)'       = @{mid=14;  class='public'}
  'Sheetz #457 Bradley/Mount Hope'                              = @{mid=0;   class='none'}
  'DTE Repair & Towing lot Oak Hill (Truck Parking Club)'       = @{mid=$null;  class='paid'}
  'Lochgelly Rd truck lot (Truck Parking Club)'                 = @{mid=12;  class='paid'}
  'Hico truck yard (candidate - US-19/US-60 junction)'          = @{mid=10;  class='candidate'}
  "U-Save Travel Plaza (Mabel's) Mount Nebo"                    = @{mid=125; class='private'}
  'Go-Mart #51 Mount Nebo'                                      = @{mid=20;  class='private'}
  'Sheetz Summersville'                                         = @{mid=0;   class='none'}
  'Walmart Supercenter Summersville'                            = @{mid=12;  class='informal'}
  'Little General / Exxon LG#2455 Birch River'                  = @{mid=6;   class='informal'}
  # Parking Study additions (Nov 2026); imagery-located, counts not established
  'I-64 Weigh Station EB (Hurricane)'                           = @{mid=3; class='informal'}
  'I-64 Weigh Station WB (Hurricane)'                           = @{mid=$null; class='informal'}
  'I-64 EB Brake Check Area (Exit 133 Bragg)'                   = @{mid=$null; class='informal'}
  'Sheetz Marmet (Exit 89)'                                     = @{mid=18;  class='private'}
  'Exxon Marmet (Exit 89)'                                      = @{mid=$null; class='informal'}
  'Boy Scouts of America free lot (US-19 - LOCATION UNKNOWN)'   = @{mid=$null; class='candidate'}
  'Birch River Scenic Overlook (US-19)'                         = @{mid=4; class='informal'}
}

function Get-CorridorGroup($c) {
  if ($c -like 'I-64*') { 'I-64' }
  elseif ($c -like 'I-77*') { 'I-77 (incl. Turnpike)' }
  elseif ($c -eq 'US-19 / I-79') { 'US-19 / I-79 junction' }
  elseif ($c -like 'I-79*') { 'I-79' }
  else { 'US-19 (Corridor L)' }
}
function Get-StatusShort($s) {
  if ($s -match 'UNDER CONSTRUCTION') { 'Under construction' }
  elseif ($s -match '^CLOSED') { 'Closed' }
  elseif ($s -match 'NOT FOUND') { 'Not found (ghost)' }
  elseif ($s -match 'renovation') { 'Open (renovation pending)' }
  elseif ($s -match '^Open') { 'Open' }
  elseif ($s -match '^(Unverified|Listed in directories)') { 'Unverified' }
  elseif ($s -match '^Existing gravel pads') { 'Informal pads' }
  elseif ($s -match '^Vacant pads') { 'Vacant pads (informal use)' }
  elseif ($s -match '^Active informal') { 'Informal/commercial use' }
  else { $s.Substring(0, [Math]::Min(30, $s.Length)) }
}
function Get-OwnerShort($o) {
  if ($o -like 'Public - state*') { 'Public (state)' }
  elseif ($o -like 'Public - federal*') { 'Public (federal)' }
  elseif ($o -like 'Private*') { ($o -replace '^Private - ', '') -replace ' \(.*$','' }
  else { 'Unknown' }
}
function Get-TypeGroup($t) {
  if ($t -like 'Truck stop*') { 'Truck stop' }
  elseif ($t -like 'Travel plaza*') { 'Travel plaza' }
  elseif ($t -like 'Rest area*') { 'Rest area' }
  elseif ($t -like 'Welcome center*') { 'Welcome center' }
  elseif ($t -like 'Parking-only wayside*') { 'Wayside (parking only)' }
  elseif ($t -like 'Paid reservable lot*') { 'Paid reservable lot' }
  elseif ($t -like 'Weigh station*') { 'Weigh station' }
  elseif ($t -like 'Brake check*') { 'Brake check area' }
  elseif ($t -like 'Scenic overlook*') { 'Scenic overlook' }
  elseif ($t -like 'Informal*') { 'Informal / candidate' }
  elseif ($t -match '^(Fuel|Gas station|C-store)') { 'Fuel only / no truck lot' }
  else { 'Other / closed / ghost' }
}
function Esc($t) { [System.Web.HttpUtility]::HtmlEncode($t) }
Add-Type -AssemblyName System.Web

# per-source truck-space figures (capacity-sources.csv + TSS + satellite counts):
# builds $capSources and re-derives each $cap mid from them (see the file header)
. (Join-Path $PSScriptRoot 'capacity-sources.ps1')
