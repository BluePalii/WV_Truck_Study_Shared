"""Core algorithm: truck-parking capacity + occupied/empty counts from one
georeferenced satellite still (see esri.py) and hand-digitized parking rows.

Model
-----
A lot is described as one or more *parking rows*. A row is a baseline P0->P1
drawn along the stall mouths (the aisle-side edge), plus:
  side       +1 / -1  which side of the baseline the stalls are on
                      (+1 = to the right of P0->P1 as seen on screen, y down)
  angle_deg  angle between the stall axis and the baseline
             (90 = perpendicular, 30-80 = angled/echelon, 0 = parallel)
  depth_m    stall depth along the stall axis (tractor-trailer ~21 m)
  width_m    parallel rows only: lane width (default 3.7 m)
  striped    true if painted stall lines are visible
  pitch_m    optional fixed along-row pitch (overrides measurement/defaults)

Capacity (how many trucks the row holds)
  angled/perpendicular rows: along-row pitch measured from the image --
                 autocorrelation of a brightness profile sampled across the
                 stall mouths (painted stripes, and parked trucks themselves,
                 repeat at the pitch actually used). Accepted only when there
                 is a clear interior autocorrelation peak (>= 0.15); otherwise
                 the default 4.3 m / sin(angle) is used and flagged.
  parallel rows: 23 m per truck (no usable period).
  capacity     = floor(row length / pitch + 0.25)

Occupancy -- the PILOT (run_pilot.py) counts occupied trucks as de-duplicated
detector boxes inside the digitized lot polygon. The two row-level signals
below are also computed and written to rows.csv for diagnosis only: on the
pilot lots the appearance signal could not separate stained/patched empty
concrete from white trailers (see methodology.md, section 2b).
  appearance : an along-row *occupancy profile*. At each position along the
               baseline, the cross-section of the stall band (along the stall
               axis, 15-85% of depth) is compared with the row's aisle
               pavement colour in CIE-Lab; the position is "occupied" when at
               least half the cross-section differs by > DE_PX. The profile is
               median-filtered (removes painted stripes and noise), and each
               occupied run of length L becomes
                   n = max(1, round((L + pitch - w) / pitch))
               trucks, where w is a truck's footprint along the row
               (2.6 m / sin(angle); 21 m for parallel rows). This is
               independent of where the stall grid happens to start.
  detector   : count of YOLOv8-OBB (DOTA-pretrained) 'large vehicle' boxes
               whose centre lies in the row's stall band.
  fused      : max(appearance, detector) -- the detector is high-precision
               but low-recall on 0.3-0.5 m imagery, so it can only raise a
               count the appearance signal missed.
  empty      = max(0, capacity - occupied); occupied > capacity is flagged
               (trucks parked outside marked positions / overflow).
"""
import math

import cv2
import numpy as np

DEFAULT_PERP_PITCH_M = 4.3       # 14 ft stall, measured perpendicular to the stall axis
DEFAULT_PARALLEL_PITCH_M = 23.0  # tractor-trailer (~21 m) + gap, parallel parking
TRUCK_WIDTH_M = 2.6
TRUCK_LEN_PARALLEL_M = 21.0
DE_PX = 18.0                     # Lab delta-E for a pixel to count as "not pavement"
XSEC_OCC = 0.5                   # cross-section occupied if >= 50% of it differs
MEDIAN_M = 1.0                   # median-filter window along the row (m)
MIN_RUN_M = 1.5                  # ignore occupied runs shorter than this (perpendicular m)
DET_CONF = 0.10
UPSAMPLE = 2.0                   # detector runs on a 2x upsampled image (~0.15 m/px)


def _unit(v):
    n = np.linalg.norm(v)
    return v / n if n else v


def is_parallel(row):
    return row.get("angle_deg", 90) < 10


