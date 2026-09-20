#!/usr/bin/env python3
"""Train a hand-depth model on FreiHAND (real 3D ground truth, no recording needed). NumPy only.

  python3 train_depth_freihand.py --data ~/FreiHAND     # folder that contains training_xyz.json (searched recursively)
  python3 train_depth_freihand.py --synthetic           # ~1 min smoke test on fake hands: checks the code, says NOTHING about accuracy

Idea, all in normalised image coordinates (x/z, y/z), so it does not depend on camera or resolution:
  r  = RMS radius of the 5 palm landmarks (wrist + 4 MCP)   -> apparent palm size, measured
  k  = log(Z * r)                                           -> what the network predicts, from the scale-free 2D shape
  Z  = exp(k) / r
Because r is measured, the log-depth error equals the error on k. The network only has to learn how much a pose is
foreshortened (rotation) and the typical hand size. The apparent size itself is NOT an input (no shortcut through
"hands are usually ~50 cm away in this dataset").

Truth = mean depth of the 5 palm landmarks. Input landmarks get noise sigma = rho * r during training (rho 0.3%..3%
of palm size), plus random roll about the optical axis (+-45 deg) and mirroring (left hands).
Compared on held-out blocks of the dataset (contiguous index blocks, so near-duplicate frames don't leak):
  span_len / span_wid   single span (wrist->middle MCP / index MCP->little MCP), size from the training set
  min_pairs             min over the 10 palm-landmark pairs
  mlp_palm              network on the 5 palm landmarks only (robust if Vision drops fingers)
  mlp_all               network on all 21 landmarks
Writes palm_depth_mlp.json (weights + constants) for a Swift port.
"""
import argparse, glob, json, math, os, sys
import numpy as np

PALM = [0, 5, 9, 13, 17]                      # wrist, index/middle/ring/little MCP (21-joint layout shared with Vision / MediaPipe)
PAIRS = [(i, j) for i in range(5) for j in range(i + 1, 5)]
EST = ["span_len", "span_wid", "min_pairs", "mlp_palm", "mlp_all"]


# ------------------------------------------------------------------ data
def load_freihand(root):
    hits = glob.glob(os.path.join(os.path.expanduser(root), "**", "training_xyz.json"), recursive=True)
    if not hits:
        sys.exit(f"training_xyz.json not found under {root}")
    xyz = np.array(json.load(open(hits[0])), dtype=np.float64)              # [N,21,3] metres, camera frame
    if xyz.ndim != 3 or xyz.shape[1:] != (21, 3):
        sys.exit(f"unexpected shape {xyz.shape}, expected [N,21,3]")
    return xyz


def synthetic(n, rng):
    """Fake articulated hands in FreiHAND joint layout (0 wrist, 1-4 thumb, 5-8 index ... 17-20 little)."""
    mcp = np.array([[-0.032, 0.092], [-0.008, 0.098], [0.014, 0.094], [0.032, 0.084]])
    seg = np.array([[0.040, 0.024, 0.020], [0.045, 0.027, 0.022], [0.042, 0.025, 0.020], [0.033, 0.019, 0.018]])
    hand = np.zeros((n, 21, 3)); hand[:, 1] = [-0.022, 0.030, 0.005]
    for f in range(4):
        a = rng.uniform(0, 1.4, n)
        p = np.tile(np.append(mcp[f], 0.0), (n, 1)); hand[:, 5 + 4 * f] = p
        for s in range(3):
            p = p + seg[f, s] * np.stack([np.zeros(n), np.cos(a), -np.sin(a)], 1)
            hand[:, 6 + 4 * f + s] = p; a = a + rng.uniform(0, 1.0, n)
    for k in range(3):
        a = rng.uniform(0.3, 1.2, n)
        hand[:, 2 + k] = hand[:, 1 + k] + 0.025 * np.stack([-np.sin(a), np.cos(a), 0.2 * np.ones(n)], 1)
    hand *= rng.normal(1.0, 0.06, (n, 1, 1))                                 # subject hand size
    ang = lambda s: np.radians(np.clip(rng.normal(0, s, n), -75, 75))
    def rot(axis, t):
        c, s_, z, o = np.cos(t), np.sin(t), np.zeros(n), np.ones(n)
        m = {"x": [[o, z, z], [z, c, -s_], [z, s_, c]], "y": [[c, z, s_], [z, o, z], [-s_, z, c]], "z": [[c, -s_, z], [s_, c, z], [z, z, o]]}[axis]
        return np.moveaxis(np.array(m), -1, 0)
    R = rot("z", np.radians(rng.uniform(-45, 45, n))) @ rot("x", ang(30)) @ rot("y", ang(30)) @ np.diag([1.0, -1.0, -1.0])
    Z = rng.uniform(0.25, 0.85, n)
    t = np.stack([Z * rng.uniform(-0.3, 0.3, n), Z * rng.uniform(-0.2, 0.2, n), Z], 1)
    return hand @ np.transpose(R, (0, 2, 1)) + t[:, None]


