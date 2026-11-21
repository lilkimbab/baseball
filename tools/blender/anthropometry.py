"""Measures the generated body the way a tailor or an anthropometric survey would
(docs/12 section 4): heights, breadths and girths, in metres, so the model can be held against
published tables (US Army ANSUR II, men) and against what a ballplayer looks like.

Used by make_player.py (which prints the numbers and writes them next to the model) and by
tools/blender/try_shapes.py (which tries shape settings and prints a table).

Blender's axes here: +x the model's left, -y its front, +z up; the soles are at z = 0.
"""
import math

from mathutils import Matrix, Vector
from mathutils.geometry import convex_hull_2d


def _weights(body, name):
    group = body.vertex_groups.get(name)
    out = [0.0] * len(body.data.vertices)
    if group is None:
        return out
    for v in body.data.vertices:
        for g in v.groups:
            if g.group == group.index:
                out[v.index] = g.weight
    return out


def _girth(points):
    """Length round the convex outline of points seen from above (a tape drawn round them)."""
    flat = [Vector((p.x, p.y)) for p in points]
    if len(flat) < 3:
        return 0.0
    hull = convex_hull_2d(flat)
    return sum((flat[hull[i]] - flat[hull[(i + 1) % len(hull)]]).length for i in range(len(hull)))


def level_points(verts, low, high, half=0.012):
    """Skin points near the middle of the body between two heights."""
    return [p for p in verts if abs(p.x) < half and low < p.z < high and p.y < 0.0]


def _arms_down(rig, lean=0.09):
    """Hangs the arms at the sides (the model is built with them held out), as a survey measures
    shoulder breadth. Returns nothing; undo with _rest()."""
    for side, sign in (("l", 1.0), ("r", -1.0)):
        for name, target in (("upperarm_" + side, Vector((sign * lean, 0.0, -1.0))),):
            pb = rig.pose.bones[name]
            rest = pb.bone.matrix_local
            head = pb.bone.head_local
            direction = (pb.bone.tail_local - head).normalized()
            turn = direction.rotation_difference(target.normalized()).to_matrix().to_4x4()
            pb.matrix = Matrix.Translation(head) @ turn @ Matrix.Translation(-head) @ rest


def _rest(rig):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)