def row_frame(row, gsd):
    """Return p0 (px), u (unit along row), d (unit stall axis), n (unit normal
    toward stalls), row length in metres."""
    p0 = np.asarray(row["p0"], float)
    p1 = np.asarray(row["p1"], float)
    u = _unit(p1 - p0)
    s = row.get("side", 1)
    n = np.array([-u[1], u[0]]) * s
    if is_parallel(row):
        d = n
    else:
        a = math.radians(row.get("angle_deg", 90))
        c, sn = math.cos(s * a), math.sin(s * a)
        d = np.array([u[0] * c - u[1] * sn, u[0] * sn + u[1] * c])
    return p0, u, d, n, float(np.linalg.norm(p1 - p0) * gsd)


def band_depth_m(row):
    return row.get("width_m", 3.7) if is_parallel(row) else row["depth_m"]


def default_pitch(row):
    if is_parallel(row):
        return DEFAULT_PARALLEL_PITCH_M
    return DEFAULT_PERP_PITCH_M / math.sin(math.radians(row.get("angle_deg", 90)))


def truck_footprint_along_row(row):
    if is_parallel(row):
        return TRUCK_LEN_PARALLEL_M
    return TRUCK_WIDTH_M / math.sin(math.radians(row.get("angle_deg", 90)))


