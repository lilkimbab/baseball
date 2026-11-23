"""What an umpire wears that a player does not (the user: "the umpires are
roughly done; design them in detail, like real umpires"). Fitted to the body like the gear:

  mask ("Mask"): the plate umpire's traditional mask, worn over his cap. A frame of steel wire
    — a rim the shape of the face (widest at the cheeks, narrowing to the chin), bars across
    above the eyes, under them and at the mouth with the eyes left open between, uprights
    below — standing a few centimetres off the face on two leather pads, one across the
    forehead and one round the chin and jaw; a throat guard hanging under it; and the harness
    that holds it on: straps from its sides round the back of the head and one over the top.
  polo collar ("PoloCollar"): umpires wear a polo shirt, not a jersey: a collar that stands a
    little way up the neck and folds down over the shoulders, open in front.
  ball bags ("BallBags"): the plate umpire's two pouches of spare balls, hanging from his belt
    in front of each hip.
make_player.py imports this and passes its `material` function in (officials.material = ...).
"""
import math

import bmesh
from mathutils import Vector

import gear

material = None  # set by make_player.py

WIRE = 0.0032
RIM_WIRE = 0.0038


def _finish(*args, **kwargs):
    gear.material = material
    return gear.finish(*args, **kwargs)


def _pillow(bm, front, back, cols, rows, mat):
    """A pad: two faces (front(i, j) and back(i, j), points over a cols x rows grid) joined
    round their edges. `front` is the side away from the face."""
    outer = [[bm.verts.new(front(i / (cols - 1), j / (rows - 1))) for j in range(rows)] for i in range(cols)]
    inner = [[bm.verts.new(back(i / (cols - 1), j / (rows - 1))) for j in range(rows)] for i in range(cols)]
    faces = gear.grid_faces(bm, outer, material_of=lambda i, j: mat)
    faces += gear.grid_faces(bm, inner, material_of=lambda i, j: mat)
    for i in range(cols - 1):
        for j in (0, rows - 1):
            faces.append(bm.faces.new((outer[i][j], outer[i + 1][j], inner[i + 1][j], inner[i][j])))
    for j in range(rows - 1):
        for i in (0, cols - 1):
            faces.append(bm.faces.new((outer[i][j], outer[i][j + 1], inner[i][j + 1], inner[i][j])))
    for f in faces:
        f.material_index = mat
    middle = sum((v.co for col in outer + inner for v in col), Vector()) / (2 * cols * rows)
    gear.orient(faces, lambda c: middle)


