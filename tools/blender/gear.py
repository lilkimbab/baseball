"""Headgear and catcher's gear fitted to the player's own head, chest and legs (docs/13 S11-5,
S11-8; the user: "the uniform, the catcher's gear and the helmets still look unnatural").

Every piece is a shell with thickness and finished edges, shaped from the body it is worn on:
rays from inside the head, the trunk or the leg find the surface underneath, the piece stands
off it by its padding and is smoothed into one stiff form (no dents where an ear or a fold of
the jersey is). Shapes and sizes after the equipment itself:
  batting helmet: shell down to the brow, the tops of the ears and the base of the skull; a
    short visor; a low ridge over the crown; padding visible at the edges; ear flaps (separate, the
    game shows one or both) reaching down over the ear to the jaw, with a hole at the ear;
  catcher's helmet (hockey style): shell down over the ears to the jaw and the back of the
    neck, a wire cage across the face with a wide opening for the eyes, a throat guard;
  umpire's mask: a wire frame with padded brow, chin and side pads, worn over the cap;
  chest protector: from the collarbones to the belt and round the ribs, quilted in padded
    cells, bound at the edges;
  shin guards: a knee cap, three plates down the shin with wings over the ankle, and a flap
    over the instep.
make_player.py imports this and passes its `material` function in (gear.material = ...).
"""
import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

material = None  # set by make_player.py


# --- Helpers ---


def tree(obj):
    return BVHTree.FromObject(obj, bpy.context.evaluated_depsgraph_get())


def inside_hit(bvh, origin, direction, reach=0.4):
    """Distance from `origin` (inside a garment) to the garment along `direction`: the first
    surface met going out, so nothing beyond it (an arm, the other leg) is found. Or None."""
    hit = bvh.ray_cast(origin, direction, reach)
    return hit[3] if hit[0] is not None else None


def outward_hit(bvh, origin, direction, reach=0.5):
    """Distance from `origin` to the surface along `direction`, found from outside (the
    outermost surface: over the hair, the jersey over the skin), or None."""
    start = origin + direction * reach
    hit = bvh.ray_cast(start, -direction, reach)
    if hit[0] is None:
        return None
    return reach - hit[3]


def smooth_grid(values, wrap, iterations, keep_above=None):
    """Smooths a grid of numbers (list of columns), each pass averaging with the neighbours;
    never below keep_above (same shape) if given."""
    cols, rows = len(values), len(values[0])
    for _ in range(iterations):
        out = [col[:] for col in values]
        for i in range(cols):
            for j in range(rows):
                total, n = values[i][j] * 2.0, 2.0
                for di, dj in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    ii, jj = i + di, j + dj
                    if wrap:
                        ii %= cols
                    if 0 <= ii < cols and 0 <= jj < rows:
                        total += values[ii][jj]
                        n += 1.0
                out[i][j] = total / n
                if keep_above is not None:
                    out[i][j] = max(out[i][j], keep_above[i][j])
        values = out
    return values


def grid_faces(bm, verts, wrap=False, material_of=None):
    """Quads between columns of vertices (verts[i][j], None where there is none). Returns them."""
    cols = len(verts)
    faces = []
    for i in range(cols if wrap else cols - 1):
        a, b = verts[i], verts[(i + 1) % cols]
        for j in range(min(len(a), len(b)) - 1):
            quad = (a[j], b[j], b[j + 1], a[j + 1])
            if any(v is None for v in quad) or len(set(quad)) < 4:
                continue
            face = bm.faces.new(quad)
            if material_of is not None:
                face.material_index = material_of(i, j)
            faces.append(face)
    return faces


def orient(faces, inside):
    """Turns each face to face away from inside(its centre) (the thickness then goes in)."""
    for f in faces:
        f.normal_update()
        c = f.calc_center_median()
        if f.normal.dot(c - inside(c)) < 0.0:
            f.normal_flip()


