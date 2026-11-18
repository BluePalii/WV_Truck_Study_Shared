"""Build satellite-count/study-summary.csv: one row per Parking Study location
(tools/study-map.csv), combining the satellite results (results.csv), field-
verified counts (digitizing files), the published master-CSV figure, and the
findings for locations that could not be analyzed (site-findings.csv).

"total_spots" picks, in order:
  1. field-verified count (study team, July 2026)
  2. satellite row-based spot count (+ area ceiling for any open pad on the site)
  3. satellite area-based estimate (open unmarked apron; ceiling, not a count)
and always names its source. "occupied_at_image" = trucks detected in the lot
on the image date; "empty_at_image" is counted per spot where rows exist, and
estimated (total - occupied) otherwise -- "empty_method" says which.
Published figures are shown for comparison only.

Run after run_pilot.py:  python tools/satcount/summarize.py
"""
import csv
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "satellite-count")


def main():
    master = {r["Name"]: r for r in csv.DictReader(open(os.path.join(ROOT, "wv-truck-parking-master.csv"), encoding="utf-8"))}
    study = list(csv.DictReader(open(os.path.join(HERE, "..", "study-map.csv"), encoding="utf-8")))
    res = {r["study_id"]: r for r in csv.DictReader(open(os.path.join(OUT, "results.csv"), encoding="utf-8")) if r["study_id"]}
    findings = {r["study_id"]: r["finding"] for r in csv.DictReader(open(os.path.join(OUT, "site-findings.csv"), encoding="utf-8"))}
    sites = {}
    for p in glob.glob(os.path.join(OUT, "digitizing", "*.json")):
        s = json.load(open(p))
        sites[s.get("study_id", "")] = s
    out = []
    for st in study:
        sid = st["StudyId"]
        m = master.get(st["MasterName"], {})
        r = res.get(sid, {})
        s = sites.get(sid, {})
        field = (s.get("field_capacity") or {}).get("value", "")
        rows_n = int(r["total_spots"]) if r.get("total_spots", "") != "" else None
        area_n = int(r["area_based_spots"]) if r.get("area_based_spots", "") != "" else None
        trucks = int(r["trucks_in_lot"]) if r.get("trucks_in_lot", "") != "" else None
        outside = int(r.get("trucks_outside_spots") or 0)
        empty_rows = int(r["empty_spots"]) if r.get("empty_spots", "") != "" else None
        if field != "":
            best, src = int(field), "field-verified (July 2026)"
            empty = max(0, best - trucks) if trucks is not None else ""
            how = "field-verified spots minus trucks detected (image and field visit are different dates)"
        elif rows_n is not None and area_n is not None:
            best, src = rows_n + area_n, "satellite: counted spots along rows + area-based ceiling for open pad"
            empty = empty_rows + max(0, area_n - outside)
            how = "per-spot count on rows + (area ceiling minus trucks on the open pad)"
        elif rows_n is not None:
            best, src = rows_n, "satellite: counted spots along digitized rows"
            empty, how = empty_rows, "per-spot count: each spot labelled occupied/empty"
        elif area_n is not None:
            best, src = area_n, "satellite: area-based ceiling (open unmarked apron)"
            empty = max(0, area_n - trucks) if trucks is not None else ""
            how = "area ceiling minus trucks detected (estimate)"
        else:
            best, src, empty, how = "", "not available", "", ""
        out.append({
            "study_id": sid, "site_id": s.get("site_id", ""), "location": st["MasterName"], "corridor": m.get("Corridor", ""),
            "image_date": r.get("image_date", ""),
            "total_spots": best, "total_spots_source": src,
            "occupied_at_image": "" if trucks is None else trucks,
            "empty_at_image": empty, "empty_method": how,
            "satellite_row_spots": "" if rows_n is None else rows_n,
            "satellite_occupied_spots": r.get("occupied_spots", ""), "satellite_empty_spots": r.get("empty_spots", ""),
            "trucks_outside_spots": r.get("trucks_outside_spots", ""),
            "satellite_area_spots": "" if area_n is None else area_n,
            "field_verified_spots": field, "published_spots_master_csv": m.get("Truck spaces", ""),
            "flags": r.get("flags", ""),
            "note": "; ".join(x for x in (s.get("spot_note", ""), findings.get(sid, "")) if x),
        })
    with open(os.path.join(OUT, "study-summary.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()), lineterminator="\n")
        w.writeheader()
        w.writerows(out)
    print("wrote study-summary.csv (%d locations)" % len(out))


if __name__ == "__main__":
    main()