# ------------------------------------------------------------------ features
def prepare(xyz, rng=None, rho=None, augment=False):
    """xyz [n,21,3] -> dict(uv noisy [n,21,2], c, r, zt, feat_all, feat_palm)."""
    n = len(xyz)
    if augment:
        th = rng.uniform(-math.pi / 4, math.pi / 4, n); c, s = np.cos(th)[:, None], np.sin(th)[:, None]
        x, y = xyz[..., 0], xyz[..., 1]
        xyz = np.stack([c * x - s * y, s * x + c * y, xyz[..., 2]], -1)
        sgn = np.where(rng.random(n) < 0.5, -1.0, 1.0)                     # mirror = left hand
        xyz = xyz * np.stack([sgn, np.ones(n), np.ones(n)], 1)[:, None, :]
    uv = xyz[..., :2] / xyz[..., 2:3]
    zt = xyz[:, PALM, 2].mean(1)
    p = uv[:, PALM]; r0 = np.sqrt(((p - p.mean(1, keepdims=True)) ** 2).sum(-1).mean(1))
    if rho is not None:
        uv = uv + rng.normal(0, 1, uv.shape) * (np.asarray(rho) * r0)[:, None, None]
    p = uv[:, PALM]; c = p.mean(1)
    r = np.sqrt(((p - c[:, None]) ** 2).sum(-1).mean(1))
    q = (uv - c[:, None]) / r[:, None, None]
    return dict(uv=uv, r=r, zt=zt, all=np.concatenate([q.reshape(n, -1), c], 1),
                palm=np.concatenate([q[:, PALM].reshape(n, -1), c], 1))


# ------------------------------------------------------------------ tiny MLP (tanh, Adam)
class Net:
    def __init__(self, sizes, rng):
        self.W = [rng.normal(0, math.sqrt(1.0 / a), (a, b)) for a, b in zip(sizes[:-1], sizes[1:])]
        self.b = [np.zeros(b) for b in sizes[1:]]
        self.m = [np.zeros_like(p) for p in self.W + self.b]; self.v = [np.zeros_like(p) for p in self.W + self.b]; self.t = 0

    def forward(self, x):
        self.a = [x]
        for i, (W, b) in enumerate(zip(self.W, self.b)):
            x = x @ W + b
            if i < len(self.W) - 1:
                x = np.tanh(x)
            self.a.append(x)
        return x[:, 0]

    def step(self, dout, lr):
        g = dout[:, None]; gW, gb = [], []
        for i in reversed(range(len(self.W))):
            gW.insert(0, self.a[i].T @ g); gb.insert(0, g.sum(0))
            if i:
                g = (g @ self.W[i].T) * (1 - self.a[i] ** 2)
        self.t += 1
        for p, gi, m, v in zip(self.W + self.b, gW + gb, self.m, self.v):
            m *= 0.9; m += 0.1 * gi; v *= 0.999; v += 0.001 * gi * gi
            p -= lr * (m / (1 - 0.9 ** self.t)) / (np.sqrt(v / (1 - 0.999 ** self.t)) + 1e-8)


def train(kind, xyz_tr, xyz_va, rng, epochs, bs=512, lr=2e-3):
    d = prepare(xyz_tr, rng, np.full(len(xyz_tr), 0.01))
    k0 = np.log(d["zt"] * d["r"]); mu, sd = k0.mean(), k0.std()
    net = Net([d[kind].shape[1], 128, 128, 1] if kind == "all" else [d[kind].shape[1], 64, 64, 1], rng)
    for ep in range(epochs):
        perm = rng.permutation(len(xyz_tr)); lr_e = lr * 0.5 * (1 + math.cos(math.pi * ep / epochs))
        for i in range(0, len(perm), bs):
            b = perm[i:i + bs]
            f = prepare(xyz_tr[b], rng, np.exp(rng.uniform(math.log(0.003), math.log(0.03), len(b))), augment=True)
            k = (np.log(f["zt"] * f["r"]) - mu) / sd
            net.step((net.forward(f[kind]) - k) / len(b), lr_e)
        if ep % 10 == 9 or ep == epochs - 1:
            f = prepare(xyz_va, np.random.default_rng(1), np.full(len(xyz_va), 0.01))
            err = np.abs(np.exp(net.forward(f[kind]) * sd + mu) / f["r"] / f["zt"] - 1).mean() * 100
            print(f"  mlp_{kind:<4} epoch {ep + 1:>3}/{epochs}  val mean |err| {err:.2f}%", flush=True)
    return net, mu, sd