def measure(body, rig, marks, bpy):
    """Returns a dictionary of measurements (m). `marks` is make_player.body_marks()."""
    skin = _weights(body, "body")
    verts = [v.co.copy() for v in body.data.vertices if skin[v.index] > 0.5]
    edges = [(body.data.vertices[e.vertices[0]].co.copy(), body.data.vertices[e.vertices[1]].co.copy())
             for e in body.data.edges if skin[e.vertices[0]] > 0.5 and skin[e.vertices[1]] > 0.5]
    bones = rig.data.bones
    top = max(p.z for p in verts)
    out = {"stature": top}

    def section(at, normal, radius=None, where=None, among=edges):
        """Where the skin crosses a plane: the points a tape laid in that plane would touch."""
        pts = []
        for a, b in among:
            da, db = (a - at).dot(normal), (b - at).dot(normal)
            if (da > 0.0) == (db > 0.0):
                continue
            p = a.lerp(b, da / (da - db))
            if radius is not None and (p - at).length > radius:
                continue
            if where is not None and not where(p):
                continue
            pts.append(p)
        return pts

    def level(z, reach=None):
        return section(Vector((0.0, 0.0, z)), Vector((0.0, 0.0, 1.0)), where=(lambda p: abs(p.x) < reach) if reach else None)

    def tape(pts, normal):
        """Girth of a section: the points flattened into the plane and wrapped."""
        side = normal.cross(Vector((0.0, 1.0, 0.0)))
        if side.length < 1e-3:
            side = Vector((1.0, 0.0, 0.0))
        side.normalize()
        fore = normal.cross(side)
        return _girth([Vector((p.dot(side), p.dot(fore), 0.0)) for p in pts])

    # --- Head ---
    lips = marks["lips"]
    eye = marks["eye"]
    ear = marks["ear"]
    chin_zone = [p for p in verts if abs(p.x) < 0.012 and p.z < lips.z and p.y < lips.y + 0.035 and p.z > lips.z - 0.09]
    menton = min(p.z for p in chin_zone)
    out["head_height"] = top - menton
    out["heads_tall"] = top / (top - menton)
    skull = [p for p in verts if p.z > eye.z + 0.015]
    out["head_breadth"] = max(p.x for p in skull) - min(p.x for p in skull)
    out["head_length"] = max(p.y for p in skull) - min(p.y for p in skull)
    out["head_girth"] = _girth(level(eye.z + 0.035))
    cheeks = [p for p in level(eye.z - 0.035) if p.y < ear.y - 0.015 and abs(p.x) < 0.11]
    out["face_breadth"] = max(p.x for p in cheeks) - min(p.x for p in cheeks)
    jaw = [p for p in level(lips.z - 0.02) if p.y < ear.y and abs(p.x) < 0.11]
    out["jaw_breadth"] = max(p.x for p in jaw) - min(p.x for p in jaw)
    out["face_height"] = eye.z - menton  # eye line to chin
    out["eye_height"] = eye.z

    # --- Neck: round it across its own axis, at the Adam's apple (under the jaw, above the
    # slope of the shoulders) ---
    neck_low = bones["neck_01"].head_local
    neck_high = bones["head"].head_local
    axis = (neck_high - neck_low).normalized()
    girths = []
    for f in (0.2, 0.35, 0.5):
        at = neck_low.lerp(neck_high, f)
        ring = section(at, axis, 0.095)
        if len(ring) > 6:
            girths.append((tape(ring, axis), max(p.x for p in ring) - min(p.x for p in ring)))
    out["neck_girth"], out["neck_breadth"] = min(girths)
    out["menton_height"] = menton
    # The pit of the throat (suprasternale): going down the middle of the front of the neck,
    # where the surface is furthest back before the chest comes forward again.
    front = {}
    for p in level_points(verts, top * 0.78, top * 0.86):
        key = round(p.z, 2)
        if key not in front or p.y < front[key].y:
            front[key] = p
    if front:
        notch = max(front.values(), key=lambda p: p.y)
        out["throat_height"] = notch.z
        out["chin_to_throat"] = menton - notch.z

    # --- Joints (the rig is fitted to the body) ---
    shoulder_l, shoulder_r = bones["upperarm_l"].head_local, bones["upperarm_r"].head_local
    out["shoulder_joints"] = (shoulder_l - shoulder_r).length
    out["shoulder_joint_height"] = shoulder_l.z
    out["upper_arm"] = (bones["lowerarm_l"].head_local - shoulder_l).length
    out["forearm"] = (bones["hand_l"].head_local - bones["lowerarm_l"].head_local).length
    out["hip_joint_height"] = bones["thigh_l"].head_local.z
    out["hip_joints"] = (bones["thigh_l"].head_local - bones["thigh_r"].head_local).length
    out["knee_height"] = bones["calf_l"].head_local.z
    out["ankle_height"] = bones["foot_l"].head_local.z
    out["thigh"] = (bones["calf_l"].head_local - bones["thigh_l"].head_local).length
    out["shin"] = (bones["foot_l"].head_local - bones["calf_l"].head_local).length

    # --- Hand and foot ---
    wrist = bones["hand_l"].head_local
    along = (bones["hand_l"].tail_local - wrist).normalized()
    reach = [(p - wrist).dot(along) for p in verts if p.x > 0.2 and (p - wrist).length < 0.3]
    out["hand_length"] = max(reach)
    palm = section(wrist + along * 0.075, along, 0.08)
    if palm:
        across = along.cross(Vector((0.0, 0.0, 1.0))).normalized()
        out["hand_breadth"] = max(p.dot(across) for p in palm) - min(p.dot(across) for p in palm)
    foot = [p for p in verts if p.z < bones["foot_l"].head_local.z and p.x > 0.0]
    out["foot_length"] = max(p.y for p in foot) - min(p.y for p in foot)
    out["foot_breadth"] = max(p.x for p in foot) - min(p.x for p in foot)

    # --- Trunk (the arms are held out, so a tape round the trunk misses them) ---
    inside = shoulder_l.x - 0.015
    for label, frac in (("chest", 0.72), ("waist", 0.61), ("hips", 0.50)):
        ring = level(top * frac, inside if label != "hips" else 0.24)
        out[label + "_girth"] = _girth(ring)
        out[label + "_breadth"] = max(p.x for p in ring) - min(p.x for p in ring)
        out[label + "_depth"] = max(p.y for p in ring) - min(p.y for p in ring)
    # The narrowest and the widest the trunk gets between the ribs and the hips.
    out["waist_least_girth"] = min(_girth(level(top * f, inside)) for f in (0.58, 0.595, 0.61, 0.625, 0.64))
    out["seat_girth"] = max(_girth(level(top * f, 0.24)) for f in (0.49, 0.505, 0.52, 0.535))
    pelvis = [p for p in verts if abs(p.x) < 0.012 and top * 0.4 < p.z < top * 0.55]
    out["crotch_height"] = min(p.z for p in pelvis)

    # --- Limbs: girths round each one, taken across its own axis ---
    def limb_girth(bone, child, fraction, radius=0.11):
        start, end = bones[bone].head_local, bones[child].head_local
        axis = (end - start).normalized()
        at = start.lerp(end, fraction)
        return tape(section(at, axis, radius), axis)

    out["upper_arm_girth"] = max(limb_girth("upperarm_l", "lowerarm_l", f) for f in (0.4, 0.5, 0.6))
    out["forearm_girth"] = max(limb_girth("lowerarm_l", "hand_l", f, 0.08) for f in (0.15, 0.25, 0.35))
    out["wrist_girth"] = min(limb_girth("lowerarm_l", "hand_l", f, 0.06) for f in (0.88, 0.94, 1.0))
    out["thigh_girth"] = limb_girth("thigh_l", "calf_l", 0.22, 0.16)
    out["mid_thigh_girth"] = limb_girth("thigh_l", "calf_l", 0.5, 0.15)
    out["knee_girth"] = limb_girth("thigh_l", "calf_l", 1.0, 0.12)
    out["calf_girth"] = max(limb_girth("calf_l", "foot_l", f, 0.11) for f in (0.2, 0.3, 0.4))
    out["ankle_girth"] = min(limb_girth("calf_l", "foot_l", f, 0.08) for f in (0.84, 0.9, 0.95))

    # --- Weight: the skin's volume at the density of a lean man (1.06 kg/l), for the model
    # scaled to 1.83 m ---
    volume = 0.0
    for poly in body.data.polygons:
        if all(skin[i] > 0.5 for i in poly.vertices):
            pts = [body.data.vertices[i].co for i in poly.vertices]
            for i in range(1, len(pts) - 1):
                volume += pts[0].dot(pts[i].cross(pts[i + 1])) / 6.0
    out["volume"] = abs(volume)
    out["mass_at_183"] = abs(volume) * 1060.0 * (1.83 / top) ** 3

    # --- Shoulder breadth with the arms hanging (over the deltoids), and the height of the
    # shoulder's top there (acromion) ---
    _arms_down(rig)
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    posed = body.evaluated_get(depsgraph)
    mesh = posed.to_mesh()
    hung = [v.co.copy() for v in mesh.vertices if v.index < len(skin) and skin[v.index] > 0.5]
    posed.to_mesh_clear()
    _rest(rig)
    bpy.context.view_layer.update()
    if hung:
        band = [p for p in hung if shoulder_l.z - 0.14 < p.z < shoulder_l.z + 0.03]
        out["shoulder_breadth"] = max(p.x for p in band) - min(p.x for p in band)
        tops = [p for p in hung if abs(abs(p.x) - shoulder_l.x) < 0.02]
        out["acromion_height"] = max(p.z for p in tops)
        # How much neck shows: from the chin down to the level of the tops of the shoulders.
        out["chin_above_shoulders"] = menton - out["acromion_height"]
    return out


