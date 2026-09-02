WV TRUCK PARKING — DOWNLOADABLE MAP PACKAGE

FILES
All map files are GENERATED from wv-truck-parking-master.csv (the master
inventory: one row per facility with coordinates, sources, confidence, and a
satellite image reference). Edit the master CSV, then rerun:
  powershell -ExecutionPolicy Bypass -File tools\build-outputs.ps1

1. wv-truck-parking-report.html
   Full illustrated report: one card per facility with satellite image,
   Google Maps link, data-quality badge, and a coverage-gaps section.

2. wv-truck-parking-google-earth.kml (identical: wv-truck-parking-master.kml)
   Open directly in Google Earth, or import into Google My Maps.
   It includes a separate "Target corridors — dark lines" folder/layer for
   I-64, I-77, I-79, and US-19.

3. wv-truck-parking-shareable.csv
   Open in Excel/Google Sheets, or import into Google My Maps using:
   - Location column: Location (contains exact "latitude, longitude" — more
     reliable than address search; several directory addresses were found to
     geocode to the wrong spot)
   - Marker title column: Name

GOOGLE MY MAPS IMPORT
1. Go to https://www.google.com/mymaps
2. Create a new map.
3. Click Add layer, then Import.
4. Upload either the KML or CSV file.
5. Share the resulting map using Google My Maps' Share button.

SCOPE AND CAUTIONS
- Covers the selected I-64, I-77, I-79 and US-19 corridors.
- Princeton Lowe's/Walmart truck parking is excluded.
- Princeton public/state facilities remain included.
- "Capacity unavailable" means a reliable facility-specific truck-space count
  was not found in the available public information.
- Verify construction/open status and private overnight-parking policies before
  a driver relies on a location.
- Commercial reservation apps do not represent live vacancy for an entire lot.

PRIMARY PUBLIC SOURCES
- WV511 Facilities: https://wv511.org/Facilities.aspx
- WVDOT Rest Areas GIS layer (facility data current as of Nov. 1, 2018):
  https://gis.transportation.wv.gov/arcgis/rest/services/Transportation/FeatureServer/7?f=pjson
- WVDOT Truck Parking Profile (2022 inventory / 2023 report):
  https://transportation.wv.gov/highways/Planning/Documents/Freight%20Plan/WVDOTFreightPlan_TruckParkingProfile_20231130_final.pdf
