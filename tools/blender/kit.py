"""The cap, the shoes, the belt buckle and the trousers' side piping, shaped from the body they are worn on and from the
things themselves (the user: "the head and body look out of proportion ...
compare with the photographs"). A dome on the skull and a hull round the foot read as a
swimming cap and clown shoes at any distance.

  cap: a fitted six-panel cap. The band sits level on the forehead, over the tops of the ears
    and lower on the back of the skull; the two front panels are stiffened and stand up from
    the bill before curving back; the crown is a centimetre taller than the skull; the bill is
    7 cm long, 18 cm wide, curved, tipped down.
  shoes: low baseball spikes. A sole plate with a midsole wall, a toe box, the upper rising
    over the instep to a tongue, a padded collar below the ankle bones with a tab at the heel,
    laces across the instep, studs under the sole.
  buckle: a plain frame buckle on the front of the belt.
make_player.py imports this and passes its `material` function in (kit.material = ...).
"""
import math

import bmesh
import bpy
from mathutils import Vector

import gear

material = None  # set by make_player.py


def _finish(*args, **kwargs):
    gear.material = material
    return gear.finish(*args, **kwargs)


# --- Cap ---

CAP_BILL = 0.072          # m, at the middle
CAP_BILL_SPREAD = 62.0    # degrees each side of straight ahead the bill is sewn on
CAP_CLOTH = 0.0035        # m, wool/polyester with its sweatband


def cap_band(marks):
    """Height of the cap's edge by direction (theta round from the front): on the forehead,
    over the ears, lower behind."""
    eye, ear = marks["eye"], marks["ear"]
    return lambda t: gear._front_blend(t, eye.z + 0.047, ear.z + 0.036, ear.z + 0.006)


def cap(body, marks, rig, name="Cap", bill=CAP_BILL):
    """Returns the cap (`name`), its button and a test for points under it. `bill` is the
    length of the bill (an umpire's behind the plate is half a player's)."""
    head = gear.Head(body, marks)
    band = cap_band(marks)
    cols, rows = 48, 20

    def structure(t, p):
        front = gear.smoothstep(math.radians(72), math.radians(34), abs(t))
        # The stiffened front stands up from the bill: most off the head a little above the
        # band, where the forehead has already started back.
        stand = (0.004 + 0.011 * gear.smoothstep(1.2, 0.8, p)) * gear.smoothstep(0.15, 0.7, p)
        # The crown is taller than the skull and rounder: clear of it by a centimetre and a
        # half over the whole top, not rising to a point.
        top = 0.011 * gear.smoothstep(1.3, 0.75, p)
        # Six panels: a seam straight ahead and every 60 degrees.
        from_seam = abs((t / (math.pi / 3.0) + 0.5) % 1.0 - 0.5) * (math.pi / 3.0)
        seam = -0.0007 * math.sin(p) if from_seam * 0.09 < 0.0035 else 0.0
        return front * stand + top + seam

    pts, thetas, _ = head.shell(band, lambda t, p: CAP_CLOTH, cols=cols, rows=rows, smoothing=8, extra=structure)
    bm = bmesh.new()
    gear.orient(gear.shell_faces(bm, pts), lambda c: head.centre)

    # The bill: sewn to the band across the front, a crescent in plan, tipped down toward its
    # edge and lower at its corners than in the middle (they follow the band down).
    steps, across = 20, 4
    grid = []
    for k in range(steps + 1):
        a = math.radians(-CAP_BILL_SPREAD + 2.0 * CAP_BILL_SPREAD * k / steps)
        i = min(range(cols), key=lambda n: abs(thetas[n] - a))
        j = (i + 1) % cols if thetas[i] < a else (i - 1) % cols
        span = abs(thetas[j] - thetas[i]) or 1.0
        f = min(abs(a - thetas[i]) / span, 1.0)
        base = pts[i][-1].lerp(pts[j][-1], f)
        out = Vector((math.sin(a), -math.cos(a), 0.0))
        reach = bill * max(math.cos(a / math.radians(CAP_BILL_SPREAD) * math.pi * 0.5), 0.0) ** 0.55
        # (From a little way up the inside of the crown: no slit of light where they meet.)
        column = [bm.verts.new(pts[i][-3].lerp(pts[j][-3], f) - out * 0.003)]
        for m in range(across + 1):
            u = m / across
            # It starts a little inside the crown (no slit of light where they meet).
            p = base + out * (-0.006 + (reach + 0.006) * u)
            p.z = base.z + 0.003 - 0.21 * reach * u - 0.004 * u * u
            column.append(bm.verts.new(p))
        grid.append(column)
    bill = gear.grid_faces(bm, grid)
    gear.orient(bill, lambda c: c + Vector((0.0, 0.0, -1.0)))
    # The button sits where the panels meet, over the middle of the head.
    top_z = sum(col[0].z for col in pts) / len(pts) + 0.002
    cap_obj = _finish(name, bm, rig, lambda co: [("head", 1.0)], ["Cap"], thickness=CAP_CLOTH, sharp_deg=50.0)

    # The button where the panels meet.
    bm = bmesh.new()
    rings = []
    for r in range(4):
        phi = math.pi * 0.5 * r / 3.0
        rings.append([bm.verts.new(Vector((head.centre.x + 0.0075 * math.sin(phi) * math.cos(2 * math.pi * s / 10),
                                           head.centre.y + 0.0075 * math.sin(phi) * math.sin(2 * math.pi * s / 10),
                                           top_z - 0.001 + 0.004 * math.cos(phi))))
                      for s in range(10)] if r > 0 else None)
    tip = bm.verts.new(Vector((head.centre.x, head.centre.y, top_z + 0.0032)))
    for s in range(10):
        bm.faces.new((tip, rings[1][s], rings[1][(s + 1) % 10]))
    for r in (1, 2):
        for s in range(10):
            bm.faces.new((rings[r][s], rings[r + 1][s], rings[r + 1][(s + 1) % 10], rings[r][(s + 1) % 10]))
    gear.orient(list(bm.faces), lambda c: Vector((head.centre.x, head.centre.y, top_z - 0.01)))
    button = _finish(name + "Button", bm, rig, lambda co: [("head", 1.0)], ["Cap"])

    def under_cap(co):
        """Is this point (of the hair) inside the cap?"""
        rel = co - head.centre
        return co.z > band(math.atan2(rel.x, -rel.y)) - 0.003

    return cap_obj, button, under_cap