# What the numbers should be, as shares of standing height unless marked "m": those are in
# metres for the model scaled to SCALED_TO (heads do not grow with height the way limbs do, and
# the game scales the whole model to each player's height). Sources: ANSUR II (2012) men's
# means at 1.756 m; de Leva (1996) segment lengths; Drillis & Contini; and, for a ballplayer's
# build (broader shoulders, thicker neck and limbs than a soldier of the same height), the
# upper part of the ANSUR range.
SCALED_TO = 1.83
TARGETS = {
    # name: (low, high, unit)
    "head_height": (0.230, 0.245, "m"),        # menton to vertex: ANSUR 0.232 at 1.756 m
    "heads_tall": (7.5, 8.0, "x"),             # 1.83 m over 0.232-0.245 m
    "head_breadth": (0.152, 0.165, "m"),       # ANSUR 0.154; Korean men about 0.157
    "head_length": (0.193, 0.212, "m"),        # ANSUR 0.197; Korean men about 0.19
    "head_girth": (0.565, 0.600, "m"),         # ANSUR 0.574
    "face_breadth": (0.138, 0.158, "m"),       # bizygomatic: ANSUR 0.142
    "neck_girth": (0.385, 0.47, "m"),          # ANSUR 0.398; athletes thicker
    "menton_height": (0.862, 0.874, "H"),      # stature less head height: (1.756 - 0.232)/1.756
    "chin_above_shoulders": (0.040, 0.052, "H"),  # ANSUR: chin 1.524 m, acromion 1.443 m
    "chin_to_throat": (0.044, 0.058, "H"),     # ANSUR: suprasternale 1.435 m
    "shoulder_joints": (0.19, 0.23, "H"),
    "shoulder_breadth": (0.290, 0.315, "H"),   # bideltoid: ANSUR 0.510/1.756 = 0.290
    "acromion_height": (0.810, 0.826, "H"),    # ANSUR 1.443/1.756 = 0.822
    "chest_girth": (0.575, 0.625, "H"),        # ANSUR 1.059/1.756 = 0.603
    "chest_depth": (0.135, 0.155, "H"),        # ANSUR 0.254/1.756 = 0.145
    "waist_girth": (0.47, 0.52, "H"),          # ANSUR 0.941/1.756 = 0.536 (soldiers); athletes less
    "hips_breadth": (0.185, 0.205, "H"),       # ANSUR 0.345/1.756 = 0.196
    "seat_girth": (0.525, 0.590, "H"),         # buttock girth: ANSUR 1.020/1.756 = 0.581
    "crotch_height": (0.470, 0.495, "H"),      # ANSUR 0.846/1.756 = 0.482
    "upper_arm_girth": (0.180, 0.205, "H"),    # ANSUR biceps flexed 0.358/1.756 = 0.204
    "forearm_girth": (0.165, 0.180, "H"),      # ANSUR forearm flexed 0.311/1.756 = 0.177
    "wrist_girth": (0.095, 0.103, "H"),        # ANSUR 0.176/1.756 = 0.100
    "thigh_girth": (0.345, 0.375, "H"),        # ANSUR 0.625/1.756 = 0.356
    "calf_girth": (0.215, 0.235, "H"),         # ANSUR 0.392/1.756 = 0.223
    "ankle_girth": (0.122, 0.134, "H"),        # ANSUR 0.225/1.756 = 0.128
    "hand_length": (0.105, 0.112, "H"),        # ANSUR 0.193/1.756 = 0.110
    "foot_length": (0.150, 0.158, "H"),        # ANSUR 0.271/1.756 = 0.154
    "knee_height": (0.270, 0.295, "H"),
}


def report(numbers):
    """Lines comparing the measurements with TARGETS."""
    height = numbers["stature"]
    lines = []
    for name, (low, high, unit) in TARGETS.items():
        if name not in numbers:
            continue
        value = numbers[name] / height if unit == "H" else numbers[name]
        if unit == "m":
            value *= SCALED_TO / height
        mark = "ok" if low <= value <= high else ("LOW" if value < low else "HIGH")
        shown = "%.3f" % value if unit != "x" else "%.2f" % value
        absolute = " (%.1f cm)" % (numbers[name] * 100.0) if unit == "H" else ""
        lines.append("%-18s %s %s  [%s .. %s]%s  %s" % (name, shown, unit, low, high, absolute, mark))
    return lines
