"""Convert lot polygons / parking rows digitized in *pixel* coordinates of a
reference image (fetched by esri.py, with its .json sidecar) into lat/lon
GeoJSON features, and merge them into satellite-count/lots.geojson.

Input JSON (one site):
{
  "site_id": "gomart-beckley-harper",
  "master_name": "GoMart Truck Stop Beckley (Harper Rd)",
  "image": "satellite-count/images/gomart-beckley-harper.png",
  "lots":  [{"lot_id": "all", "polygon": [[x, y], ...]}],
  "rows":  [{"id": "N", "lot_id": "all", "p0": [x, y], "p1": [x, y], "side": -1,
             "angle_deg": 78, "depth_m": 21, "striped": true, "note": "..."}]
}
Usage: python digitize.py site.json [site2.json ...]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import esri  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LOTS = os.path.join(ROOT, "satellite-count", "lots.geojson")


def px2ll(meta, xy):
    lat, lon = esri.px_to_lonlat(meta, xy[0], xy[1])
    return [round(lon, 7), round(lat, 7)]


def site_features(site):
    meta = json.load(open(os.path.join(ROOT, site["image"]) + ".json"))
    common = {"site_id": site["site_id"], "master_name": site["master_name"], "study_id": site.get("study_id", ""),
              "digitized_on": os.path.relpath(site["image"]).replace("\\", "/"),
              "digitized_image_date": meta["imagery"].get("capture_date", "unknown"),
              "spot_note": site.get("spot_note", "")}
    feats = []
    for lot in site.get("lots", []):
        ring = [px2ll(meta, p) for p in lot["polygon"]]
        ring.append(ring[0])
        extra = {k: v for k, v in lot.items() if k not in ("polygon", "lot_id", "note")}
        feats.append({"type": "Feature", "geometry": {"type": "Polygon", "coordinates": [ring]},
                      "properties": dict(common, kind="lot", lot_id=lot["lot_id"], note=lot.get("note", ""), **extra)})
    for row in site.get("rows", []):
        props = {k: v for k, v in row.items() if k not in ("p0", "p1")}
        props.update(common, kind="row", row_id=props.pop("id"))
        feats.append({"type": "Feature",
                      "geometry": {"type": "LineString", "coordinates": [px2ll(meta, row["p0"]), px2ll(meta, row["p1"])]},
                      "properties": props})
    return feats


VALIDATION = os.path.join(ROOT, "satellite-count", "validation.csv")
VCOLS = ["site_id", "study_id", "lot_id", "occupied_truth", "occupied_truth_low", "occupied_truth_high",
         "occupied_truth_method", "capacity_truth", "capacity_truth_source", "notes"]


def write_validation():
    """Rebuild validation.csv from every digitizing file's blind_count /
    field_capacity (the blind count is recorded in the file BEFORE the model
    is run on that site)."""
    import csv
    import glob
    rows = []
    for p in sorted(glob.glob(os.path.join(ROOT, "satellite-count", "digitizing", "*.json"))):
        s = json.load(open(p))
        b = s.get("blind_count")
        if not b:
            continue
        fc = s.get("field_capacity") or {}
        rows.append({"site_id": s["site_id"], "study_id": s.get("study_id", ""), "lot_id": "all",
                     "occupied_truth": b["occupied"], "occupied_truth_low": b["low"], "occupied_truth_high": b["high"],
                     "occupied_truth_method": "blind hand count from the same image, recorded before model output was viewed",
                     "capacity_truth": fc.get("value", ""), "capacity_truth_source": fc.get("source", ""),
                     "notes": b.get("note", "")})
    with open(VALIDATION, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=VCOLS, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    print("validation.csv:", len(rows), "sites")


def main(paths):
    fc = json.load(open(LOTS)) if os.path.exists(LOTS) else {"type": "FeatureCollection", "features": []}
    import glob
    live = {json.load(open(p))["site_id"] for p in glob.glob(os.path.join(ROOT, "satellite-count", "digitizing", "*.json"))}
    fc["features"] = [f for f in fc["features"] if f["properties"]["site_id"] in live]
    for p in paths:
        site = json.load(open(p))
        fc["features"] = [f for f in fc["features"] if f["properties"]["site_id"] != site["site_id"]]
        fc["features"].extend(site_features(site))
        print("digitized", site["site_id"])
    fc["features"].sort(key=lambda f: (f["properties"]["site_id"], f["properties"]["kind"]))
    with open(LOTS, "w") as f:
        json.dump(fc, f, indent=1)
    write_validation()


if __name__ == "__main__":
    main(sys.argv[1:])