# --- Shoes ---

SOLE = 0.016              # m, the midsole wall's height
SOLE_LIP = 0.004          # m, how far the sole stands out from the upper
COLLAR = 0.074            # m, the collar at the sides (below the ankle bones)
HEEL_TAB = 0.088
TONGUE = 0.098
SOCK_LINE = 0.058         # below this the foot is inside the shoe (make_player keeps the sock above)
STUDS = [(0.16, -0.55), (0.16, 0.55), (0.36, -0.7), (0.36, 0.7), (0.62, -0.75), (0.62, 0.75), (0.82, -0.5), (0.82, 0.5), (0.93, 0.0)]


def shoes(feet, rig):
    """feet: {"l": [points of the left foot], "r": [...]}. Returns the "Shoes" object, with
    the materials Shoes (upper), Soles and Laces."""
    bm = bmesh.new()
    for side in ("l", "r"):
        _shoe(bm, feet[side], side)
    bm.normal_update()
    joints = {s: rig.data.bones["ball_" + s].head_local.y for s in ("l", "r")}

    def weigh(co):
        side = "l" if co.x > 0.0 else "r"
        # Forward of the ball of the foot the shoe bends with the toes (-Y is forward).
        w = gear.smoothstep(joints[side] + 0.012, joints[side] - 0.012, co.y)
        out = []
        if w > 0.01:
            out.append(("ball_" + side, w))
        if w < 0.99:
            out.append(("foot_" + side, 1.0 - w))
        return out

    return _finish("Shoes", bm, rig, weigh, ["Shoes", "Soles", "Laces"], sharp_deg=55.0)


