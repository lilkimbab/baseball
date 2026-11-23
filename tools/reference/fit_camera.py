#!/usr/bin/env python3
"""Works out where a camera stood from a reference screenshot.

Mark a few things whose place on the field you know (feet and top of the head of the pitcher,
the batter, the umpire...) and where they appear in the picture; the script finds the camera
position, the point it looks at and its vertical field of view that put them there.

    python3 tools/reference/fit_camera.py tools/reference/pitch_view.json

The JSON file gives the picture size and a list of [field x, y, z] -> [pixel x, pixel y] pairs
in field coordinates (docs/03: +x first-base side, +y toward centre field, +z up, metres).
Pure Python; no packages needed.
"""
import json
import math
import random
import sys

W, H = 1500.0, 933.0

def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def dot(a, b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def norm(a):
    l = math.sqrt(dot(a, a)); return (a[0]/l, a[1]/l, a[2]/l)

def project(cam, target, fov_deg, p):
    f = norm(sub(target, cam)); r = norm(cross(f, (0, 0, 1))); u = cross(r, f)
    d = sub(p, cam); z = dot(d, f)
    k = (H / 2) / math.tan(math.radians(fov_deg) / 2)
    return (W / 2 + dot(d, r) / z * k, H / 2 - dot(d, u) / z * k)

def nelder_mead(f, x0, step, iters=6000):
    n = len(x0)
    pts = [list(x0)] + [[x0[j] + (step[j] if i == j else 0) for j in range(n)] for i in range(n)]
    vals = [f(p) for p in pts]
    for _ in range(iters):
        order = sorted(range(n + 1), key=lambda i: vals[i]); pts = [pts[i] for i in order]; vals = [vals[i] for i in order]
        c = [sum(pts[i][j] for i in range(n)) / n for j in range(n)]
        xr = [c[j] + (c[j] - pts[-1][j]) for j in range(n)]; fr = f(xr)
        if fr < vals[0]:
            xe = [c[j] + 2 * (c[j] - pts[-1][j]) for j in range(n)]; fe = f(xe)
            pts[-1], vals[-1] = (xe, fe) if fe < fr else (xr, fr)
        elif fr < vals[-2]:
            pts[-1], vals[-1] = xr, fr
        else:
            xc = [c[j] + 0.5 * (pts[-1][j] - c[j]) for j in range(n)]; fc = f(xc)
            if fc < vals[-1]:
                pts[-1], vals[-1] = xc, fc
            else:
                for i in range(1, n + 1):
                    pts[i] = [pts[0][j] + 0.5 * (pts[i][j] - pts[0][j]) for j in range(n)]; vals[i] = f(pts[i])
    i = min(range(n + 1), key=lambda i: vals[i]); return pts[i], vals[i]



def main(path):
    global W, H
    data = json.load(open(path))
    W, H = float(data["width"]), float(data["height"])
    obs = [(tuple(p["field"]), tuple(p["pixel"])) for p in data["points"]]
    look_z = float(data.get("look_height", 0.9))

    def cost(v):
        cx, cy, cz, tx, ty, fov = v
        if fov < 0.5 or fov > 60:
            return 1e12
        e = 0.0
        for p, m in obs:
            s = project((cx, cy, cz), (tx, ty, look_z), fov, p)
            e += (s[0] - m[0]) ** 2 + (s[1] - m[1]) ** 2
        return e

    random.seed(1)
    best = None
    for _ in range(40):
        x0 = [random.uniform(-10, 10), random.uniform(20, 160), random.uniform(1, 15), random.uniform(-1, 1), random.uniform(-2, 6), random.uniform(1.5, 30)]
        x, v = nelder_mead(cost, x0, [2, 15, 2, 0.5, 1, 2])
        if best is None or v < best[1]:
            best = (x, v)
    x, v = best
    print("camera (%.1f, %.1f, %.1f) looking at (%.2f, %.2f, %.2f), vertical fov %.2f deg, rms error %.1f px"
          % (x[0], x[1], x[2], x[3], x[4], look_z, x[5], math.sqrt(v / len(obs))))
    for p, m in obs:
        s = project((x[0], x[1], x[2]), (x[3], x[4], look_z), x[5], p)
        print("  %-28s -> (%5.0f, %5.0f)   marked (%5.0f, %5.0f)" % (p, s[0], s[1], m[0], m[1]))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1])
