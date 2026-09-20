#!/usr/bin/env python3
"""Offline hand-depth evaluation. Record once with DepthRecorder.swift, iterate on estimators here without a camera.

  python3 depth_eval.py rec.jsonl [--hfov 70]           # real recording
  python3 depth_eval.py --synth [--sigma 2.0 --seeds 3] # synthetic sanity benchmark

Protocol (ground truth = tape/ruler, better than LiDAR at this range):
  distance = camera lens -> palm centre, measured along a ruler/string: 25, 40, 55, 70 cm.
  poses    = flat (palm parallel to screen) | pitch30 (fingers tilted toward/away, ~30 deg) |
             roll30 (palm turned sideways about the forearm, ~30 deg) | pr30 (both) | pr45 | spin45 (in-plane control)
  label    = d<cm>_<pose>, e.g. d40_pr30. Hold the pose; keep the palm centre on the mark.

Estimators (all use the same 5 rigid palm landmarks: wrist + 4 MCP):
  span_len   Z = f*D/span, span = wrist->middleMCP                     (single span, palm length)
  span_wid   Z = f*D/span, span = indexMCP->littleMCP                  (single span, knuckle width)
  min_pairs  min over all 10 landmark pairs of f*D/span                (cheap: foreshortening only inflates Z)
  pnp        rigid palm pose, Levenberg-Marquardt on reprojection error, warm-started per frame
  live       (recordings only) the Z your running app reported, as-is
Tables show mean |error| % vs truth, before and after ONE-POINT scale calibration (a per-user scalar fitted on d40_flat).
"""
import argparse, json, math, re, sys
import numpy as np

NAMES = ["wrist", "indexMCP", "middleMCP", "ringMCP", "littleMCP"]
# Nominal palm model, mm. Palm frame: x index->little, y wrist->fingers, z out of the palm.
MODEL = np.array([[0, 0, 0], [-32, 92, 0], [-8, 98, 0], [14, 94, 0], [32, 84, 0]], float)
MODEL_C = MODEL - MODEL.mean(0)                       # origin at centroid => t_z is centroid depth
R0 = np.diag([1.0, -1.0, -1.0])                       # palm faces camera, fingers up (image v points down)
PAIRS = [(i, j) for i in range(5) for j in range(i + 1, 5)]
D_PAIR = {p: np.linalg.norm(MODEL[p[0]] - MODEL[p[1]]) for p in PAIRS}
ESTIMATORS = ["span_len", "span_wid", "min_pairs", "pnp"]


def rot(axis, deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return {"x": np.array([[1, 0, 0], [0, c, -s], [0, s, c]]),
            "y": np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]),
            "z": np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])}[axis]


def exp_so3(w):
    th = np.linalg.norm(w)
    if th < 1e-12:
        return np.eye(3)
    k = w / th
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + math.sin(th) * K + (1 - math.cos(th)) * (K @ K)


def project(R, t, X, f, cx, cy):
    Xc = X @ R.T + t
    return f * Xc[:, :2] / Xc[:, 2:3] + np.array([cx, cy])


# ------------------------------------------------------------------ estimators
def z_span(uv, i, j, f):
    return f * D_PAIR[(min(i, j), max(i, j))] / np.linalg.norm(uv[i] - uv[j])


def z_min_pairs(uv, f):
    return min(z_span(uv, i, j, f) for i, j in PAIRS)


def solve_pnp(uv, f, cx, cy, R, t, iters=15):
    """Left-perturbation Levenberg-Marquardt on (R, t). Returns R, t, rms reprojection error (px)."""
    def resid(R_, t_):
        Xc = MODEL_C @ R_.T + t_
        if np.any(Xc[:, 2] < 50):
            return None
        return (f * Xc[:, :2] / Xc[:, 2:3] + np.array([cx, cy]) - uv).ravel()

    r0 = resid(R, t)
    if r0 is None:
        return R, t, float("inf")
    c0, lam = r0 @ r0, 1e-2
    for _ in range(iters):
        J = np.empty((r0.size, 6))
        for k in range(6):
            d = np.zeros(6); d[k] = 1e-6 if k < 3 else 1e-3
            rk = resid(exp_so3(d[:3]) @ R, t + d[3:])
            if rk is None:
                return R, t, float("inf")
            J[:, k] = (rk - r0) / d[k]
        A, g = J.T @ J, J.T @ r0
        ok = False
        for _ in range(8):
            step = np.linalg.solve(A + lam * (np.diag(np.diag(A)) + 1e-9 * np.eye(6)), -g)
            Rn, tn = exp_so3(step[:3]) @ R, t + step[3:]
            rn = resid(Rn, tn)
            if rn is not None and rn @ rn < c0:
                R, t, r0, c0, lam, ok = Rn, tn, rn, rn @ rn, max(lam / 3, 1e-9), True
                break
            lam *= 4
        if not ok or np.linalg.norm(step) < 1e-7:
            break
    return R, t, math.sqrt(c0 / len(uv))