def _shoe(bm, foot, side):
    heel = max(p.y for p in foot)
    toe = min(p.y for p in foot)
    length = heel - toe
    # The foot's outline and height, station by station from the heel (0) to the toes (1).
    stations = 26
    data = []
    for n in range(stations + 1):
        y = heel - length * n / stations
        slab = [p for p in foot if abs(p.y - y) < 0.014]
        low = [p for p in slab if p.z < 0.07] or slab or foot
        lo, hi = min(p.x for p in low), max(p.x for p in low)
        data.append([(lo + hi) * 0.5, (hi - lo) * 0.5, max(p.z for p in slab) if slab else 0.04])
    for _ in range(3):
        data = [[(data[max(i - 1, 0)][k] + 2.0 * data[i][k] + data[min(i + 1, stations)][k]) * 0.25 for k in range(3)]
                for i in range(stations + 1)]

    def profile(s):
        """Centre, half-width and top height of the upper at a station (it reaches a little
        beyond the heel and the toes, rounded in plan)."""
        f = min(max(s, 0.0), 1.0) * stations
        i = min(int(f), stations - 1)
        c, w, foot_top = [data[i][k] + (data[i + 1][k] - data[i][k]) * (f - i) for k in range(3)]
        w += 0.005
        if s < 0.12:
            w *= math.sqrt(max(1.0 - ((0.12 - s) / 0.17) ** 2, 0.02))
        if s > 0.84:
            w *= math.sqrt(max(1.0 - ((s - 0.84) / 0.22) ** 2, 0.02))
        if s < 0.47:
            # The collar round the ankle, a tab at the heel, rising to the tongue in front.
            top = COLLAR + (HEEL_TAB - COLLAR) * gear.smoothstep(0.12, 0.0, s) + (TONGUE - COLLAR) * gear.smoothstep(0.3, 0.47, s)
        else:
            # Down the instep from the tongue to the toe box, which is lower at its tip.
            box = max(foot_top + 0.007, 0.038) * (1.0 - 0.3 * gear.smoothstep(0.9, 1.05, s))
            top = TONGUE + (box - TONGUE) * gear.smoothstep(0.47, 0.62, s)
            top = max(top, min(foot_top + 0.005, TONGUE)) if s < 0.9 else top
        return c, w, top

    ring_steps = 12
    spots = [-0.045, -0.02] + [n / 30.0 for n in range(0, 31)] + [1.02, 1.045, 1.058]
    rings = []
    for s in spots:
        c, w, top = profile(s)
        y = heel - length * s
        ws = w + SOLE_LIP
        ring = [bm.verts.new(Vector((c - ws, y, 0.0))), bm.verts.new(Vector((c - ws, y, SOLE)))]
        for k in range(ring_steps + 1):
            phi = math.pi * k / ring_steps
            # A boxy arch: walls that go up before they come over.
            x = -math.copysign(abs(math.cos(phi)) ** 0.55, math.cos(phi)) * w
            z_top = top
            if s < 0.47:
                # The collar is hollowed toward the ankle (a padded rim round the opening).
                z_top = top - 0.012 * math.sin(phi) ** 2 * gear.smoothstep(0.0, 0.08, s) * gear.smoothstep(0.47, 0.36, s)
            ring.append(bm.verts.new(Vector((c + x, y, SOLE + (z_top - SOLE) * math.sin(phi) ** 0.7))))
        ring += [bm.verts.new(Vector((c + ws, y, SOLE))), bm.verts.new(Vector((c + ws, y, 0.0)))]
        rings.append(ring)
    n = len(rings[0])
    middle = Vector((sum(d[0] for d in data) / len(data), (heel + toe) * 0.5, 0.03))
    loft = []
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            f = bm.faces.new((a[k], b[k], b[(k + 1) % n], a[(k + 1) % n]))
            # The sole: its wall, the ledge it makes round the upper, and its underside.
            f.material_index = 1 if k in (0, 1, n - 3, n - 2, n - 1) else 0
            loft.append(f)
    gear.orient(loft, lambda c: Vector((middle.x, c.y, 0.03)))
    ends = []
    for ring in (rings[0], rings[-1]):
        centre = bm.verts.new(sum((v.co for v in ring), Vector()) / n)
        ends += [bm.faces.new((centre, ring[k], ring[(k + 1) % n])) for k in range(n)]
    gear.orient(ends, lambda c: middle)

    # Laces: bars across the instep, from the tongue down toward the toe box.
    for i in range(5):
        s = 0.5 + 0.042 * i
        c, w, top = profile(s)
        _box(bm, Vector((c, heel - length * s, top + 0.0008)), Vector((w * 0.4, 0.0035, 0.0022)), 2)
    # Studs under the sole (they sink into the turf when he stands; seen when the foot lifts).
    for s, across in STUDS:
        c, w, _ = profile(s)
        _stud(bm, Vector((c + across * w * 0.8, heel - length * s, 0.0)))


def _box(bm, centre, half, mat):
    verts = [bm.verts.new(centre + Vector((sx * half.x, sy * half.y, sz * half.z)))
             for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    faces = [bm.faces.new([verts[i] for i in quad])
             for quad in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))]
    for f in faces:
        f.material_index = mat
    gear.orient(faces, lambda c: centre)
    return faces


def _stud(bm, at, radius=0.006, depth=0.011):
    top, bottom = [], []
    for k in range(6):
        a = 2.0 * math.pi * k / 6
        top.append(bm.verts.new(at + Vector((radius * math.cos(a), radius * math.sin(a), 0.0))))
        bottom.append(bm.verts.new(at + Vector((radius * 0.55 * math.cos(a), radius * 0.55 * math.sin(a), -depth))))
    faces = [bm.faces.new((top[k], top[(k + 1) % 6], bottom[(k + 1) % 6], bottom[k])) for k in range(6)]
    faces.append(bm.faces.new(bottom))
    for f in faces:
        f.material_index = 1
    gear.orient(faces, lambda c: at + Vector((0.0, 0.0, -depth * 0.4)))