def mask(body, marks, rig):
    head = gear.Head(body, marks)
    eye, chin, lips = marks["eye"], marks["chin"], marks["lips"]
    top, bottom = eye.z + 0.05, chin.z - 0.02
    brow, cheek, mouth = eye.z + 0.021, eye.z - 0.031, lips.z - 0.004
    wide = math.radians(48.0)
    at = gear._cage_surface(head, top + 0.01, bottom - 0.01, wide, 0.027)

    def half(z):
        """Half the mask's width (rad) at a height: widest at the cheeks, narrow at the chin."""
        if z > cheek:
            return math.radians(37.0 + 7.0 * gear.smoothstep(top, cheek, z))
        return math.radians(44.0 - 20.0 * gear.smoothstep(cheek, bottom, z))

    bm = bmesh.new()

    def across(z, radius=WIRE):
        a = half(z)
        gear.tube(bm, [at(-a + 2.0 * a * k / 28, z) for k in range(29)], radius)

    def upright(deg, z0, z1, radius=WIRE):
        gear.tube(bm, [at(math.radians(deg), z0 + (z1 - z0) * k / 12) for k in range(13)], radius)

    # The rim, the bars across (none through the eyes) and the uprights.
    for z in (top, bottom):
        across(z, RIM_WIRE)
    for sign in (-1.0, 1.0):
        gear.tube(bm, [at(sign * half(top + (bottom - top) * k / 24), top + (bottom - top) * k / 24) for k in range(25)], RIM_WIRE)
    for z in (brow, cheek, mouth, (mouth + bottom) * 0.5):
        across(z)
    upright(0.0, top, brow)
    upright(0.0, cheek, bottom)
    for deg in (-17.0, 17.0):
        upright(deg, cheek, bottom)
        upright(deg * 1.45, top, brow)
    for deg in (-30.0, 30.0):
        upright(deg, brow, mouth)

    def off(t, z, inward):
        """A point `inward` m behind the frame toward the face."""
        p = at(t, z)
        return p + (Vector((head.centre.x, head.centre.y, p.z)) - p).normalized() * inward

    # The pads the mask rests on: across the forehead, and round the chin and jaw.
    for z0, z1, a_deg, thick in ((top + 0.004, brow + 0.006, 33.0, 0.024), (mouth - 0.012, bottom + 0.002, 21.0, 0.024)):
        a = math.radians(a_deg)
        bulge = lambda u, v: math.sin(math.pi * v) ** 0.5 * (0.6 + 0.4 * math.sin(math.pi * u) ** 0.3)
        _pillow(bm,
                lambda u, v: off(-a + 2.0 * a * u, z0 + (z1 - z0) * v, 0.005),
                lambda u, v: off(-a + 2.0 * a * u, z0 + (z1 - z0) * v, 0.005 + thick * bulge(u, v)),
                13, 5, 1)
    # The throat guard: a small curved plate hanging from the bottom of the frame, narrower
    # at its foot and swung in a little toward the neck.
    low = bottom - 0.052
    cols = []
    for k in range(7):
        u = k / 6.0
        col = []
        for m in range(6):
            v = m / 5.0
            t = math.radians(-10.0 + 20.0 * u) * (1.0 - 0.45 * v)
            p = at(t, bottom) + Vector((0.0, 0.022 * v * v, (low - bottom) * v))
            col.append(bm.verts.new(p))
        cols.append(col)
    guard = gear.grid_faces(bm, cols, material_of=lambda i, j: 2)
    gear.orient(guard, lambda c: Vector((head.centre.x, head.centre.y + 0.05, c.z)))

    # The harness: a strap from each side of the mask round the back of the head, at the
    # level of the eyes and of the jaw, and one from the top over the crown (over the cap).
    def strap(z_at, from_deg, lift):
        cols = []
        for k in range(33):
            u = k / 32.0
            t = math.radians(from_deg + (360.0 - 2.0 * from_deg) * u)
            col = []
            for dz in (-0.009, 0.009):
                z = z_at(u) + dz
                d = Vector((math.sin(t), -math.cos(t), 0.0))
                origin = Vector((head.centre.x, head.centre.y, z))
                r = gear.outward_hit(head.bvh, origin, d, 0.3) or 0.09
                col.append(bm.verts.new(origin + d * (r + lift)))
            cols.append(col)
        faces = gear.grid_faces(bm, cols, material_of=lambda i, j: 2)
        gear.orient(faces, lambda c: Vector((head.centre.x, head.centre.y, c.z)))

    strap(lambda u: brow + 0.012 * math.sin(math.pi * u), 42.0, 0.017)
    strap(lambda u: mouth + 0.03 * math.sin(math.pi * u), 34.0, 0.006)
    over = []
    for k in range(17):
        # A direction in the head's middle plane: forward and up at the frame, then up, then
        # back and down behind the crown.
        phi = math.radians(-58.0 + 190.0 * k / 16.0)
        aim = Vector((0.0, -math.cos(phi + math.radians(90.0)), math.sin(phi + math.radians(90.0))))
        col = []
        for dx in (-0.009, 0.009):
            origin = head.centre + Vector((dx, 0.0, 0.0))
            r = gear.outward_hit(head.bvh, origin, aim, 0.3) or 0.1
            col.append(bm.verts.new(origin + aim * (r + 0.02)))
        over.append(col)
    faces = gear.grid_faces(bm, over, material_of=lambda i, j: 2)
    gear.orient(faces, lambda c: head.centre)
    return _finish("Mask", bm, rig, lambda co: [("head", 1.0)], ["Bars", "MaskPads", "HelmetPads"], thickness=0.0, sharp_deg=80.0)