# ------------------------------------------------------------------ evaluation
def tilt_deg(xyz):
    p = xyz[:, PALM]
    nrm = np.cross(p[:, 1] - p[:, 0], p[:, 4] - p[:, 0]); nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    v = p.mean(1); v /= np.linalg.norm(v, axis=1, keepdims=True)
    return np.degrees(np.arccos(np.clip(np.abs((nrm * v).sum(1)), 0, 1)))


def estimates(xyz, D, nets, rho, seed):
    f = prepare(xyz, np.random.default_rng(seed), np.full(len(xyz), rho))
    p = f["uv"][:, PALM]; d = np.linalg.norm(p[:, :, None] - p[:, None], axis=-1)
    z = {"span_len": D[0, 2] / d[:, 0, 2], "span_wid": D[1, 4] / d[:, 1, 4],
         "min_pairs": np.min(np.stack([D[i, j] / d[:, i, j] for i, j in PAIRS], 1), 1)}
    for kind in ("palm", "all"):
        net, mu, sd = nets[kind]; z[f"mlp_{kind}"] = np.exp(net.forward(f[kind]) * sd + mu) / f["r"]
    return z, f["zt"]


def report(xyz_te, D, nets, rho):
    z, zt = estimates(xyz_te, D, nets, rho, seed=5)
    err = {e: np.abs(z[e] / zt - 1) * 100 for e in EST}
    tl = tilt_deg(xyz_te)
    print(f"\nTEST, landmark noise = {rho * 100:.1f}% of palm size, {len(xyz_te)} held-out samples; entries = mean |error| % (p90)")
    print(f"{'palm tilt':<10}{'n':>6}" + "".join(f"{e:>15}" for e in EST))
    for lo, hi in [(0, 20), (20, 40), (40, 60), (60, 91)]:
        m = (tl >= lo) & (tl < hi)
        if m.sum() < 20:
            continue
        print(f"{f'{lo}-{min(hi, 90)} deg':<10}{m.sum():>6}" + "".join(f"{err[e][m].mean():>8.1f} ({np.percentile(err[e][m], 90):>4.1f})" for e in EST))
    print(f"{'all':<10}{len(zt):>6}" + "".join(f"{err[e].mean():>8.1f} ({np.percentile(err[e], 90):>4.1f})" for e in EST))
    print(f"{'bias %':<10}{'':>6}" + "".join(f"{np.median(z[e] / zt - 1) * 100:>15.1f}" for e in EST) + "   (median signed error)")


def export(nets, D, path):
    out = {"palm_idx": PALM, "note": "Z = exp(net(feat) * sd + mu) / r ; feat = [(uv_i - c) / r for selected joints ..., c]; uv = (x/z, y/z)",
           "pair_lengths_m": D.tolist()}
    for kind, (net, mu, sd) in nets.items():
        out[kind] = {"mu": mu, "sd": sd, "layers": [{"W": W.tolist(), "b": b.tolist()} for W, b in zip(net.W, net.b)]}
    json.dump(out, open(path, "w"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data"); ap.add_argument("--synthetic", action="store_true")
    ap.add_argument("--epochs", type=int, default=100); ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default="palm_depth_mlp.json")
    a = ap.parse_args()
    if not a.data and not a.synthetic:
        ap.print_help(); sys.exit(1)
    rng = np.random.default_rng(a.seed)
    xyz = synthetic(20000, rng) if a.synthetic else load_freihand(a.data)
    z = xyz[:, PALM, 2].mean(1)
    print(f"{'SYNTHETIC' if a.synthetic else 'FreiHAND'}: {len(xyz)} samples, palm depth median {np.median(z):.2f} m "
          f"(5-95%: {np.percentile(z, 5):.2f}-{np.percentile(z, 95):.2f})")
    blk = np.arange(len(xyz)) // 300; order = rng.permutation(blk.max() + 1); rank = np.empty_like(order); rank[order] = np.arange(len(order))
    frac = rank[blk] / (blk.max() + 1)
    tr, va, te = xyz[frac < 0.70], xyz[(frac >= 0.70) & (frac < 0.85)], xyz[frac >= 0.85]
    print(f"blocked split: train {len(tr)} / val {len(va)} / test {len(te)}")
    pm = tr[:, PALM]; D = np.linalg.norm(pm[:, :, None] - pm[:, None], axis=-1).mean(0)
    nets = {k: train(k, tr, va, rng, a.epochs) for k in ("palm", "all")}
    for rho in (0.005, 0.02):
        report(te, D, nets, rho)
    export(nets, D, a.out); print(f"\nwrote {a.out}")


if __name__ == "__main__":
    main()
