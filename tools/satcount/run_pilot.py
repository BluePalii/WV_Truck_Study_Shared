"""Satellite truck-parking count pilot.

For every site in satellite-count/lots.geojson:
  1. use (or fetch) its Esri World Imagery still + capture metadata
  2. detect large vehicles (YOLOv8-OBB, DOTA-pretrained; cached per image)
  3. occupied = de-duplicated detections whose centre lies in the lot polygon(s)
  4. capacity = sum over the lot's digitized parking rows (see satcount.py)
  5. empty    = capacity - occupied (flagged if negative)
Writes satellite-count/results.csv, rows.csv, overlays/<site>.jpg, and -- when
satellite-count/validation.csv has hand/field truth -- validation-results.csv.
Results are NEVER written into the master CSV.

Run:  python tools/satcount/run_pilot.py [--refetch] [--redetect]
"""
import argparse
import csv
import json
import math
import os
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import esri  # noqa: E402
import satcount as sc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "satellite-count")
WEIGHTS = os.path.join(HERE, "models", "yolov8x-obb.pt")
NMS_OVERLAP = 0.3
# Open, unmarked aprons: planning-standard footprint per parked tractor-trailer
# = a 14 ft x 75 ft stall (~98 m2) plus its half of a shared ~50 ft aisle
# (~32 m2) ~= 130 m2. Gives a ceiling for efficient angled parking, not a count.
AREA_PER_TRUCK_M2 = 130.0


def load_sites():
    fc = json.load(open(os.path.join(OUT, "lots.geojson")))
    sites = {}
    for f in fc["features"]:
        p = f["properties"]
        s = sites.setdefault(p["site_id"], {"site_id": p["site_id"], "master_name": p["master_name"],
                                            "study_id": p.get("study_id", ""), "spot_note": p.get("spot_note", ""),
                                            "lots": [], "rows": []})
        (s["lots"] if p["kind"] == "lot" else s["rows"]).append(f)
    return sites


def ensure_image(site, refetch=False):
    path = os.path.join(OUT, "images", site["site_id"] + ".png")
    if os.path.exists(path) and os.path.exists(path + ".json") and not refetch:
        return path, json.load(open(path + ".json"))
    pts = [c for f in site["lots"] for c in f["geometry"]["coordinates"][0]]
    pts += [c for f in site["rows"] for c in f["geometry"]["coordinates"]]
    lons, lats = [p[0] for p in pts], [p[1] for p in pts]
    lat, lon = (min(lats) + max(lats)) / 2, (min(lons) + max(lons)) / 2
    h = (max(lats) - min(lats)) * 111320 + 80
    w = (max(lons) - min(lons)) * 111320 * math.cos(math.radians(lat)) + 80
    return path, esri.fetch(lat, lon, w, h, path, 0.3)


def overlap_min(a, b, shape):
    """Intersection over the smaller box's area (catches a box nested in or
    side-by-side with another box for the same trailer, which IoU misses)."""
    ma = np.zeros(shape, np.uint8)
    mb = np.zeros(shape, np.uint8)
    cv2.fillPoly(ma, [np.asarray(a).astype(np.int32)], 1)
    cv2.fillPoly(mb, [np.asarray(b).astype(np.int32)], 1)
    small = min(ma.sum(), mb.sum())
    return (ma & mb).sum() / small if small else 0.0


def detections(site_id, bgr, path, redetect=False):
    cache = os.path.join(OUT, "detections", site_id + ".json")
    if os.path.exists(cache) and not redetect and os.path.getmtime(cache) > os.path.getmtime(path):
        raw = [(np.array(d["poly"]), d["conf"]) for d in json.load(open(cache))]
    else:
        cwd = os.getcwd()
        os.makedirs(os.path.dirname(WEIGHTS), exist_ok=True)
        os.chdir(os.path.dirname(WEIGHTS))       # ultralytics downloads weights into cwd
        try:
            raw = sc.detect_large_vehicles(bgr, os.path.basename(WEIGHTS))
        finally:
            os.chdir(cwd)
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        json.dump([{"poly": np.asarray(p).round(1).tolist(), "conf": round(c, 3)} for p, c in raw],
                  open(cache, "w"))
    # class-agnostic suppression on rotated boxes (the model sometimes emits two
    # boxes for one trailer, e.g. trailer + its shadow)
    raw = sorted(raw, key=lambda d: -d[1])
    keep = []
    for p, c in raw:
        if all(overlap_min(p, q, bgr.shape[:2]) < NMS_OVERLAP for q, _ in keep):
            keep.append((p, c))
    return keep


def to_px(meta, lonlat):
    x, y = esri.lonlat_to_px(meta, lonlat[1], lonlat[0])
    return [x, y]