# --- Belt buckle ---


def buckle(pants, rig, belt_z, belt_half):
    """A frame buckle on the front of the belt ("Buckle"), weighted like the belt behind it."""
    bvh = gear.tree(pants)
    hit = bvh.ray_cast(Vector((0.0, -0.6, belt_z)), Vector((0.0, 1.0, 0.0)), 1.0)
    front = hit[0] if hit[0] is not None else Vector((0.0, -0.12, belt_z))
    bm = bmesh.new()
    half_w, half_h, bar = 0.016, belt_half + 0.001, 0.0035
    # A frame: four bars round an opening, and the prong across it.
    for cx, cz, hx, hz in ((0.0, half_h - bar, half_w, bar), (0.0, -half_h + bar, half_w, bar),
                           (-half_w + bar, 0.0, bar, half_h), (half_w - bar, 0.0, bar, half_h), (0.004, 0.0, half_w * 0.6, 0.0022)):
        # The belt curves round the body: each bar sits on the cloth where it is.
        spot = bvh.ray_cast(Vector((cx, -0.6, belt_z + cz)), Vector((0.0, 1.0, 0.0)), 1.0)[0] or front
        _box(bm, Vector((cx, min(spot.y, front.y + 0.004) - 0.0035, belt_z + cz)), Vector((hx, 0.0035, hz)), 0)
    bm.normal_update()
    spine = rig.data.bones["spine_01"].head_local.z
    return _finish("Buckle", bm, rig, lambda co: [("pelvis", 1.0)] if co.z < spine else [("spine_01", 1.0)], ["Buckle"], sharp_deg=30.0)


# --- Piping down the trousers ---

PIPING = 0.011   # m wide


def side_piping(pants, rig, top_z, bottom_z):
    """The piping down the outside of each trouser leg ("PantsStripe"), from under the belt to
    the hem: a narrow band lying on the cloth where the side seam runs. (Painted into the
    trousers' front and back views it landed wherever the cloth happened to stand furthest
    out: on these legs, a wedge at the hem.)"""
    bvh = gear.tree(pants)
    mesh = pants.data
    names = {g.index: g.name for g in pants.vertex_groups}
    kd = [(v.co.copy(), [(names[g.group], g.weight) for g in v.groups if g.group in names and g.weight > 0.01]) for v in mesh.vertices]
    bm = bmesh.new()
    weights = {}
    steps = 60
    faces = []
    for side, sign in (("l", 1.0), ("r", -1.0)):
        hip = rig.data.bones["thigh_" + side].head_local
        knee = rig.data.bones["calf_" + side].head_local
        ankle = rig.data.bones["foot_" + side].head_local
        rows = []
        for n in range(steps + 1):
            z = top_z + (bottom_z - top_z) * n / steps
            # The middle of the leg's side at this height (the seam), from the joints.
            if z >= knee.z:
                f = min(max((hip.z - z) / (hip.z - knee.z), 0.0), 1.0)
                mid_y = hip.y + (knee.y - hip.y) * f
            else:
                f = min(max((knee.z - z) / (knee.z - ankle.z), 0.0), 1.0)
                mid_y = knee.y + (ankle.y - knee.y) * f
            row = []
            for dy in (-PIPING * 0.5, 0.0, PIPING * 0.5):
                hit = bvh.ray_cast(Vector((sign * 0.6, mid_y + dy, z)), Vector((-sign, 0.0, 0.0)), 0.6)
                if hit[0] is None:
                    row = None
                    break
                v = bm.verts.new(hit[0] + hit[1] * 0.0018)
                nearest = min(kd, key=lambda item: (item[0] - hit[0]).length_squared)
                weights[tuple(round(c, 5) for c in v.co)] = nearest[1]
                row.append(v)
            rows.append(row)
        for a, b in zip(rows, rows[1:]):
            if a is None or b is None:
                continue
            for k in range(2):
                faces.append(bm.faces.new((a[k], a[k + 1], b[k + 1], b[k])))
    middle = Vector((0.0, 0.0, 0.0))
    gear.orient(faces, lambda c: Vector((0.0, c.y, c.z)))
    return _finish("PantsStripe", bm, rig, lambda co: weights.get(tuple(round(c, 5) for c in co), [("pelvis", 1.0)]), ["Piping"])