def polo_collar(jersey, rig, radius, stand=0.017):
    """The folded collar of a polo shirt round the jersey's neck opening (`radius` m from the
    neck's axis): up the neck a little way, then down over the shoulders, open in front with
    a point either side."""
    bvh = gear.tree(jersey)
    mesh = jersey.data
    names = {g.index: g.name for g in jersey.vertex_groups}
    known = [(v.co.copy(), [(names[g.group], g.weight) for g in v.groups if g.group in names and g.weight > 0.01]) for v in mesh.vertices]
    neck = rig.data.bones["neck_01"].head_local
    axis = (rig.data.bones["head"].head_local - neck).normalized()
    centre = neck + axis * 0.012
    side = axis.cross(Vector((0.0, 1.0, 0.0))).normalized()
    fore = side.cross(axis).normalized()    # toward the back of the neck
    bm = bmesh.new()
    weights = {}
    cols = []
    steps = 48
    gap = math.radians(9.0)
    for k in range(steps + 1):
        # Round from one side of the front opening to the other (0 is straight ahead).
        t = gap + (2.0 * math.pi - 2.0 * gap) * k / steps
        out = side * math.sin(t) - fore * math.cos(t)
        # Longer toward the points in front.
        front = max(math.cos(t), 0.0) ** 2
        leaf = 0.036 + 0.02 * front
        col = []
        for r, h in ((radius - 0.004, -0.004), (radius - 0.006, stand * 0.6), (radius - 0.003, stand),
                     (radius + leaf * 0.45, stand - leaf * 0.45), (radius + leaf * 0.85, stand - leaf * 1.05)):
            p = centre + out * r + axis * h
            if r > radius:
                # The leaf lies on the shirt: on the cloth under it, a little clear of it
                # (and where the shoulders fall away under it, it falls with them).
                hit = bvh.ray_cast(p + axis * 0.1, -axis, 0.3)
                if hit[0] is not None:
                    p = hit[0] + axis * 0.004 + out * 0.001
            v = bm.verts.new(p)
            nearest = min(known, key=lambda item: (item[0] - p).length_squared)
            weights[tuple(round(c, 5) for c in v.co)] = nearest[1]
            col.append(v)
        cols.append(col)
    # The leaf evened out round the neck (each point toward the middle of its neighbours): set
    # down on the cloth point by point it stood up in spikes over the shoulders.
    for _ in range(4):
        moved = {}
        for k in range(1, len(cols) - 1):
            for row in (3, 4):
                moved[(k, row)] = cols[k][row].co * 0.5 + (cols[k - 1][row].co + cols[k + 1][row].co) * 0.25
        for (k, row), co in moved.items():
            key = tuple(round(c, 5) for c in cols[k][row].co)
            cols[k][row].co = co
            weights[tuple(round(c, 5) for c in co)] = weights.get(key, [("spine_03", 1.0)])
    faces = gear.grid_faces(bm, cols)
    gear.orient(faces, lambda c: centre + axis * (c - centre).dot(axis))
    return _finish("PoloCollar", bm, rig, lambda co: weights.get(tuple(round(c, 5) for c in co), [("spine_03", 1.0)]),
                   ["Collar"], thickness=0.002, sharp_deg=60.0)


def ball_bags(pants, rig, belt_z, belt_half):
    """Two pouches of spare balls on the belt, in front of each hip ("BallBags")."""
    bvh = gear.tree(pants)
    bm = bmesh.new()
    top = belt_z + belt_half * 0.4
    tall, wide = 0.135, 0.11
    for sign in (1.0, -1.0):
        middle = math.radians(50.0) * sign    # round from straight ahead toward the hip
        cols = []
        for i in range(9):
            u = i / 8.0
            t = middle + (u - 0.5) * wide / 0.17
            col = []
            for j in range(9):
                v = j / 8.0
                z = top - tall * v
                d = Vector((math.sin(t), -math.cos(t), 0.0))
                hit = bvh.ray_cast(Vector((0.0, 0.0, z)) + d * 0.6, -d, 0.6)
                base = hit[0] if hit[0] is not None else Vector((0.0, 0.0, z)) + d * 0.17
                # A pouch: flat against the belt at the top, fuller toward the bottom, rounded
                # at its sides and its lower corners.
                full = math.sin(math.pi * u) ** 0.45 * (0.2 + 0.8 * gear.smoothstep(0.0, 0.6, v)) * (1.0 - 0.5 * gear.smoothstep(0.8, 1.0, v))
                col.append(bm.verts.new(base + d * (0.003 + 0.032 * full)))
            cols.append(col)
        faces = gear.grid_faces(bm, cols)
        gear.orient(faces, lambda c: Vector((0.0, 0.0, c.z)))
    return _finish("BallBags", bm, rig, lambda co: [("pelvis", 1.0)], ["GearTrim"], thickness=0.003, sharp_deg=50.0)
