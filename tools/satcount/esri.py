"""Esri World Imagery fetch + capture-metadata lookup (no API key needed).

Imagery is requested in Web Mercator (EPSG:3857) at a fixed *ground* sampling
distance, so every pixel maps to a known number of meters on the ground. Each
image is saved with a sidecar JSON holding the exact bbox, ground resolution,
and the Esri capture metadata (date, native resolution, sensor) for the site.
"""
import json
import math
import os

import requests

EXPORT = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export"
IDENTIFY = "https://services.arcgisonline.com/arcgis/rest/services/World_Imagery/MapServer/identify"
UA = {"User-Agent": "wv-truck-parking-study/1.0"}
R = 6378137.0
MAX_PX = 4096


def to_merc(lat, lon):
    x = math.radians(lon) * R
    y = math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * R
    return x, y


def to_lonlat(x, y):
    lon = math.degrees(x / R)
    lat = math.degrees(2 * math.atan(math.exp(y / R)) - math.pi / 2)
    return lat, lon


def capture_metadata(lat, lon):
    """Return Esri's capture metadata for the imagery at a point.

    Uses the World Imagery MapServer identify op; the high-resolution layer
    attributes include DATE (YYYYMMDD), RESOLUTION (M), ACCURACY (M), sensor
    DESCRIPTION and SOURCE. Returns {} when nothing is found -- callers must
    record 'unknown' rather than assume a date.
    """
    d = 0.001
    params = {
        "geometry": f"{lon},{lat}", "geometryType": "esriGeometryPoint", "sr": 4326,
        "layers": "all", "tolerance": 1, "returnGeometry": "false", "f": "json",
        "mapExtent": f"{lon - d},{lat - d},{lon + d},{lat + d}", "imageDisplay": "800,800,96",
    }
    try:
        res = requests.get(IDENTIFY, params=params, headers=UA, timeout=60).json().get("results", [])
    except (requests.RequestException, ValueError):
        return {}
    # Prefer the 30cm layer, then 60cm, then the composite layer 0.
    by_name = {r.get("layerName"): r.get("attributes", {}) for r in res}
    for name in ("High Resolution 30cm Imagery", "High Resolution 60cm Imagery", "World Imagery"):
        a = by_name.get(name)
        if a and a.get("DATE (YYYYMMDD)") not in (None, "", "Null"):
            dt = a["DATE (YYYYMMDD)"]
            return {
                "capture_date": f"{dt[:4]}-{dt[4:6]}-{dt[6:8]}",
                "native_res_m": float(a.get("RESOLUTION (M)") or "nan"),
                "accuracy_m": float(a.get("ACCURACY (M)") or "nan"),
                "sensor": a.get("DESCRIPTION", ""),
                "source": f"{a.get('SOURCE', '')} / {a.get('SOURCE_INFO', '')}".strip(" /"),
                "release": a.get("ReleaseName", ""),
            }
    return {}


def fetch(lat, lon, width_m, height_m, out_png, gsd_m=0.3):
    """Fetch an image centered on lat/lon covering width_m x height_m of ground.

    gsd_m is the requested ground sampling distance (m/px). The export endpoint
    returns HTTP 500 for requests much finer than ~0.3 m/px. Esri's native
    imagery in rural WV is typically 0.3-0.5 m; finer requests are resampled.
    Writes out_png plus out_png + '.json' (georeference + capture metadata).
    """
    k = 1.0 / math.cos(math.radians(lat))  # mercator meters per ground meter
    cx, cy = to_merc(lat, lon)
    w_px = min(MAX_PX, int(round(width_m / gsd_m)))
    h_px = min(MAX_PX, int(round(height_m / gsd_m)))
    half_w, half_h = w_px * gsd_m * k / 2, h_px * gsd_m * k / 2
    bbox = (cx - half_w, cy - half_h, cx + half_w, cy + half_h)
    params = {
        "bbox": ",".join(f"{v:.3f}" for v in bbox), "bboxSR": 3857, "imageSR": 3857,
        "size": f"{w_px},{h_px}", "format": "png", "f": "image",
    }
    r = requests.get(EXPORT, params=params, headers=UA, timeout=120)
    r.raise_for_status()
    if not r.headers.get("Content-Type", "").startswith("image"):
        raise RuntimeError(f"Esri export did not return an image: {r.text[:200]}")
    os.makedirs(os.path.dirname(os.path.abspath(out_png)), exist_ok=True)
    with open(out_png, "wb") as f:
        f.write(r.content)
    meta = {
        "center": [lat, lon], "bbox_3857": bbox, "size_px": [w_px, h_px],
        "gsd_m": gsd_m, "width_m": w_px * gsd_m, "height_m": h_px * gsd_m,
        "imagery": capture_metadata(lat, lon) or {"capture_date": "unknown"},
    }
    with open(out_png + ".json", "w") as f:
        json.dump(meta, f, indent=2)
    return meta


def px_to_lonlat(meta, px, py):
    x0, y0, x1, y1 = meta["bbox_3857"]
    w, h = meta["size_px"]
    return to_lonlat(x0 + (x1 - x0) * px / w, y1 - (y1 - y0) * py / h)


def lonlat_to_px(meta, lat, lon):
    x0, y0, x1, y1 = meta["bbox_3857"]
    w, h = meta["size_px"]
    x, y = to_merc(lat, lon)
    return (x - x0) / (x1 - x0) * w, (y1 - y) / (y1 - y0) * h


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser(description="Fetch one Esri World Imagery still + metadata")
    ap.add_argument("lat", type=float)
    ap.add_argument("lon", type=float)
    ap.add_argument("out")
    ap.add_argument("--width", type=float, default=300, help="ground width in meters")
    ap.add_argument("--height", type=float, default=None, help="ground height in meters")
    ap.add_argument("--gsd", type=float, default=0.3, help="meters per pixel (>= ~0.3)")
    a = ap.parse_args()
    m = fetch(a.lat, a.lon, a.width, a.height or a.width, a.out, a.gsd)
    print(json.dumps(m["imagery"]), m["size_px"])