def pnp_cold(uv, f, cx, cy):
    """Cold start: seed from palm-length span + in-plane spin, try a few tilts, keep the best fit."""
    z0 = z_span(uv, 0, 2, f)
    d = uv[2] - uv[0]
    spin = math.degrees(math.atan2(d[0], -d[1]))
    c = uv.mean(0)
    t0 = np.array([(c[0] - cx) / f * z0, (c[1] - cy) / f * z0, z0])
    best = None
    for tx, ty in [(0, 0), (25, 0), (-25, 0), (0, 25), (0, -25), (25, 25), (-25, -25), (25, -25), (-25, 25)]:
        R = rot("z", spin) @ rot("x", tx) @ rot("y", ty) @ R0
        out = solve_pnp(uv, f, cx, cy, R, t0.copy())
        if best is None or out[2] < best[2]:
            best = out
    return best


class PnPTracker:
    def __init__(self, f, cx, cy):
        self.f, self.cx, self.cy, self.R, self.t = f, cx, cy, None, None

    def z(self, uv):
        if self.R is None:
            self.R, self.t, rms = pnp_cold(uv, self.f, self.cx, self.cy)
        else:
            self.R, self.t, rms = solve_pnp(uv, self.f, self.cx, self.cy, self.R, self.t)
            if not math.isfinite(rms) or rms > 12:                      # lost the fit -> cold restart
                self.R, self.t, rms = pnp_cold(uv, self.f, self.cx, self.cy)
        return self.t[2]


def run_estimators(frames, f, cx, cy):
    out = {k: [] for k in ESTIMATORS}
    trk = PnPTracker(f, cx, cy)
    for uv in frames:
        out["span_len"].append(z_span(uv, 0, 2, f))
        out["span_wid"].append(z_span(uv, 1, 4, f))
        out["min_pairs"].append(z_min_pairs(uv, f))
        out["pnp"].append(trk.z(uv))
    return {k: np.array(v) for k, v in out.items()}


# ------------------------------------------------------------------ evaluation
def evaluate(cell_frames, f, cx, cy):
    """cell_frames: {(dist_mm, pose): (frames, per-frame truth Z)} -> {cell: {estimator: Z array, 'truth': Z array}}"""
    cells = {}
    for k, v in cell_frames.items():
        frames, truth = v[0], v[1]
        cells[k] = run_estimators(frames, f, cx, cy)
        cells[k]["truth"] = np.asarray(truth, float)
        if len(v) > 2 and all(z is not None for z in v[2]):
            cells[k]["live"] = np.asarray(v[2], float)              # what the running app reported
    return cells


def tables(cells, cal_key):
    """-> {(mode, pose): [err% per estimator]} and jitter% per estimator."""
    names = [e for e in ESTIMATORS + ["live"] if all(e in c for c in cells.values())]
    scale = {e: cells[cal_key]["truth"].mean() / cells[cal_key][e].mean() for e in names}
    poses = list(dict.fromkeys(p for _, p in cells))
    out = {}
    for mode, use_cal in (("raw", False), ("cal", True)):
        for p in poses:
            row = []
            for e in names:
                errs = [np.abs(c[e] * (scale[e] if use_cal else 1.0) - c["truth"]).mean() / c["truth"].mean() * 100
                        for (d, pp), c in cells.items() if pp == p]
                row.append(float(np.mean(errs)))
            out[(mode, p)] = row
    jit = [float(np.mean([c[e].std() / c["truth"].mean() * 100 for c in cells.values()])) for e in names]
    return out, jit, poses, names


def print_tables(out, jit, poses, names, cal_key, title):
    print(f"\n{title}")
    print(f"entries = mean |error| % vs truth, pooled over distances; one-point scale calibration on {cal_key[1]} @ {cal_key[0] / 10:.0f} cm")
    print(f"{'pose':<10}" + "".join(f"{e:>11}" for e in names))
    for mode, name in (("raw", "raw (no calibration)"), ("cal", "after 1-point scale calibration")):
        print(f"-- {name}")
        for p in poses:
            print(f"{p:<10}" + "".join(f"{v:>10.1f}%" for v in out[(mode, p)]))
    print("-- jitter: std of Z within a cell / truth (%), pooled")
    print(f"{'':<10}" + "".join(f"{v:>10.2f}%" for v in jit))