def finish(name, bm, rig, weigh, mats, thickness=0.0, rim_material=None, sharp_deg=40.0, inner_rim=True):
    """Turns a bmesh into a skinned object: given thickness (inward, against the faces'
    normals), edges sharpened, each vertex weighted by weigh(position) -> [(bone, weight)].
    The edges, and the inside too if inner_rim, take rim_material (a helmet's padded lining)."""
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for m in mats:
        mesh.materials.append(material(m))
    if rim_material is not None:
        mesh.materials.append(material(rim_material))
    for p in mesh.polygons:
        p.use_smooth = True
    if thickness > 0.0:
        mod = obj.modifiers.new("Thickness", 'SOLIDIFY')
        mod.thickness = thickness
        mod.offset = -1.0
        mod.use_even_offset = True
        mod.use_quality_normals = True
        mod.use_rim = True
        if rim_material is not None:
            mod.material_offset_rim = len(mats)
            if inner_rim:
                mod.material_offset = len(mats)
        with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    mesh.set_sharp_from_angle(angle=math.radians(sharp_deg))
    groups = {}
    for v in obj.data.vertices:
        for bone, w in weigh(v.co):
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
            groups[bone].add([v.index], w, 'REPLACE')
    obj.parent = rig
    obj.modifiers.new("Armature", 'ARMATURE').object = rig
    return obj


def tube(bm, points, radius, sides=6, mat=0):
    """A round bar along the points (closed at neither end; the ends are hidden in the frame)."""
    rings = []
    for k, p in enumerate(points):
        ahead = points[min(k + 1, len(points) - 1)] - points[max(k - 1, 0)]
        ahead.normalize()
        side = ahead.cross(Vector((0.0, 0.0, 1.0)))
        if side.length < 1e-3:
            side = ahead.cross(Vector((0.0, 1.0, 0.0)))
        side.normalize()
        up = side.cross(ahead)
        rings.append([bm.verts.new(p + (side * math.cos(2 * math.pi * s / sides) + up * math.sin(2 * math.pi * s / sides)) * radius)
                      for s in range(sides)])
    for a, b in zip(rings, rings[1:]):
        for s in range(sides):
            f = bm.faces.new((a[s], a[(s + 1) % sides], b[(s + 1) % sides], b[s]))
            f.material_index = mat