def run(refetch=False, redetect=False):
    sites = load_sites()
    os.makedirs(os.path.join(OUT, "overlays"), exist_ok=True)
    results, row_rows, spot_rows = [], [], []
    for sid, site in sorted(sites.items()):
        path, meta = ensure_image(site, refetch)
        bgr = cv2.imread(path)
        gsd = meta["gsd_m"]
        img = meta["imagery"]
        det = detections(sid, bgr, path, redetect)
        rows_px = []
        for f in site["rows"]:
            p = dict(f["properties"])
            p["id"] = p.pop("row_id")
            p["p0"], p["p1"] = (to_px(meta, c) for c in f["geometry"]["coordinates"])
            rows_px.append(p)
        lots, area_lots = {}, {}
        for f in site["lots"]:
            poly = np.array([to_px(meta, c) for c in f["geometry"]["coordinates"][0]], np.float32)
            lots.setdefault(f["properties"]["lot_id"], []).append(poly)
            if f["properties"].get("area_estimate"):
                area_lots.setdefault(f["properties"]["lot_id"], []).append(poly)
        # only trucks inside a lot outline may occupy a spot (a row band can
        # poke past the outline onto a road or car lot)
        all_polys = [pp for ps in lots.values() for pp in ps]
        det = [(p, c) for p, c in det
               if any(cv2.pointPolygonTest(pp, tuple(float(v) for v in np.asarray(p).mean(axis=0)), False) >= 0
                      for pp in all_polys)] + [(p, c) for p, c in det
               if not any(cv2.pointPolygonTest(pp, tuple(float(v) for v in np.asarray(p).mean(axis=0)), False) >= 0
                          for pp in all_polys)]
        n_in = sum(1 for p, c in det if any(cv2.pointPolygonTest(pp, tuple(float(v) for v in np.asarray(p).mean(axis=0)), False) >= 0 for pp in all_polys))
        row_res = sc.analyze(bgr, rows_px, gsd, det[:n_in])
        in_spot = {sp["det"] for r in row_res for sp in r["spots"] if sp["det"] is not None}
        in_any_lot = np.zeros(len(det), bool)
        overlay = sc.draw_overlay(bgr, row_res, gsd)
        for lot_id, polys in sorted(lots.items()):
            hits = []
            for k, (p, c) in enumerate(det):
                ctr = np.asarray(p).mean(axis=0)
                if any(cv2.pointPolygonTest(pp, (float(ctr[0]), float(ctr[1])), False) >= 0 for pp in polys):
                    hits.append(k)
                    in_any_lot[k] = True
            lot_rows = [r for r in row_res if r["row"].get("lot_id", "all") == lot_id]
            spots = sum(r["capacity"] for r in lot_rows) if lot_rows else None
            occ_spots = sum(r["occupied_spots"] for r in lot_rows)
            empty_spots = sum(r["empty_spots"] for r in lot_rows)
            outside = [k for k in hits if k not in in_spot]
            flags = []
            if spots is None:
                flags.append("spots not counted (no rows digitized)")
            if outside:
                flags.append("%d truck(s) parked outside counted spots" % len(outside))
            if any(not r["pitch_method"].startswith("measured") and not sc.is_parallel(r["row"]) for r in lot_rows):
                flags.append("some rows use default spot width")
            if any(not r["row"].get("striped") for r in lot_rows):
                flags.append("unmarked rows: spot count is an estimate")
            if img.get("capture_date", "unknown") == "unknown":
                flags.append("image date unknown")
            area_m2 = sum(float(cv2.contourArea(pp)) for pp in area_lots.get(lot_id, [])) * gsd * gsd
            area_spots = int(area_m2 // AREA_PER_TRUCK_M2) if area_m2 else ""
            if area_m2:
                flags.append("area-based estimate only (open unmarked apron)")
            results.append({
                "study_id": site.get("study_id", ""), "site_id": sid, "lot_id": lot_id,
                "master_name": site["master_name"],
                "image_date": img.get("capture_date", "unknown"), "native_res_m": img.get("native_res_m", ""),
                "sensor": img.get("sensor", ""),
                "total_spots": "" if spots is None else spots,
                "occupied_spots": "" if spots is None else occ_spots,
                "empty_spots": "" if spots is None else empty_spots,
                "trucks_in_lot": len(hits), "trucks_outside_spots": len(outside),
                "area_m2": round(area_m2) if area_m2 else "", "area_based_spots": area_spots,
                "spot_note": site.get("spot_note", ""),
                "spot_basis": "; ".join("%s:%d@%.1fm(%s)" % (r["row"]["id"], r["capacity"], r["pitch_m"], r["pitch_method"])
                                        for r in lot_rows),
                "mean_det_conf": round(float(np.mean([det[k][1] for k in hits])), 2) if hits else "",
                "flags": "; ".join(flags),
            })
            for pp in polys:
                cv2.polylines(overlay, [(pp * 2).astype(np.int32)], True, (255, 255, 255), 2)
            for k in hits:
                col = (0, 0, 255) if k in in_spot else (255, 0, 255)   # magenta = outside counted spots
                cv2.polylines(overlay, [(np.asarray(det[k][0]) * 2).astype(np.int32)], True, col, 1)
        for k, (p, c) in enumerate(det):
            if not in_any_lot[k]:
                cv2.polylines(overlay, [(np.asarray(p) * 2).astype(np.int32)], True, (200, 200, 0), 1)
        for r in row_res:
            row_rows.append({
                "site_id": sid, "lot_id": r["row"].get("lot_id", "all"), "row_id": r["row"]["id"],
                "layout": "parallel" if sc.is_parallel(r["row"]) else "angle %s" % r["row"].get("angle_deg", 90),
                "striped": r["row"].get("striped", False), "length_m": round(r["length_m"], 1),
                "spot_width_along_row_m": round(r["pitch_m"], 2), "width_method": r["pitch_method"],
                "width_strength": round(r["pitch_strength"], 2), "spots": r["capacity"],
                "occupied_spots": r["occupied_spots"], "empty_spots": r["empty_spots"],
                "extra_trucks_in_row": len(r["extra_trucks"]),
                "occ_appearance_diagnostic": r["occ_appearance_diag"],
            })
            for sp in r["spots"]:
                spot_rows.append({"site_id": sid, "lot_id": r["row"].get("lot_id", "all"), "row_id": r["row"]["id"],
                                  "spot": sp["i"] + 1, "status": "occupied" if sp["det"] is not None else "empty",
                                  "det_conf": round(det[sp["det"]][1], 2) if sp["det"] is not None else ""})
        title = "%s  imagery %s (%s, native %s m)  red=occupied spot, green=empty spot, magenta=truck outside spots" % (
            sid, img.get("capture_date"), img.get("sensor"), img.get("native_res_m"))
        cv2.putText(overlay, title, (10, 28), 0, 0.7, (0, 0, 0), 4)
        cv2.putText(overlay, title, (10, 28), 0, 0.7, (255, 255, 255), 2)
        cv2.imwrite(os.path.join(OUT, "overlays", sid + ".jpg"), overlay, [cv2.IMWRITE_JPEG_QUALITY, 85])
        print("%-26s %s" % (sid, "; ".join("%s: %s spots, %s occ, %s empty, %d trucks (%d outside)" % (
            r["lot_id"], r["total_spots"] or "?", r["occupied_spots"], r["empty_spots"], r["trucks_in_lot"], r["trucks_outside_spots"])
            for r in results if r["site_id"] == sid)))
    write_csv(os.path.join(OUT, "results.csv"), results)
    write_csv(os.path.join(OUT, "rows.csv"), row_rows)
    write_csv(os.path.join(OUT, "spots.csv"), spot_rows)
    validate(results)


def write_csv(path, rows):
    if not rows:
        return
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()), lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def validate(results):
    vpath = os.path.join(OUT, "validation.csv")
    if not os.path.exists(vpath):
        return
    by_key = {(r["site_id"], r["lot_id"]): r for r in results}
    out = []
    for v in csv.DictReader(open(vpath, encoding="utf-8")):
        r = by_key.get((v["site_id"], v["lot_id"]))
        if not r:
            continue
        rec = {"site_id": v["site_id"], "lot_id": v["lot_id"], "image_date": r["image_date"],
               "occupied_algo": r["trucks_in_lot"], "occupied_truth": v["occupied_truth"],
               "occupied_truth_range": "%s-%s" % (v["occupied_truth_low"], v["occupied_truth_high"]),
               "occupied_error": int(r["trucks_in_lot"]) - int(v["occupied_truth"]),
               "occupied_within_truth_range": int(v["occupied_truth_low"]) <= int(r["trucks_in_lot"]) <= int(v["occupied_truth_high"]),
               "capacity_algo": r["total_spots"], "capacity_truth": v["capacity_truth"],
               "capacity_error": "", "capacity_pct_error": "", "capacity_truth_source": v["capacity_truth_source"]}
        if v["capacity_truth"] and r["total_spots"] != "":
            e = int(r["total_spots"]) - int(v["capacity_truth"])
            rec["capacity_error"] = e
            rec["capacity_pct_error"] = round(100.0 * e / int(v["capacity_truth"]), 1)
        out.append(rec)
    write_csv(os.path.join(OUT, "validation-results.csv"), out)
    if out:
        occ_err = [abs(o["occupied_error"]) for o in out]
        tot_a = sum(int(o["occupied_algo"]) for o in out)
        tot_t = sum(int(o["occupied_truth"]) for o in out)
        print("\nValidation (%d lots): occupied MAE %.2f trucks; total %d algo vs %d truth (%+.0f%%); %d/%d within truth range"
              % (len(out), np.mean(occ_err), tot_a, tot_t, 100.0 * (tot_a - tot_t) / tot_t,
                 sum(o["occupied_within_truth_range"] for o in out), len(out)))
        caps = [o for o in out if o["capacity_pct_error"] != ""]
        for o in caps:
            print("  capacity %s/%s: algo %s vs field %s (%+.1f%%)" % (o["site_id"], o["lot_id"], o["capacity_algo"],
                                                                     o["capacity_truth"], o["capacity_pct_error"]))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--refetch", action="store_true", help="re-download imagery even if cached")
    ap.add_argument("--redetect", action="store_true", help="re-run the detector even if cached")
    a = ap.parse_args()
    run(a.refetch, a.redetect)
