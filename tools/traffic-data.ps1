# Toll + traffic layer manifest and CSV loader, dot-sourced by build-dashboard.ps1
# (same pattern as facility-classify.ps1). Defines which layers exist, whether
# each currently has real data, and why not when it doesn't -- see CLAUDE.md's
# "Traffic & toll data" ground rule for why most of these ship empty.
#
# hasData is always computed from actual CSV row count -- never hand-set --
# so the dashboard's "no data reported" UI can never drift out of sync with
# what's actually in traffic-data/.

$TRAFFIC_LAYERS = @(
  [pscustomobject]@{
    id = 'toll'; label = 'Toll facilities'; category = 'toll'; csv = 'toll-facilities.csv'
    defaultEnabled = $true; filterFields = @('Route', 'County', 'LayerType')
    unavailableReason = ''
    externalLink = $null
  },
  [pscustomobject]@{
    id = 'turnpike'; label = 'Turnpike toll transactions'; category = 'traffic'; csv = 'turnpike-toll-transactions.csv'
    defaultEnabled = $false; filterFields = @('Plaza', 'ReportingPeriod')
    unavailableReason = 'WV Parkways publishes traffic & revenue only as monthly PDF statements (no CSV/API). When populated this shows one manually-transcribed snapshot period, not live data.'
    externalLink = 'https://turnpike.wv.gov/investor-relations-information/investor-relations/traffic-and-revenue'
  },
  [pscustomobject]@{
    id = 'aadt'; label = 'AADT by segment'; category = 'traffic'; csv = 'aadt-segments.csv'
    defaultEnabled = $false; filterFields = @('Route', 'County', 'Direction')
    unavailableReason = 'WVDOT''s AADT map and GeoCounts are JS-rendered ArcGIS apps; no plain-HTTP export or public REST/GeoJSON endpoint could be located.'
    externalLink = 'https://gis.transportation.wv.gov/aadt/'
  },
  [pscustomobject]@{
    id = 'count'; label = 'Traffic count stations'; category = 'traffic'; csv = 'count-stations.csv'
    defaultEnabled = $false; filterFields = @('Route', 'County', 'Direction', 'StationType')
    unavailableReason = 'GeoCounts is a real public dashboard with export buttons, but exporting requires driving the UI -- no plain-HTTP export found.'
    externalLink = 'https://geocounts.com/traffic/wvdoh/'
  },
  [pscustomobject]@{
    id = 'wim'; label = 'Weigh-in-motion / commercial traffic'; category = 'traffic'; csv = 'wim-stations.csv'
    defaultEnabled = $false; filterFields = @('Route', 'County', 'Direction')
    unavailableReason = 'No public weigh-in-motion station export was found.'
    externalLink = 'https://geocounts.com/traffic/wvdoh/'
  },
  [pscustomobject]@{
    id = 'citations'; label = 'Citations & enforcement'; category = 'traffic'; csv = 'citations.csv'
    defaultEnabled = $false; filterFields = @('Route', 'County', 'OffenseCategory', 'Agency', 'CMVFlag')
    unavailableReason = 'WV Judiciary and GHSP reports are narrative PDF only -- no structured county-level citation/enforcement data was found. This layer is ready to import a sanitized public-records-request CSV using its documented schema.'
    externalLink = 'https://www.courtswv.gov/statistics/annual-reports'
  },
  [pscustomobject]@{
    id = 'crashes'; label = 'Crashes'; category = 'traffic'; csv = 'crashes.csv'
    defaultEnabled = $false; filterFields = @('Route', 'County', 'Severity')
    unavailableReason = 'NHTSA''s CDAN crash query tool is bot-protected (blocks direct fetches); no public export was found.'
    externalLink = 'https://cdan.dot.gov/query'
  },
  [pscustomobject]@{
    id = 'live'; label = 'Live conditions (WV511)'; category = 'traffic'; csv = $null
    defaultEnabled = $false; filterFields = @()
    unavailableReason = 'WV511 exposes no discoverable public incidents/closures feed (it runs on Google/INRIX/Waze, not a standard ArcGIS 511 platform) -- shown as an external link only, per the "documented external link instead of unsupported scraping" fallback.'
    externalLink = 'https://www.wv511.org/'
  }
)

function Get-TrafficLayers {
  param([Parameter(Mandatory)][string]$Root)
  $dataDir = Join-Path $Root 'traffic-data'
  $layers = @{}
  $meta = @()
  foreach ($def in $TRAFFIC_LAYERS) {
    $rows = @()
    if ($def.csv) {
      $csvPath = Join-Path $dataDir $def.csv
      if (Test-Path $csvPath) {
        $rawRows = @(Import-Csv $csvPath)
        $i = 0
        $rows = foreach ($r in $rawRows) {
          $raw = [ordered]@{}
          foreach ($p in $r.PSObject.Properties) { $raw[$p.Name] = $p.Value }
          $lat = $null; $lon = $null
          if ($raw.Contains('Latitude') -and $raw['Latitude'] -match '\d') { $lat = [double]$raw['Latitude'] }
          if ($raw.Contains('Longitude') -and $raw['Longitude'] -match '\d') { $lon = [double]$raw['Longitude'] }
          [pscustomobject]@{ id = $i; layer = $def.id; lat = $lat; lon = $lon; raw = $raw }
          $i++
        }
      }
    }
    $rows = @($rows)
    $hasData = $rows.Count -gt 0
    $layers[$def.id] = $rows
    $meta += [pscustomobject]@{
      id                = $def.id
      label             = $def.label
      category          = $def.category
      defaultEnabled    = $def.defaultEnabled
      filterFields      = $def.filterFields
      unavailableReason = $def.unavailableReason
      externalLink      = $def.externalLink
      hasData           = $hasData
      count             = $rows.Count
    }
  }
  [pscustomobject]@{ Meta = $meta; Layers = $layers }
}