# ------------------------------------------------------------------ synthetic data
POSES = {  # name: (pitch about x, roll about y, spin about z), degrees
    "flat": (0, 0, 0), "pitch30": (30, 0, 0), "roll30": (0, 30, 0),
    "pr30": (30, 30, 0), "pr45": (45, 45, 0), "spin45": (0, 0, 45),
}


def synth(sigma, seed, w=1280, h=720, hfov=70.0, user_scale=1.06, user_shape=1.03, sys_px=1.0, n=40):
    rng = np.random.default_rng(seed)
    f = (w / 2) / math.tan(math.radians(hfov / 2))
    cx, cy = w / 2, h / 2
    hand = MODEL_C * np.array([user_scale * user_shape, user_scale / user_shape, user_scale])   # this user's real hand
    cell_frames = {}
    for dist in (250, 400, 550, 700):
        for pose, (pi, ro, sp) in POSES.items():
            bias = rng.normal(0, sys_px, (5, 2))                 # per-cell systematic landmark bias (detector)
            fr, zt = [], []
            for _ in range(n):
                jit = rng.normal(0, 2, 3)
                R = rot("z", sp + jit[2]) @ rot("x", pi + jit[0]) @ rot("y", ro + jit[1]) @ R0
                t = np.array([rng.normal(0, 30), rng.normal(0, 20), dist + rng.normal(0, 5)])
                fr.append(project(R, t, hand, f, cx, cy) + bias + rng.normal(0, sigma, (5, 2)))
                zt.append(t[2])
            cell_frames[(dist, pose)] = (fr, zt)
    return cell_frames, f, cx, cy


# ------------------------------------------------------------------ real recordings
def load_recording(path, hfov):
    hdr, rows = None, []
    for line in open(path):
        o = json.loads(line)
        if o.get("t") == "h":
            hdr = o
        elif o.get("t") == "f":
            rows.append(o)
    w, h = hdr["w"], hdr["h"]
    f = (w / 2) / math.tan(math.radians(hfov / 2))
    groups, lat, miss, total = {}, [], {}, {}
    for o in rows:
        m = re.match(r"d(\d+)_(\w+)", o["l"])
        if not m:
            continue
        key = (int(m.group(1)) * 10, m.group(2))
        total[key] = total.get(key, 0) + 1
        lat.append((o["now"] - o["pts"]) * 1000)
        j = o.get("j")
        if not j or any(n not in j or j[n][2] < 0.3 for n in NAMES):
            miss[key] = miss.get(key, 0) + 1
            continue
        uv = np.array([[j[n][0] * w, (1 - j[n][1]) * h] for n in NAMES])   # Vision: origin bottom-left -> pixels
        groups.setdefault(key, ([], [], []))
        groups[key][0].append(uv); groups[key][1].append(key[0]); groups[key][2].append(o.get("z"))
    return {k: v for k, v in groups.items() if len(v[0]) > 10}, f, w / 2, h / 2, lat, miss, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("recording", nargs="?")
    ap.add_argument("--synth", action="store_true")
    ap.add_argument("--sigma", type=float, default=2.0, help="synthetic landmark noise, px @1280 wide")
    ap.add_argument("--seeds", type=int, default=1, help="synthetic runs to average")
    ap.add_argument("--hfov", type=float, default=70.0)
    a = ap.parse_args()
    cal = (400, "flat")
    if a.synth:
        runs = []
        for s in range(a.seeds):
            cf, f, cx, cy = synth(a.sigma, s)
            runs.append(tables(evaluate(cf, f, cx, cy), cal))
        out = {k: np.mean([r[0][k] for r in runs], axis=0) for k in runs[0][0]}
        jit = np.mean([r[1] for r in runs], axis=0)
        print_tables(out, jit, runs[0][2], runs[0][3], cal,
                     f"SYNTHETIC x{a.seeds} (1280x720, hfov 70, {a.sigma}px noise + 1px systematic, user hand +6% size / +3% aspect vs nominal model)")
    elif a.recording:
        cf, f, cx, cy, lat, miss, total = load_recording(a.recording, a.hfov)
        cal = cal if cal in cf else sorted(cf)[0]
        out, jit, poses, names = tables(evaluate(cf, f, cx, cy), cal)
        print_tables(out, jit, poses, names, cal, f"REAL {a.recording} (hfov assumed {a.hfov})")
        if lat:
            print(f"\nsoftware-side latency now-pts (ms): p50 {np.percentile(lat, 50):.0f}  p95 {np.percentile(lat, 95):.0f}")
        print("dropout (frames without a usable palm) per cell:",
              {f"{k[0] // 10}cm_{k[1]}": f"{miss.get(k, 0)}/{total[k]}" for k in sorted(total)})
    else:
        ap.print_help(); sys.exit(1)


if __name__ == "__main__":
    main()