def smoothstep(lo, hi, x):
    t = min(max((x - lo) / (hi - lo), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


# --- Heads ---


POLE = 0.09


def shell_faces(bm, pts, material_of=None):
    """The faces of a shell from Head.shell's columns: the grid round and down, and a fan
    over the crown. Returns them."""
    verts = [[bm.verts.new(p) for p in col] for col in pts]
    faces = grid_faces(bm, verts, wrap=True, material_of=material_of)
    ring = [col[0] for col in verts]
    centre = sum((v.co for v in ring), Vector()) / len(ring)
    lift = max((v.co - centre).length for v in ring) * math.tan(POLE * 0.5)
    crown = bm.verts.new(centre + Vector((0.0, 0.0, lift)))
    for i in range(len(ring)):
        faces.append(bm.faces.new((crown, ring[(i + 1) % len(ring)], ring[i])))
    return faces


class Head:
    """The head's surface seen from a point inside the skull: distance to it by direction,
    and the landmarks the gear is placed by (eye, ear and chin heights, from the body)."""

    def __init__(self, body, marks):
        self.bvh = tree(body)
        self.marks = marks
        eye, ear = marks["eye"], marks["ear"]
        self.centre = Vector((0.0, ear.y + 0.004, (eye.z + ear.z) * 0.5 + 0.012))

    def direction(self, theta, phi):
        """theta round from the front (-Y) toward the left (+X); phi down from straight up."""
        return Vector((math.sin(phi) * math.sin(theta), -math.sin(phi) * math.cos(theta), math.cos(phi)))

    def radius(self, d):
        r = outward_hit(self.bvh, self.centre, d, 0.3)
        return r if r is not None else 0.09

    def shell(self, rim_z, gap, cols=96, rows=36, smoothing=25, extra=None):
        """Columns of points over the head down to rim_z(theta): the head's surface pushed out
        by gap(theta, phi) and smoothed into a stiff shell. extra(theta, phi) adds to it.
        Returns (points, thetas, phis per column)."""
        thetas = [2.0 * math.pi * i / cols - math.pi for i in range(cols)]
        ends = []
        for t in thetas:
            # The rim: march down until the surface is below the rim height.
            phi = 0.05
            while phi < 2.6:
                d = self.direction(t, phi)
                if (self.centre + d * self.radius(d)).z < rim_z(t):
                    break
                phi += 0.02
            ends.append(phi)
        ends = [sum(ends[(i + k) % cols] for k in range(-2, 3)) / 5.0 for i in range(cols)]
        # From just off the crown (a fan closes it: no faces squeezed to nothing at the pole).
        phis = [[POLE + (ends[i] - POLE) * j / (rows - 1) for j in range(rows)] for i in range(cols)]
        raw = [[self.radius(self.direction(thetas[i], phis[i][j])) for j in range(rows)] for i in range(cols)]
        rough = smooth_grid(raw, True, 6)
        # Ears and the nose may stand out of the smooth form by a centimetre at most.
        floor = [[min(raw[i][j], rough[i][j] + 0.01) + gap(thetas[i], phis[i][j]) * 0.55 for j in range(rows)] for i in range(cols)]
        r = [[rough[i][j] + gap(thetas[i], phis[i][j]) for j in range(rows)] for i in range(cols)]
        r = smooth_grid(r, True, smoothing, floor)
        pts = []
        for i in range(cols):
            col = []
            for j in range(rows):
                e = extra(thetas[i], phis[i][j]) if extra else 0.0
                col.append(self.centre + self.direction(thetas[i], phis[i][j]) * (r[i][j] + e))
            pts.append(col)
        return pts, thetas, phis


def _front_blend(theta, front, side, back):
    """A value that is `front` straight ahead, `side` over the ears and `back` behind."""
    a = abs(theta)
    if a < math.radians(90):
        return front + (side - front) * smoothstep(math.radians(25), math.radians(80), a)
    return side + (back - side) * smoothstep(math.radians(100), math.radians(160), a)


def batting_helmet(body, marks, rig):
    """The batting helmet's shell and visor (one object, "Helmet") and its ear flaps
    ("HelmetFlapLeft", "HelmetFlapRight")."""
    head = Head(body, marks)
    eye, ear = marks["eye"], marks["ear"]
    brow = eye.z + 0.042
    rim = lambda t: _front_blend(t, brow, ear.z + 0.032, ear.z - 0.035)
    gap = lambda t, p: 0.024 - 0.006 * smoothstep(0.6, 1.5, p)
    # A low ridge front to back over the crown. (Vents pressed into the shell shaded as
    # streaks down it; KBO helmets mostly have none.)

    def ridge(t, p):
        across = abs(math.sin(t)) * math.sin(p)
        return 0.004 * math.exp(-(across / 0.12) ** 2) * smoothstep(0.1, 0.4, p)

    pts, thetas, phis = head.shell(rim, gap, extra=ridge)
    bm = bmesh.new()
    orient(shell_faces(bm, pts), lambda c: head.centre)
    visor = _visor(bm, head, brow, pts, thetas)
    orient(visor, lambda c: c + Vector((0.0, 0.0, -1.0)))
    helmet = finish("Helmet", bm, rig, lambda co: [("head", 1.0)], ["Helmet", "HelmetPads"], thickness=0.006, rim_material="HelmetPads")
    flaps = [_ear_flap(head, side, rim, gap, rig) for side in ("Left", "Right")]
    return helmet, flaps


def _visor(bm, head, brow, pts, thetas, reach=0.05, spread=58.0):
    """A short visor over the eyes, from the shell's front edge, tipped down a little."""
    inner, outer = [], []
    steps = 16
    for k in range(steps + 1):
        a = math.radians(-spread + 2.0 * spread * k / steps)
        # The shell's lowest point at this angle.
        i = min(range(len(thetas)), key=lambda n: abs(thetas[n] - a))
        base = pts[i][-1]
        out = Vector((math.sin(a), -math.cos(a), 0.0))
        length = reach * math.cos(a * 0.9) ** 0.7
        inner.append(bm.verts.new(base + out * 0.004 + Vector((0.0, 0.0, 0.002))))
        outer.append(bm.verts.new(base + out * (0.004 + length) + Vector((0.0, 0.0, -0.016 * length / reach))))
    return [bm.faces.new((inner[k], outer[k], outer[k + 1], inner[k + 1])) for k in range(steps)]


def _ear_flap(head, side, rim, gap, rig):
    """The flap over one ear (+X is the player's left): the shell carried on down over the ear
    to the jaw, tucked a centimetre up under the shell's edge, its front edge sweeping back
    toward the bottom, a hole at the ear."""
    sign = 1.0 if side == "Left" else -1.0
    ear = head.marks["ear_" + side[0].lower()]
    chin = head.marks["chin"]
    cols, rows = 40, 26
    ts = [sign * math.radians(50.0 + 84.0 * i / (cols - 1)) for i in range(cols)]
    raw, zs = [], []
    for t in ts:
        top_z = rim(t) + 0.012
        bottom_z = chin.z + 0.03 + 0.035 * smoothstep(math.radians(100), math.radians(134), abs(t))
        zcol = [top_z + (bottom_z - top_z) * j / (rows - 1) for j in range(rows)]
        d = Vector((math.sin(t), -math.cos(t), 0.0))
        raw.append([outward_hit(head.bvh, Vector((head.centre.x, head.centre.y, z)), d, 0.25) or 0.075 for z in zcol])
        zs.append(zcol)
    r = smooth_grid([[v + gap(t, 1.6) + 0.004 for v in col] for col, t in zip(raw, ts)], False, 10,
                    [[v + 0.012 for v in col] for col in raw])
    bm = bmesh.new()
    verts, where = [], []
    for i, t in enumerate(ts):
        d = Vector((math.sin(t), -math.cos(t), 0.0))
        col, wcol = [], []
        for j in range(rows):
            front_limit = math.radians(50.0 + 30.0 * (j / (rows - 1)) ** 1.5)
            if abs(t) < front_limit - 1e-6:
                col.append(None)
                wcol.append(None)
                continue
            p = Vector((head.centre.x, head.centre.y, zs[i][j])) + d * r[i][j]
            # The ear hole: a round dip with soft edges.
            q = p - ear
            p -= d * 0.006 * smoothstep(0.016, 0.009, Vector((q.y, q.z)).length)
            col.append(bm.verts.new(p))
            wcol.append(p)
        verts.append(col)
        where.append(wcol)

    def mat(i, j):
        p = where[i][j]
        if p is None:
            return 0
        q = p - ear
        return 1 if Vector((q.y, q.z)).length < 0.011 else 0

    faces = grid_faces(bm, verts, material_of=mat)
    orient(faces, lambda c: head.centre)
    return finish("HelmetFlap" + side, bm, rig, lambda co: [("head", 1.0)], ["Helmet", "HelmetPads"],
                  thickness=0.006, rim_material="HelmetPads")


def _cage_surface(head, top_z, bottom_z, half_angle, stand_off):
    """A smooth curved surface in front of the face, stand_off clear of it: point(theta, z)."""
    chin = head.marks["chin"]

    def point(t, z):
        d = Vector((math.sin(t), -math.cos(t), 0.0))
        origin = Vector((head.centre.x, head.centre.y, z))
        r = outward_hit(head.bvh, origin, d, 0.3)
        r = r if r is not None else 0.1
        return origin, d, r

    # Sample, then smooth the distance so the cage is a clean curve.
    zs = [top_z + (bottom_z - top_z) * k / 10 for k in range(11)]
    ts = [-half_angle + 2.0 * half_angle * k / 12 for k in range(13)]
    radius = [[point(t, z)[2] for z in zs] for t in ts]
    # The nose and lips stand out; the cage clears the most forward point of each row.
    for j in range(len(zs)):
        front = max(radius[i][j] * math.cos(ts[i]) for i in range(len(ts)))
        for i in range(len(ts)):
            radius[i][j] = max(radius[i][j], front / max(math.cos(ts[i]), 0.3) * (0.92 + 0.08 * math.cos(ts[i])))
    radius = smooth_grid(radius, False, 6)

    def at(t, z):
        fi = (t + half_angle) / (2.0 * half_angle) * (len(ts) - 1)
        fj = (z - top_z) / (bottom_z - top_z) * (len(zs) - 1)
        i0, j0 = int(min(max(fi, 0), len(ts) - 2)), int(min(max(fj, 0), len(zs) - 2))
        u, v = min(max(fi - i0, 0.0), 1.0), min(max(fj - j0, 0.0), 1.0)
        r = (radius[i0][j0] * (1 - u) * (1 - v) + radius[i0 + 1][j0] * u * (1 - v)
             + radius[i0][j0 + 1] * (1 - u) * v + radius[i0 + 1][j0 + 1] * u * v)
        d = Vector((math.sin(t), -math.cos(t), 0.0))
        return Vector((head.centre.x, head.centre.y, z)) + d * (r + stand_off)

    return at


def catcher_helmet(body, marks, rig):
    """Hockey-style catcher's helmet ("CatcherHelmet"): shell, cage and throat guard."""
    head = Head(body, marks)
    eye, ear, chin = marks["eye"], marks["ear"], marks["chin"]
    brow = eye.z + 0.038
    jaw = chin.z + 0.012

    def rim(t):
        a = abs(t)
        if a < math.radians(38):
            return brow
        if a < math.radians(70):
            # Down the sides of the face behind the cage.
            return brow + (jaw - brow) * smoothstep(math.radians(38), math.radians(55), a)
        return jaw + (ear.z - 0.06 - jaw) * smoothstep(math.radians(110), math.radians(170), a)

    gap = lambda t, p: 0.023 - 0.005 * smoothstep(0.8, 1.6, p)
    pts, thetas, phis = head.shell(rim, gap, smoothing=30)
    bm = bmesh.new()
    # The opening for the face is where the cage goes: the shell stops at its edge.
    orient(shell_faces(bm, pts), lambda c: head.centre)
    shell = finish("CatcherHelmet", bm, rig, lambda co: [("head", 1.0)], ["Helmet", "HelmetPads"], thickness=0.007, rim_material="HelmetPads")

    # The cage: bars 3 mm thick round a curve 4.5 cm clear of the face.
    at = _cage_surface(head, brow - 0.004, chin.z - 0.03, math.radians(52), 0.045)
    bars = bmesh.new()
    eye_line = eye.z - 0.024
    rows = [brow - 0.004, eye_line, eye.z - 0.058, marks["lips"].z, chin.z - 0.03]
    for z in rows:
        tube(bars, [at(math.radians(a), z) for a in range(-52, 53, 4)], 0.0032)
    for a, top in ((0.0, brow - 0.004), (-13.0, eye_line), (13.0, eye_line), (-27.0, eye_line), (27.0, eye_line),
                   (-41.0, brow - 0.004), (41.0, brow - 0.004), (-52.0, brow - 0.004), (52.0, brow - 0.004)):
        zs = [top + (chin.z - 0.03 - top) * k / 10 for k in range(11)]
        tube(bars, [at(math.radians(a), z) for z in zs], 0.0032)
    cage = finish("CatcherCage", bars, rig, lambda co: [("head", 1.0)], ["Bars"], sharp_deg=80.0)

    # The throat guard: a curved plate hanging from the bottom of the cage.
    guard = bmesh.new()
    rowsv = []
    for k in range(5):
        z = chin.z - 0.03 - 0.016 * k
        row = []
        for a in range(-20, 21, 5):
            p = at(math.radians(a), chin.z - 0.03)
            back = 0.012 * k
            row.append(guard.verts.new(Vector((p.x * 0.8, p.y + back, z))))
        rowsv.append(row)
    faces = [guard.faces.new((rowsv[k][m], rowsv[k][m + 1], rowsv[k + 1][m + 1], rowsv[k + 1][m]))
             for k in range(4) for m in range(len(rowsv[k]) - 1)]
    orient(faces, lambda c: Vector((head.centre.x, head.centre.y, c.z)))
    throat = finish("ThroatGuard", guard, rig, lambda co: [("head", 1.0)], ["HelmetPads"], thickness=0.004)
    return [shell, cage, throat]


def umpire_mask(body, marks, rig):
    """The umpire's mask ("Mask"): a wire frame over the face, padded at brow, chin and sides,
    worn with the cap."""
    head = Head(body, marks)
    eye, chin = marks["eye"], marks["chin"]
    top, bottom = eye.z + 0.044, chin.z - 0.016
    at = _cage_surface(head, top, bottom, math.radians(50), 0.028)
    bars = bmesh.new()
    eye_line = eye.z - 0.022
    for z in (top, eye_line, eye.z - 0.055, marks["lips"].z - 0.005, bottom):
        tube(bars, [at(math.radians(a), z) for a in range(-50, 51, 4)] + [at(math.radians(50), z)], 0.0033)
    for a, from_z in ((0.0, top), (-12.0, eye_line), (12.0, eye_line), (-25.0, eye_line), (25.0, eye_line),
                      (-38.0, top), (38.0, top), (-50.0, top), (50.0, top)):
        zs = [from_z + (bottom - from_z) * k / 10 for k in range(11)]
        tube(bars, [at(math.radians(a), z) for z in zs], 0.0033)
    # Pads: strips just behind the frame at the brow and chin and down each side.
    for z0, z1, a0, a1 in ((top + 0.01, top - 0.02, -40.0, 40.0), (bottom + 0.024, bottom - 0.004, -28.0, 28.0),
                           (top - 0.01, bottom + 0.012, -50.0, -42.0), (top - 0.01, bottom + 0.012, 42.0, 50.0)):
        cols = []
        for a in [a0 + (a1 - a0) * k / 8 for k in range(9)]:
            col = []
            for z in [z0 + (z1 - z0) * k / 4 for k in range(5)]:
                p = at(math.radians(a), z)
                inward = Vector((head.centre.x, head.centre.y, p.z)) - p
                col.append(bars.verts.new(p + inward.normalized() * 0.009))
            cols.append(col)
        orient(grid_faces(bars, cols, material_of=lambda i, j: 1), lambda c: Vector((head.centre.x, head.centre.y, c.z)))
    return finish("Mask", bars, rig, lambda co: [("head", 1.0)], ["Bars", "HelmetPads"], thickness=0.0, sharp_deg=80.0)


# --- Trunk and legs ---


def chest_protector(jersey, rig, marks):
    """The catcher's chest protector ("ChestProtector")."""
    bvh = tree(jersey)
    bones = rig.data.bones
    neck = bones["neck_01"].head_local
    belt, chest_z = marks["belt"], marks["chest"]
    axis = Vector((0.0, marks["trunk_y"], 0.0))
    cols, rows = 64, 44
    angles = [math.radians(-78.0 + 156.0 * i / (cols - 1)) for i in range(cols)]
    zs = []
    for a in angles:
        lo, hi = _protector_span(abs(math.degrees(a)), marks, neck)
        zs.append([lo + (hi - lo) * j / (rows - 1) for j in range(rows)])
    raw = []
    for a, zcol in zip(angles, zs):
        d = Vector((math.sin(a), -math.cos(a), 0.0))
        raw.append([inside_hit(bvh, Vector((axis.x, axis.y, z)), d) or 0.15 for z in zcol])
    # A stiff plate: smoothed hard (the jersey's folds and the muscles under it do not show
    # through), only kept from going into the jersey.
    r = smooth_grid([[v + 0.036 for v in c] for c in raw], False, 80, [[v + 0.026 for v in c] for c in raw])
    bm = bmesh.new()
    verts = []
    for i, a in enumerate(angles):
        d = Vector((math.sin(a), -math.cos(a), 0.0))
        verts.append([bm.verts.new(Vector((axis.x, axis.y, z)) + d * (r[i][j] + _quilt(a, z, r[i][j], marks)))
                      for j, z in enumerate(zs[i])])
    orient(grid_faces(bm, verts), lambda c: Vector((axis.x, axis.y, c.z)))

    def weigh(co):
        if co.z > chest_z + 0.02:
            return [("spine_03", 1.0)]
        t = smoothstep(belt + 0.04, chest_z + 0.02, co.z)
        if t > 0.5:
            return [("spine_03", (t - 0.5) * 2.0), ("spine_02", 1.0 - (t - 0.5) * 2.0)]
        return [("spine_02", t * 2.0), ("spine_01", 1.0 - t * 2.0)]

    return finish("ChestProtector", bm, rig, weigh, ["Gear"], thickness=0.024, rim_material="GearTrim", sharp_deg=50.0, inner_rim=False)


def _protector_span(deg, marks, neck):
    """Bottom and top of the chest protector at this angle round the trunk (0 in front): a
    scoop at the neck, up over the collarbones, down round the arm holes to the ribs; to the
    belt in front, rising toward the sides."""
    belt, chest_z = marks["belt"], marks["chest"]
    top = neck.z - 0.035 + 0.05 * smoothstep(6.0, 28.0, deg)
    top += (chest_z + 0.04 - (neck.z + 0.015)) * smoothstep(40.0, 76.0, deg)
    bottom = belt - 0.045 + 0.07 * smoothstep(25.0, 60.0, deg) + 0.09 * smoothstep(55.0, 78.0, deg)
    return bottom, top


def _quilt(a, z, r, marks):
    """The padded cells: each a low pillow (up to 5 mm), stitched down along the lines between
    them. Columns: a middle one and two each side; rows of 7.5 cm (9 cm in the middle)."""
    across = a * r
    edges = [-0.25, -0.15, -0.055, 0.055, 0.15, 0.25]
    k = max(i for i in range(len(edges)) if edges[i] <= across) if across >= edges[0] else 0
    lo, hi = edges[k], edges[min(k + 1, len(edges) - 1)]
    u = min(max((across - lo) / max(hi - lo, 1e-3), 0.0), 1.0)
    pitch = 0.09 if abs(across) < 0.055 else 0.075
    v = ((z - marks["belt"]) % pitch) / pitch
    return 0.005 * math.sin(math.pi * u) ** 0.6 * math.sin(math.pi * v) ** 0.6


def shin_guards(pants, body, rig):
    """Both shin guards ("ShinGuards"): knee cap, plates, ankle wings and instep flap."""
    pants_bvh, body_bvh = tree(pants), tree(body)
    bones = rig.data.bones
    bm = bmesh.new()
    for side in ("l", "r"):
        knee = bones["calf_" + side].head_local
        ankle = bones["calf_" + side].tail_local
        axis = ankle - knee
        length = axis.length
        axis.normalize()
        front = Vector((0.0, -1.0, 0.0))
        front = (front - axis * front.dot(axis)).normalized()
        left = axis.cross(front).normalized()
        cols, rows = 36, 46
        bs = [math.radians(-100.0 + 200.0 * i / (cols - 1)) for i in range(cols)]
        ts = []
        for b in bs:
            deg = abs(math.degrees(b))
            # Rounded top over the knee; at the bottom higher in front (the ankle bends) and
            # lower at the sides (the wings over the ankle bones).
            top = -0.2 + 0.26 * smoothstep(22.0, 62.0, deg)
            bottom = 0.86 + 0.08 * smoothstep(45.0, 95.0, deg)
            ts.append([top + (bottom - top) * j / (rows - 1) for j in range(rows)])
        raw = []
        for b, tcol in zip(bs, ts):
            d = (front * math.cos(b) + left * math.sin(b)).normalized()
            col = []
            for t in tcol:
                origin = knee + axis * (t * length)
                hit = inside_hit(pants_bvh, origin, d, 0.2) if t < 0.84 else inside_hit(body_bvh, origin, d, 0.2)
                col.append(hit or 0.06)
            raw.append(col)
        r = smooth_grid([[v + 0.02 for v in c] for c in raw], False, 40, [[v + 0.013 for v in c] for c in raw])
        verts = []
        for i, b in enumerate(bs):
            d = (front * math.cos(b) + left * math.sin(b)).normalized()
            col = []
            for j, t in enumerate(ts[i]):
                origin = knee + axis * (t * length)
                # The knee cap: a dome over the kneecap; the shin plates below it.
                cap = math.exp(-(((t + 0.03) / 0.1) ** 2 + (b / math.radians(42.0)) ** 2) ** 1.5)
                bulge = 0.026 * cap
                groove = 0.005 * sum(math.exp(-((t - g) / 0.014) ** 2) for g in (0.12, 0.42, 0.7))
                col.append(bm.verts.new(origin + d * (r[i][j] + bulge - groove)))
            verts.append(col)
        orient(grid_faces(bm, verts), lambda c, k=knee, ax=axis: k + ax * (c - k).dot(ax))
        _instep_flap(bm, body_bvh, bones, side)

    def weigh(co):
        side = "l" if co.x > 0 else "r"
        foot = bones["foot_" + side].head_local
        if co.z < foot.z - 0.005:
            return [("foot_" + side, 1.0)]
        return [("calf_" + side, 1.0)]

    return finish("ShinGuards", bm, rig, weigh, ["Gear"], thickness=0.012, rim_material="GearTrim", sharp_deg=50.0, inner_rim=False)


def _instep_flap(bm, body_bvh, bones, side):
    """A plate from the front of the ankle down over the laces."""
    ankle = bones["foot_" + side].head_local
    toe = bones["ball_" + side].head_local
    cols, rows = 9, 7
    verts = []
    for i in range(cols):
        g = math.radians(-40.0 + 80.0 * i / (cols - 1))
        col = []
        for j in range(rows):
            s = 0.05 + 0.5 * j / (rows - 1)
            base = ankle.lerp(toe, s) + Vector((0.0, 0.0, -0.01))
            d = Vector((math.sin(g), -0.35, math.cos(g))).normalized()
            r = outward_hit(body_bvh, base, d, 0.2)
            col.append(bm.verts.new(base + d * ((r if r is not None else 0.04) + 0.03)))
        verts.append(col)
    centre = ankle.lerp(toe, 0.3) + Vector((0.0, 0.0, -0.03))
    orient(grid_faces(bm, verts), lambda c: centre)