def _sample_band(img, row, gsd, t0, t1, nt, step_px=0.5):
    """Sample img on a grid: along the row (step_px) x across the band (nt
    samples between t0..t1 of band depth). Returns array [n_s, nt, C]."""
    p0, u, d, n, L = row_frame(row, gsd)
    depth_px = band_depth_m(row) / gsd
    s = np.arange(0, L / gsd, step_px)
    ts = np.linspace(t0, t1, nt) * depth_px
    xs = p0[0] + np.outer(s, np.full_like(ts, u[0])) + np.outer(np.ones_like(s), d[0] * ts)
    ys = p0[1] + np.outer(s, np.full_like(ts, u[1])) + np.outer(np.ones_like(s), d[1] * ts)
    out = cv2.remap(img.astype(np.float32), xs.astype(np.float32), ys.astype(np.float32),
                    cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
    return out if out.ndim == 3 else out[..., None]


def measure_pitch(gray, row, gsd, step_px=0.5):
    """Estimate along-row stall pitch (m). Returns (pitch or None, peak strength)."""
    prof = _sample_band(gray, row, gsd, 0.05, 0.35, 7, step_px)[..., 0].mean(axis=1)
    m_per = step_px * gsd
    ang = max(row.get("angle_deg", 90), 10)
    lo = 3.3 / math.sin(math.radians(ang))
    hi = 5.8 / math.sin(math.radians(ang))
    if len(prof) < 3 * hi / m_per:
        return None, 0.0
    win = max(3, int(2 * hi / m_per))
    x = prof - np.convolve(prof, np.ones(win) / win, mode="same")
    x = x - x.mean()
    if not x.any():
        return None, 0.0
    ac = np.correlate(x, x, mode="full")[len(x) - 1:]
    ac = ac / ac[0]
    i_lo, i_hi = int(lo / m_per), min(len(ac) - 1, int(hi / m_per))
    seg = ac[i_lo:i_hi + 1]
    k = int(np.argmax(seg))
    if k in (0, len(seg) - 1):           # no interior peak: no clear period
        return None, float(seg[k])
    return (i_lo + k) * m_per, float(seg[k])


def pitch_from_trucks(truck_s_m, row):
    """Spot width from the spacing of detected trucks parked side by side:
    median of neighbour gaps that fall in the plausible 1-spot range.
    Needs >= 2 such gaps. truck_s_m = along-row positions (m) of trucks."""
    if is_parallel(row) or len(truck_s_m) < 3:
        return None
    ang = math.radians(max(row.get("angle_deg", 90), 10))
    lo, hi = 3.3 / math.sin(ang), 5.8 / math.sin(ang)
    s = np.sort(np.asarray(truck_s_m))
    gaps = [g for g in np.diff(s) if lo <= g <= hi]
    return float(np.median(gaps)) if len(gaps) >= 2 else None


def capacity_for_row(row, gsd, gray=None, truck_s_m=()):
    """Return (capacity, pitch_m, method, strength).

    Spot width ("pitch") priority: fixed in the row definition > measured from
    the image (stripe / parked-truck periodicity) > measured from the spacing
    of detected trucks > default 4.3 m / sin(angle) (23 m for parallel)."""
    method, strength = "default", 0.0
    if row.get("pitch_m"):
        pitch, method = float(row["pitch_m"]), "fixed"
    else:
        pitch = default_pitch(row)
        # Striped rows: stripes repeat at the pitch. Unmarked angled rows: parked
        # trucks themselves repeat at the pitch actually used. Parallel rows: no
        # usable period (one truck per ~23 m), so the default is kept.
        if not is_parallel(row) and gray is not None:
            pm, strength = measure_pitch(gray, row, gsd)
            if pm and strength >= 0.15:
                pitch, method = pm, "measured (image periodicity)"
            else:
                pt = pitch_from_trucks(truck_s_m, row)
                if pt:
                    pitch, method = pt, "measured (detected-truck spacing)"
                else:
                    method = "default (no clear period)"
    L = row_frame(row, gsd)[4]
    # pull_through_trucks: a pull-through lane holds k trucks end to end
    k = int(row.get("pull_through_trucks", 1))
    return int(math.floor(L / pitch + 0.25)) * k, pitch, method, strength


def stall_polys(row, gsd, capacity, pitch):
    """Nominal stall outlines (for drawing only; counting does not use them)."""
    p0, u, d, n, L = row_frame(row, gsd)
    pp, dp = pitch / gsd, band_depth_m(row) / gsd
    return [np.array([p0 + u * pp * i, p0 + u * pp * (i + 1),
                      p0 + u * pp * (i + 1) + d * dp, p0 + u * pp * i + d * dp]) for i in range(capacity)]


def band_poly(row, gsd, extra=1.1):
    p0, u, d, n, L = row_frame(row, gsd)
    p1 = p0 + u * L / gsd
    dp = band_depth_m(row) / gsd * extra
    return np.array([p0, p1, p1 + d * dp, p0 + d * dp])


def aisle_reference(lab, row, gsd):
    """Median Lab colour of the aisle band on the non-stall side of the baseline."""
    p0, u, d, n, L = row_frame(row, gsd)
    a0, a1 = 1.5 / gsd, row.get("aisle_m", 6.0) / gsd
    p1 = p0 + u * (L / gsd)
    poly = np.array([p0 - n * a0, p1 - n * a0, p1 - n * a1, p0 - n * a1])
    mask = np.zeros(lab.shape[:2], np.uint8)
    cv2.fillPoly(mask, [poly.astype(np.int32)], 1)
    px = lab[mask.astype(bool)]
    return np.median(px, axis=0) if len(px) >= 20 else None


def occupancy_profile(lab, row, gsd, ref, step_px=0.5):
    """Boolean occupied/not along the row (one value per step_px), plus raw fractions."""
    samp = _sample_band(lab, row, gsd, 0.15, 0.85, 15, step_px)
    de = np.linalg.norm(samp - ref[None, None, :], axis=2)
    frac = (de > DE_PX).mean(axis=1)
    occ = (frac >= XSEC_OCC).astype(float)
    # majority (= binary median) filter over MEDIAN_M of row length
    k = max(1, int(round(MEDIAN_M / (step_px * gsd)))) | 1
    occ = np.convolve(np.pad(occ, k // 2, mode="edge"), np.ones(k) / k, mode="valid") >= 0.5
    return occ, frac


def runs(mask):
    out, start = [], None
    for i, v in enumerate(list(mask) + [False]):
        if v and start is None:
            start = i
        elif not v and start is not None:
            out.append((start, i))
            start = None
    return out


def count_from_profile(occ, row, gsd, pitch, step_px=0.5):
    m_per = step_px * gsd
    w = truck_footprint_along_row(row)
    ang = 90 if is_parallel(row) else row.get("angle_deg", 90)
    min_run = (4.0 if is_parallel(row) else MIN_RUN_M / math.sin(math.radians(ang)))
    trucks, kept = 0, []
    for a, b in runs(occ):
        L = (b - a) * m_per
        if L < min_run:
            continue
        k = max(1, int(round((L + pitch - w) / pitch)))
        trucks += k
        kept.append((a, b, k))
    return trucks, kept


_MODEL = None


def detect_large_vehicles(bgr, weights):
    """YOLOv8-OBB (DOTA) large-vehicle boxes in original-image px: [(poly4x2, conf)]."""
    global _MODEL
    from ultralytics import YOLO
    if _MODEL is None:
        _MODEL = YOLO(weights)
    up = cv2.resize(bgr, None, fx=UPSAMPLE, fy=UPSAMPLE, interpolation=cv2.INTER_CUBIC)
    sz = int(math.ceil(max(up.shape[:2]) / 32) * 32)
    r = _MODEL.predict(up, imgsz=sz, conf=DET_CONF, verbose=False)[0].obb
    names = _MODEL.names
    return [(p / UPSAMPLE, float(cf))
            for c, p, cf in zip(r.cls.cpu().numpy().astype(int), r.xyxyxyxy.cpu().numpy(), r.conf.cpu().numpy())
            if names[c] == "large vehicle"]


def to_lab(bgr):
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    lab[..., 0] *= 100.0 / 255.0   # OpenCV 8-bit L is scaled 0-255; CIE L is 0-100
    return lab


def row_coords(pt, row, gsd):
    """Express an image point as (s, t): s = px along the baseline at which a
    line parallel to the stall axis through pt meets the stall mouths, t = px
    along the stall axis from the mouth."""
    p0, u, d, n, L = row_frame(row, gsd)
    A = np.array([[u[0], d[0]], [u[1], d[1]]])
    s, t = np.linalg.solve(A, np.asarray(pt, float) - p0)
    return float(s), float(t)


def assign_spots(row, gsd, cap, pitch, det, taken=None):
    """Lay the row's `cap` spots along the baseline, align the grid with the
    trucks present, and give each detected truck its nearest free spot.

    Returns (spots, extra): spots = [{"i", "s0", "s1", "det"}] where det is the
    index into `det` of the truck occupying the spot (None = empty); extra =
    indices of trucks in the row band that could not be given a spot (more
    trucks than spots -> parked outside marked positions / doubled up)."""
    L = row_frame(row, gsd)[4] / gsd
    pp = pitch / gsd
    depth = band_depth_m(row) / gsd
    k_deep = int(row.get("pull_through_trucks", 1))
    lanes = cap // k_deep
    inside = []
    taken = set() if taken is None else taken
    for k, (p, cf) in enumerate(det):
        if k in taken:                    # already given a spot in another row
            continue
        s, t = row_coords(np.asarray(p).mean(axis=0), row, gsd)
        if -0.5 * pp <= s <= L + 0.5 * pp and -0.1 * depth <= t <= 1.15 * depth:
            inside.append((k, s, cf, t))
    slack = L - lanes * pp
    lo, hi = min(0.0, slack), max(0.0, slack)
    # grid offset: the one that puts trucks closest to spot centres
    if inside and lanes:
        cands = np.linspace(lo, hi, 41) if hi > lo else np.array([lo])
        def cost(phi):
            return sum(min(abs(((s - phi) % pp) - pp / 2), pp / 2) for _, s, _, _ in inside)
        phi = float(min(cands, key=cost))
    else:
        phi = slack / 2
    # one spot per lane position, k_deep spots stacked per lane for pull-through lanes
    spots = [{"i": j * k_deep + q, "lane": j, "deep": q, "k": k_deep,
              "s0": phi + j * pp, "s1": phi + (j + 1) * pp, "det": None}
             for j in range(lanes) for q in range(k_deep)]
    extra = []
    dk = depth / k_deep
    for k, s, cf, t in sorted(inside, key=lambda x: -x[2]):       # most confident first
        free = [sp for sp in spots if sp["det"] is None]
        if not free:
            extra.append(k)
            continue
        best = min(free, key=lambda sp: (((sp["s0"] + sp["s1"]) / 2 - s) / pp) ** 2
                   + (((sp["deep"] + 0.5) * dk - t) / dk) ** 2 * (k_deep > 1))
        if abs((best["s0"] + best["s1"]) / 2 - s) <= 1.0 * pp:
            best["det"] = k
            taken.add(k)
        else:
            extra.append(k)
    return spots, extra


def spot_poly(row, gsd, sp):
    p0, u, d, n, L = row_frame(row, gsd)
    k = sp.get("k", 1)
    dp = band_depth_m(row) / gsd / k
    a, b = p0 + u * sp["s0"] + d * dp * sp.get("deep", 0), p0 + u * sp["s1"] + d * dp * sp.get("deep", 0)
    return np.array([a, b, b + d * dp, a + d * dp])


def analyze(bgr, rows, gsd, det):
    """Capacity, per-spot occupied/empty, and diagnostics for every row of one lot."""
    lab = to_lab(bgr)
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    results = []
    taken = set()          # each truck can occupy at most one spot across all rows
    for row in rows:
        L = row_frame(row, gsd)[4]
        depth_m = band_depth_m(row)
        truck_s = []
        for p, cf in det:
            s, t = row_coords(np.asarray(p).mean(axis=0), row, gsd)
            if 0 <= s * gsd <= L and -0.1 * depth_m <= t * gsd <= 1.15 * depth_m:
                truck_s.append(s * gsd)
        cap, pitch, method, strength = capacity_for_row(row, gsd, gray, truck_s)
        spots, extra = assign_spots(row, gsd, cap, pitch, det, taken)
        n_occ = sum(sp["det"] is not None for sp in spots)
        ref = aisle_reference(lab, row, gsd)
        n_app = count_from_profile(occupancy_profile(lab, row, gsd, ref)[0], row, gsd, pitch)[0] if ref is not None else 0
        results.append({
            "row": row, "capacity": cap, "pitch_m": pitch, "pitch_method": method,
            "pitch_strength": strength, "length_m": row_frame(row, gsd)[4],
            "spots": spots, "occupied_spots": n_occ, "empty_spots": cap - n_occ,
            "extra_trucks": extra, "occ_appearance_diag": n_app,
        })
    return results


def draw_overlay(bgr, results, gsd, scale=2.0):
    """Spots drawn green (empty) / red (occupied), numbered per row."""
    img = cv2.resize(bgr, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
    for res in results:
        row = res["row"]
        for sp in res["spots"]:
            pts = (spot_poly(row, gsd, sp) * scale).astype(np.int32)
            col = (40, 40, 235) if sp["det"] is not None else (40, 220, 40)
            cv2.polylines(img, [pts], True, col, 2)
            m = pts[:2].mean(axis=0).astype(int)                        # label at the spot mouth
            cv2.putText(img, str(sp["i"] + 1), (int(m[0]) - 6, int(m[1]) + 5), 0, 0.42, (0, 0, 0), 3)
            cv2.putText(img, str(sp["i"] + 1), (int(m[0]) - 6, int(m[1]) + 5), 0, 0.42, col, 1)
        p0, u, d, n, L = row_frame(row, gsd)
        lbl = "%s: %d spots, %d occupied, %d empty" % (row["id"], res["capacity"], res["occupied_spots"], res["empty_spots"])
        q = (p0 * scale - n * 30).astype(int)
        cv2.putText(img, lbl, tuple(q), 0, 0.55, (0, 0, 0), 3)
        cv2.putText(img, lbl, tuple(q), 0, 0.55, (0, 255, 255), 1)
    return img
