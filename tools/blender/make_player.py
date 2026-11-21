"""Builds the base player model and exports it as glTF for the game.

Run through ./dev model, or directly:
    blender -b --python tools/blender/make_player.py -- <out.glb> [preview.png]

A human body is generated with MPFB (MakeHuman) and rigged. The uniform is cut from the body
along straight hem lines, lifted off the skin and smoothed into separate jersey and pants
meshes with front/back UVs for lettering and stripes. Shoes are convex shells around the
feet. A cap and a batting helmet are added, and bones are renamed to the names the game uses
(Godot's humanoid profile). The output of MakeHuman/MPFB is CC0.
"""
import math
import os
import sys

import bmesh
from mathutils.bvhtree import BVHTree
import bpy
from mathutils import Vector

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.locationservice import LocationService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gear  # noqa: E402  (the helmets and the catcher's gear, fitted to this body)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_GLB = ARGS[0] if ARGS else "player_base.glb"
PREVIEW = ARGS[1] if len(ARGS) > 1 and ARGS[1] != "-" else None
BUILD = ARGS[2] if len(ARGS) > 2 else "standard"

# Body shape: a professional ballplayer of about 183 cm and 88 kg (docs/12, section 4). More
# muscle and weight than an average man of that height: chest depth about 14% of height.
MACRO = {"gender": 1.0, "age": 0.5, "muscle": 0.95, "weight": 0.55, "height": 0.6, "proportions": 0.85}
# Corrections checked against anthropometric tables (docs/12, section 4). Arms: the body above
# comes out at 29.9% of height from shoulder to wrist against 31.6%, so they are lengthened.
# Head: it comes out about 8.5 head-heights tall against 7.8 for a grown man, so the head is
# enlarged by about 7%.
SHAPE = {
    "measure-upperarm-length-incr": 0.25, "measure-lowerarm-length-incr": 0.25,
    "head-scale-vert-incr": 0.4, "head-scale-horiz-incr": 0.4, "head-scale-depth-incr": 0.4,
    # A man's face (docs/13 S11-6): a wider, firmer jaw and chin, cheekbones, a brow ridge,
    # a thicker neck. Without these the default face reads as a woman's at close range.
    "chin-width-incr": 0.3, "chin-bones-incr": 0.35, "l-cheek-bones-incr": 0.25, "r-cheek-bones-incr": 0.25,
    "eyebrows-trans-forward": 0.35, "forehead-nubian-incr": 0.2, "measure-neck-circ-incr": 0.15, "head-square": 0.25,
    # An athlete's build (the reference game's players, and photographs): broad shoulders and
    # back tapering to a narrow waist and hips, a flat stomach. Without these the uniform
    # hung on a pear shape and the players looked heavy.
    # The breadth is the back's muscle (latissimus), not the "V shape" key: that one moves the
    # shoulder joints apart, past a fifth of height and the anthropometric tables the
    # proportion tests pin (0.5 of it put them 24% of height apart).
    "torso-muscle-dorsi-incr": 0.5,
    "torso-muscle-pectoral-incr": 0.3, "measure-waist-circ-decr": 0.35, "measure-hips-circ-decr": 0.4,
    "hip-scale-horiz-decr": 0.25, "stomach-pregnant-decr": 0.4, "buttocks-volume-decr": 0.2,
}
# Faces that differ from player to player: shape keys the game sets per player (morph
# targets in the model). Each name is one key; pairs give both directions.
FACE_KEYS = [
    "head-oval", "head-round", "head-square", "head-triangular",
    "chin-width-incr", "chin-width-decr", "chin-prominent-incr", "chin-prominent-decr",
    "nose-scale-horiz-incr", "nose-scale-horiz-decr", "nose-scale-vert-incr", "nose-hump-incr",
    "mouth-scale-horiz-incr", "mouth-scale-horiz-decr",
    "l-cheek-bones-incr", "r-cheek-bones-incr",
]
# (No eye keys: the eyes, brows and lashes are separate meshes fitted to the default face and
# would not follow them.)
RACE = {"asian": 1.0, "caucasian": 0.0, "african": 0.0}
# Builds (docs/13 S11-1): MPFB weight and muscle for a lean, standard, solid and heavy player
# of the same height. Weight rises with muscle first (athletes), then with mass. The trunk's
# width and depth at chest and waist are printed for the build checks.
BUILDS = {
    "lean": {"muscle": 0.85, "weight": 0.35},
    "standard": {"muscle": 0.95, "weight": 0.55},
    "solid": {"muscle": 1.0, "weight": 0.7},
    "heavy": {"muscle": 1.0, "weight": 0.88},
}

# Hair (docs/13 S11-4): MakeHuman's four short styles (CC0, from MPFB's system assets). Every
# model carries all four; the game shows one per player. Hair under the cap is cut away, so
# only the sides, back and sideburns show below it. Textures are scaled down to this size.
HAIR_STYLES = ["short01", "short02", "short03", "short04"]
HAIR_TEXTURE = 512
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# Where the garments end, as a fraction along the limb (0 = upper joint, 1 = lower joint).
SLEEVE_HEM = 0.62
PANTS_HEM = 0.9
BELT_HALF = 0.024
# Centre of the belt as a fraction of standing height. Baseball trousers are worn on the hips,
# with the top of the belt at about the top of the hip bones (59% of height), not at the
# narrowest part of the waist (62%).
BELT_CENTRE = 0.575
# How far skin continues under a hem before it is removed, so no gap shows.
TUCK = 0.05

SKIN, HANDS, JERSEY, BELT, PANTS, SOCKS, SHOES, UNDERSHIRT = range(8)
# The jersey's neckline (docs/13 S11-7): a V in front, from the sides of the neck down to
# where the button placket starts; the undershirt's round neck shows inside it.
V_DEPTH = 0.105
V_TOP_HALF = 0.062

BONE_NAMES = {
    "Root": "Root", "pelvis": "Hips", "spine_01": "Spine", "spine_02": "Chest", "spine_03": "UpperChest",
    "neck_01": "Neck", "head": "Head",
}
for side, name in (("l", "Left"), ("r", "Right")):
    BONE_NAMES.update({
        f"clavicle_{side}": f"{name}Shoulder", f"upperarm_{side}": f"{name}UpperArm",
        f"lowerarm_{side}": f"{name}LowerArm", f"hand_{side}": f"{name}Hand",
        f"thigh_{side}": f"{name}UpperLeg", f"calf_{side}": f"{name}LowerLeg",
        f"foot_{side}": f"{name}Foot", f"ball_{side}": f"{name}Toes",
        f"thumb_01_{side}": f"{name}ThumbMetacarpal", f"thumb_02_{side}": f"{name}ThumbProximal",
        f"thumb_03_{side}": f"{name}ThumbDistal",
    })
    for src, dst in (("index", "Index"), ("middle", "Middle"), ("ring", "Ring"), ("pinky", "Little")):
        for n, part in (("01", "Proximal"), ("02", "Intermediate"), ("03", "Distal")):
            BONE_NAMES[f"{src}_{n}_{side}"] = f"{name}{dst}{part}"

# Placeholder colours; the game recolours and textures everything per team.
COLOURS = {
    "Skin": (0.80, 0.60, 0.46), "Hands": (0.80, 0.60, 0.46), "Jersey": (0.92, 0.92, 0.94),
    "Pants": (0.88, 0.88, 0.90), "Belt": (0.04, 0.04, 0.05), "Socks": (0.10, 0.15, 0.35),
    "Shoes": (0.05, 0.05, 0.06), "Cap": (0.10, 0.15, 0.35), "Helmet": (0.10, 0.15, 0.35),
    "Collar": (0.10, 0.15, 0.35), "Gear": (0.08, 0.10, 0.20), "Bars": (0.10, 0.10, 0.11),
    "Undershirt": (0.10, 0.15, 0.35), "HelmetPads": (0.05, 0.05, 0.055), "GearTrim": (0.06, 0.06, 0.07),
}


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def material(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*COLOURS[name], 1.0)
        bsdf.inputs["Roughness"].default_value = {"Skin": 0.55, "Hands": 0.55, "Helmet": 0.25}.get(name, 0.8)
        mat.use_backface_culling = name in ("Skin", "Hands", "Socks", "Shoes")
    return mat


def stand_on_ground(body, rig):
    """Moves the rig (and the mesh parented to it) so the soles are at height zero, then
    bakes the move into both so mesh and bones share one coordinate system."""
    bpy.context.view_layer.update()
    body_group = body.vertex_groups["body"].index
    lowest = min((body.matrix_world @ v.co).z for v in body.data.vertices
                 if any(g.group == body_group and g.weight > 0.5 for g in v.groups))
    rig.location.z -= lowest
    bpy.context.view_layer.update()
    for obj in bpy.data.objects:
        obj.select_set(obj == rig or obj.parent == rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.update()
    print("make_player: moved up %.3f m; knee at %.3f m" % (-lowest, rig.data.bones["calf_l"].head_local.z))


SKIN_FILE = "skins/young_asian_male/young_asian_male.mhmat"
FACE_ASSETS = [("eyes/low-poly/low-poly.mhclo", "Eyes"), ("eyebrows/eyebrow001/eyebrow001.mhclo", "Eyebrows"),
               ("eyelashes/eyelashes01/eyelashes01.mhclo", "Eyelashes")]


def add_skin_and_face(body):
    """Gives the body a painted skin texture and adds eyes, eyebrows and eyelashes from the
    MakeHuman asset pack (CC0), if the pack is installed. Returns the extra objects."""
    data = LocationService.get_user_data()
    skin = os.path.join(data, SKIN_FILE)
    if not os.path.exists(skin):
        print("make_player: asset pack not installed, using a plain skin colour")
        return []
    HumanService.set_character_skin(skin, body, skin_type="GAMEENGINE", material_instances=False)
    extras = []
    for path, kind in FACE_ASSETS:
        full = os.path.join(data, path)
        if not os.path.exists(full):
            continue
        before = set(bpy.data.objects)
        HumanService.add_mhclo_asset(full, body, asset_type=kind, subdiv_levels=0, material_type="GAMEENGINE")
        for obj in set(bpy.data.objects) - before:
            obj.name = obj.data.name = kind
            extras.append(obj)
    print("make_player: skin texture and", [o.name for o in extras])
    return extras


def _group_weights(body, name):
    """Per vertex weight in a vertex group (0 when the group is missing)."""
    weights = [0.0] * len(body.data.vertices)
    group = body.vertex_groups.get(name)
    if group is None:
        return weights
    for v in body.data.vertices:
        for e in v.groups:
            if e.group == group.index:
                weights[v.index] = e.weight
    return weights


def _smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _pixels(image):
    import numpy as np
    out = np.empty(image.size[0] * image.size[1] * 4, dtype=np.float32)
    image.pixels.foreach_get(out)
    return out.reshape(image.size[1], image.size[0], 4)


def _box(a, r):
    """Box blur of a 2D array (edges clamped), radius r pixels."""
    import numpy as np
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
        n = a.shape[axis]
        a = (np.take(c, range(2 * r + 1, 2 * r + 1 + n), axis=axis) - np.take(c, range(0, n), axis=axis)) / (2 * r + 1)
    return a


def surface_hollows(body, group="body", strength=0.5):
    """Per vertex, how hollow the surface is there (1 flat or rounded, down to 0.5 in the
    deepest hollows): the dip between the muscles of the shoulders, arms, chest and neck,
    under the collarbones, round the knuckles. What makes a body look built and not smooth;
    the mesh has the shapes, this shades them. Measured as how far the neighbours stand out
    along the normal, against the length of the edges, smoothed over the neighbours twice."""
    import numpy as np
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    n = len(bm.verts)
    curv = np.zeros(n)
    neighbours = []
    for v in bm.verts:
        nb = [e.other_vert(v) for e in v.link_edges]
        neighbours.append([o.index for o in nb])
        if not nb:
            continue
        avg = sum((o.co for o in nb), Vector()) / len(nb)
        edge = sum((o.co - v.co).length for o in nb) / len(nb)
        curv[v.index] = (avg - v.co).dot(v.normal) / max(edge, 1e-5)
    bm.free()
    for _ in range(2):
        curv = np.array([(curv[i] + sum(curv[j] for j in nb)) / (1 + len(nb)) for i, nb in enumerate(neighbours)])
    inside = np.array(_group_weights(body, group)) > 0.5 if group else np.ones(n, dtype=bool)
    deep = float(np.percentile(curv[inside], 97))
    hollow = 1.0 - strength * np.clip(curv / max(deep, 1e-5), 0.0, 1.0)
    print("make_player: surface hollows, 97th percentile %.3f" % deep)
    return hollow


# Raised veins (docs/13 S14): on a ballplayer's forearms and the backs of his hands they are
# what tells skin from plastic at a few metres. Positions after the anatomy (superficial veins
# of the upper limb), in the model's arms-down pose with the thumbs forward: the angle round
# the forearm is 0 in front (the thumb side), +90 degrees outward (the back of the forearm),
# -90 inward (the flexor side, where the veins show most). Each: angle, wander, waves along
# the arm, phase, from and to (0 elbow, 1 wrist), half-width (m), height.
FOREARM_VEINS = [
    (-0.25, 0.22, 4.0, 0.3, 0.0, 1.0, 0.0034, 1.0),   # cephalic, up the thumb side
    (-1.35, 0.2, 5.0, 1.7, 0.15, 0.85, 0.0030, 0.85),  # median antebrachial, on the flexor side
    (-2.55, 0.18, 3.5, 2.9, 0.0, 0.7, 0.0032, 0.75),   # basilic, on the little-finger side
    (0.85, 0.25, 6.0, 0.9, 0.45, 1.0, 0.0026, 0.6),  # a branch over the back of the wrist
]
# The median cubital vein crosses the inside of the elbow from the cephalic to the basilic.
CUBITAL = (0.03, -0.3, 0.22, -2.4, 0.0036, 0.9)
# The back of the hand: veins from the wrist fanning out between the knuckles (across the
# hand in metres from its middle, toward the index finger positive; spread over its length).
HAND_VEINS = [(-0.012, -0.012, 0.8), (0.004, 0.006, 0.9), (0.016, 0.02, 0.7)]
FOREARM_RADIUS = 0.04
# How far the veins tilt the surface, per unit of their height per pixel.
VEIN_SLOPE = 2.2


# The lines of a grown man's face (docs/13 S14): the creases from the nose past the corners of
# the mouth, under the eyes, below the lower lip, across the forehead, between the brows and at
# the corners of the eyes. Without them MakeHuman's face is a smooth young mask. Each is a
# polyline in metres from the middle between the eyes (x to the player's left, z up, on the
# face seen from the front), with a half-width (m) and a depth (0..1); mirrored for both sides
# where `both`.
FACE_LINES = [
    # (points, half-width, depth, both sides)
    ([(0.017, "lips+0.034"), (0.025, "lips+0.016"), (0.031, "lips+0.0"), (0.035, "lips-0.016")], 0.0022, 1.0, True),
    ([(0.016, -0.017), (0.025, -0.021), (0.035, -0.021), (0.044, -0.016)], 0.0014, 0.6, True),
    ([(-0.014, "lips-0.017"), (0.0, "lips-0.02"), (0.014, "lips-0.017")], 0.0016, 0.6, False),
    ([(-0.04, 0.05), (-0.02, 0.047), (0.0, 0.046), (0.02, 0.047), (0.04, 0.05)], 0.0011, 0.35, False),
    ([(-0.036, 0.063), (-0.018, 0.06), (0.0, 0.059), (0.018, 0.06), (0.036, 0.063)], 0.0011, 0.3, False),
    ([(0.006, 0.012), (0.007, 0.03)], 0.0009, 0.3, True),
    ([(0.05, 0.003), (0.061, 0.007)], 0.0008, 0.35, True),
    ([(0.05, -0.004), (0.06, -0.01)], 0.0008, 0.35, True),
]
LINE_SLOPE = 0.55


def face_lines(head_pos, marks):
    """Depth of the face's lines (0..1) per pixel of the relief map, from the baked head
    positions (see FACE_LINES)."""
    import numpy as np
    on = head_pos[..., 0] > 0.01
    x = (head_pos[..., 0] - 0.5) * 0.3
    y = (head_pos[..., 1] - 0.5) * 0.3
    z = (head_pos[..., 2] - 0.5) * 0.3
    # Only the front of the face (the lines drawn on a front view must not land on the sides
    # of the head as well).
    front = on & (y < 0.03)
    depth = np.zeros_like(x)

    def height(spec):
        if isinstance(spec, str):
            base, off = spec[:4], float(spec[4:])
            return marks[base].z + off
        return spec

    for points, half, k, both in FACE_LINES:
        for sign in ((1.0, -1.0) if both else (1.0,)):
            pts = [(sign * px, height(pz)) for px, pz in points]
            best = np.full_like(x, 1.0)
            for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
                dx, dz = x1 - x0, z1 - z0
                t = np.clip(((x - x0) * dx + (z - z0) * dz) / (dx * dx + dz * dz), 0.0, 1.0)
                best = np.minimum(best, np.hypot(x - (x0 + t * dx), z - (z0 + t * dz)))
            # Fading out toward the ends of each line.
            depth = np.maximum(depth, k * np.exp(-(best / half) ** 2))
    return np.where(front, depth, 0.0)


def limb_coordinates(body, rig):
    """Per vertex, where on a forearm or hand it is: (along, cos, sin) and (weight, across, 0),
    packed into 0..1 for baking. `along` runs 0 at the elbow to 1 at the wrist and on to 2 at
    the knuckles (stored halved); the angle round the forearm as in FOREARM_VEINS (as cosine
    and sine, which interpolate across faces where an angle would jump); `across` is the
    distance across the back of the hand; weight is how much the vertex is forearm or the
    back of a hand (0 elsewhere)."""
    import numpy as np
    bones = rig.data.bones
    groups = {g.index: g.name for g in body.vertex_groups}
    limb = [(0.0, 0.5, 0.5)] * len(body.data.vertices)
    extra = [(0.0, 0.5, 0.0)] * len(body.data.vertices)
    for side, sign in (("l", 1.0), ("r", -1.0)):
        elbow = bones["lowerarm_" + side].head_local
        wrist = bones["lowerarm_" + side].tail_local
        knuckle = bones["middle_01_" + side].head_local
        across = bones["index_01_" + side].head_local - bones["pinky_01_" + side].head_local
        fore_axis = wrist - elbow
        hand_axis = knuckle - wrist
        back_of_hand = hand_axis.cross(across).normalized() * -sign
        across_dir = (across - hand_axis * (across.dot(hand_axis) / hand_axis.length_squared)).normalized()
        middle = (bones["index_01_" + side].head_local + bones["pinky_01_" + side].head_local) * 0.5
        print("make_player: %s hand back faces %s (outward %.2f)" % (side, tuple(round(c, 2) for c in back_of_hand), back_of_hand.x * sign))
        for v in body.data.vertices:
            fore = hand = 0.0
            for e in v.groups:
                name = groups.get(e.group, "")
                if name.startswith("lowerarm") and name.endswith("_" + side):
                    fore += e.weight
                elif name == "hand_" + side:
                    hand += e.weight
            if fore + hand < 0.3:
                continue
            if fore >= hand:
                t = min(max((v.co - elbow).dot(fore_axis) / fore_axis.length_squared, 0.0), 1.0)
                axis = fore_axis.normalized()
                centre = elbow + fore_axis * t
                r = v.co - centre
                r -= axis * r.dot(axis)
                front = Vector((0.0, -1.0, 0.0))
                front = (front - axis * front.dot(axis)).normalized()
                out = Vector((sign, 0.0, 0.0))
                out = (out - axis * out.dot(axis)).normalized()
                a = math.atan2(r.dot(out), r.dot(front))
                limb[v.index] = (t * 0.5, math.cos(a) * 0.5 + 0.5, math.sin(a) * 0.5 + 0.5)
                extra[v.index] = (min(fore + hand, 1.0), 0.5, 0.0)
            else:
                t = 1.0 + min(max((v.co - wrist).dot(hand_axis) / hand_axis.length_squared, 0.0), 1.0)
                facing = _smooth(0.1, 0.5, v.normal.dot(back_of_hand))
                u = (v.co - middle).dot(across_dir)
                limb[v.index] = (t * 0.5, 0.5, 0.5)
                extra[v.index] = (min(fore + hand, 1.0) * facing, u * 5.0 + 0.5, 0.0)
    return limb, extra


def forearm_veins(coords, extra):
    """Height of the veins (0..1) per pixel of the relief map, from the baked limb coordinates."""
    import numpy as np
    t = coords[..., 0] * 2.0
    a = np.arctan2(coords[..., 2] * 2.0 - 1.0, coords[..., 1] * 2.0 - 1.0)
    weight = extra[..., 0]
    u = (extra[..., 1] - 0.5) / 5.0
    wrap = lambda x: (x + math.pi) % (2.0 * math.pi) - math.pi
    smooth = lambda lo, hi, x: np.clip((x - lo) / (hi - lo), 0.0, 1.0) ** 2 * (3.0 - 2.0 * np.clip((x - lo) / (hi - lo), 0.0, 1.0))
    height = np.zeros_like(t)
    fore = (t > 0.0) & (t < 1.0)
    for a0, wander, waves, phase, t0, t1, half, k in FOREARM_VEINS:
        path = a0 + wander * np.sin(waves * t + phase) + 0.1 * np.sin(2.7 * waves * t + 1.3 * phase)
        d = wrap(a - path) * FOREARM_RADIUS
        span = smooth(t0, t0 + 0.12, t) * (1.0 - smooth(t1 - 0.12, t1, t))
        # Veins swell toward the wrist, where there is less flesh over them.
        height += k * np.exp(-(d / half) ** 2) * span * (0.6 + 0.4 * t)
    c_t0, c_a0, c_t1, c_a1, c_half, c_k = CUBITAL
    along = np.clip((t - c_t0) / (c_t1 - c_t0), 0.0, 1.0)
    d = wrap(a - (c_a0 + (c_a1 - c_a0) * along)) * FOREARM_RADIUS
    height += c_k * np.exp(-(d / c_half) ** 2) * smooth(c_t0 - 0.02, c_t0 + 0.03, t) * (1.0 - smooth(c_t1 - 0.03, c_t1 + 0.02, t))
    height = np.where(fore, height, 0.0)
    hand = (t >= 1.0) & (t < 2.0)
    th = t - 1.0
    for u0, spread, k in HAND_VEINS:
        path = u0 + spread * th + 0.003 * np.sin(9.0 * th + u0 * 400.0)
        h = k * np.exp(-((u - path) / 0.0028) ** 2) * smooth(0.0, 0.2, th) * (1.0 - smooth(0.6, 0.85, th))
        height += np.where(hand, h, 0.0)
    height = np.clip(height, 0.0, 1.0) * weight
    # Softened by a pixel: round, not ridged.
    return _box(_box(height, 1), 1)


def body_marks(body, top):
    """Landmarks the gear is fitted by: eye, ear (both and their middle), chin and lips from
    MakeHuman's joint and part groups; heights of the belt and chest; the trunk's middle front
    to back at chest height."""
    def centre(name, side=0.0):
        w = _group_weights(body, name)
        pts = [v.co for v in body.data.vertices if w[v.index] > 0.5 and (side == 0.0 or v.co.x * side > 0.0)]
        return sum(pts, Vector()) / len(pts)

    marks = {
        "eye": (centre("joint-l-eye") + centre("joint-r-eye")) * 0.5,
        "ear_l": centre("ears", 1.0), "ear_r": centre("ears", -1.0),
        "chin": centre("joint-jaw"), "lips": centre("lips"),
        "belt": top * BELT_CENTRE, "chest": top * 0.72,
    }
    marks["ear"] = (marks["ear_l"] + marks["ear_r"]) * 0.5
    trunk = [v.co.y for v in body.data.vertices if abs(v.co.z - marks["chest"]) < 0.01 and abs(v.co.x) < 0.08]
    marks["trunk_y"] = (max(trunk) + min(trunk)) * 0.5
    return marks


def bake_skin_maps(body, rig, hidden, detail_png, relief_png, size=1024):
    """Bakes the maps the game's skin shader reads (docs/13 S14: skin that reads as a
    person's, not a doll's), onto the body's own UVs:
      detail (per build): R ambient occlusion within 7 cm (the creases of the
        eyes, nostrils, mouth and ears, between the fingers; not the shadow of an arm, which
        moves) times the hollows of the surface (between the muscles of the shoulders, arms
        and neck, the collarbones, the knuckles), G roughness (the forehead and nose shine,
        the lips more), B where the beard grows (for stubble), A 1 - half the veins' height
        (for their colour);
      relief (the same for every build): the painted skin's fine detail (creases, grain,
        knuckles) as a normal map, from the texture's own light and dark: the high-pass of
        its brightness taken as height; and the raised veins of the forearms and the backs of
        the hands (see forearm_veins).
    `hidden` are objects left out of the occlusion (hair, brows, lashes)."""
    import numpy as np
    scene = bpy.context.scene
    verts = body.data.vertices

    def centre(name):
        w = _group_weights(body, name)
        pts = [v.co for v in verts if w[v.index] > 0.5]
        return sum(pts, Vector()) / len(pts)

    lips_w, ears_w, scalp_w = (_group_weights(body, n) for n in ("lips", "ears", "scalp"))
    lips = centre("lips")
    ear_pts = [v.co for v in verts if ears_w[v.index] > 0.5 and v.co.x > 0.0]
    ear = sum(ear_pts, Vector()) / len(ear_pts)
    chin = centre("joint-jaw")
    eye = (centre("joint-l-eye") + centre("joint-r-eye")) * 0.5

    def beard(co, i):
        # From just under the nose, rising at the sides to the sideburns in front of the ears,
        # down over the chin to just under the jaw.
        r = min(abs(co.x) / ear.x, 1.2)
        top = lips.z + 0.022 + (ear.z - 0.005 - (lips.z + 0.022)) * _smooth(0.5, 0.92, r)
        w = 1.0 - _smooth(top - 0.012, top + 0.006, co.z)
        w *= _smooth(chin.z - 0.045, chin.z - 0.02, co.z)
        w *= 1.0 - _smooth(ear.y - 0.012, ear.y + 0.004, co.y)
        return max(w * (1.0 - lips_w[i]) * (1.0 - ears_w[i]) * (1.0 - scalp_w[i]), 0.0)

    def roughness(co, i):
        front = 1.0 - _smooth(ear.y - 0.03, ear.y - 0.01, co.y)
        nose = (1.0 - _smooth(0.012, 0.025, abs(co.x))) * _smooth(lips.z + 0.015, lips.z + 0.03, co.z) * (1.0 - _smooth(eye.z, eye.z + 0.01, co.z))
        forehead = (1.0 - _smooth(0.04, 0.06, abs(co.x))) * _smooth(eye.z + 0.025, eye.z + 0.04, co.z) * (1.0 - scalp_w[i])
        oil = max(nose, forehead) * front
        return 0.55 - 0.15 * oil - 0.2 * lips_w[i]

    cavity = surface_hollows(body)
    limb, limb_extra = limb_coordinates(body, rig)
    attr = body.data.color_attributes.new("SkinDetail", 'FLOAT_COLOR', 'POINT')
    for v in verts:
        attr.data[v.index].color = (cavity[v.index], roughness(v.co, v.index), beard(v.co, v.index), 1.0)
    # Where on the face (for the lines of the face): position relative to the eyes, packed
    # into 0..1 over a 30 cm box; 0 off the head.
    head_attr = body.data.color_attributes.new("HeadPos", 'FLOAT_COLOR', 'POINT')
    for v in verts:
        rel = (v.co - eye) / 0.3 + Vector((0.5, 0.5, 0.5))
        on_head = v.co.z > chin.z - 0.03 and v.co.y < ear.y + 0.02
        head_attr.data[v.index].color = (*(rel if on_head else Vector((0.0, 0.0, 0.0))), 1.0)
    limb_attr = body.data.color_attributes.new("LimbCoords", 'FLOAT_COLOR', 'POINT')
    extra_attr = body.data.color_attributes.new("LimbExtra", 'FLOAT_COLOR', 'POINT')
    for v in verts:
        limb_attr.data[v.index].color = (*limb[v.index], 1.0)
        extra_attr.data[v.index].color = (*limb_extra[v.index], 1.0)

    # A bake material on every face for the time being.
    kept = list(body.data.materials)
    kept_index = [p.material_index for p in body.data.polygons]
    bake_mat = bpy.data.materials.new("SkinBake")
    bake_mat.use_nodes = True
    nt = bake_mat.node_tree
    nt.nodes.clear()
    attribute = nt.nodes.new("ShaderNodeAttribute")
    attribute.attribute_name = "SkinDetail"
    emit = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(attribute.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    target = nt.nodes.new("ShaderNodeTexImage")
    nt.nodes.active = target
    body.data.materials.clear()
    body.data.materials.append(bake_mat)
    for p in body.data.polygons:
        p.material_index = 0

    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 0.07
    scene.render.engine = 'CYCLES'
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.margin = 8
    for obj in bpy.data.objects:
        obj.select_set(obj == body)
    bpy.context.view_layer.objects.active = body
    was_hidden = {o: o.hide_render for o in hidden}
    for o in hidden:
        o.hide_render = True
    images = {}
    relief_size = 2048
    for name, kind, samples, attribute_name, bake_size in (
            ('AO', 'AO', 32, "SkinDetail", size), ('EMIT', 'EMIT', 1, "SkinDetail", size),
            ('LIMB', 'EMIT', 1, "LimbCoords", relief_size), ('LIMB2', 'EMIT', 1, "LimbExtra", relief_size),
            ('HEAD', 'EMIT', 1, "HeadPos", relief_size)):
        image = bpy.data.images.new("Skin" + name, bake_size, bake_size, alpha=False, float_buffer=True)
        image.colorspace_settings.name = "Non-Color"
        target.image = image
        attribute.attribute_name = attribute_name
        scene.cycles.samples = samples
        # Limb coordinates must not run on past the edges of their islands into others.
        scene.render.bake.margin = 8 if name in ('AO', 'EMIT') else 2
        bpy.ops.object.bake(type=kind)
        images[name] = _pixels(image)
    scene.render.bake.margin = 8
    for o, h in was_hidden.items():
        o.hide_render = h

    body.data.materials.clear()
    for m in kept:
        body.data.materials.append(m)
    for p, i in zip(body.data.polygons, kept_index):
        p.material_index = i
    for name in ("SkinDetail", "LimbCoords", "LimbExtra", "HeadPos"):
        body.data.color_attributes.remove(body.data.color_attributes[name])

    veins = forearm_veins(images['LIMB'], images['LIMB2'])
    lines = face_lines(images['HEAD'], {k: (v - eye) for k, v in (("lips", lips), ("chin", chin), ("ear", ear))})
    ao, emitted = images['AO'], images['EMIT']
    detail = np.ones((size, size, 4), dtype=np.float32)
    detail[..., 0] = ao[..., 0] * np.where(emitted[..., 1] > 0.1, emitted[..., 0], 1.0)
    f = relief_size // size
    detail[..., 0] *= 1.0 - 0.12 * lines.reshape(size, f, size, f).mean(axis=(1, 3))
    detail[..., 1] = emitted[..., 1]
    detail[..., 2] = emitted[..., 2]
    # Stored as 1 - height/2: an image importer fills fully clear pixels with their neighbours' colour.
    detail[..., 3] = 1.0 - 0.5 * veins.reshape(size, f, size, f).mean(axis=(1, 3))
    _save(detail, detail_png, alpha=True)

    # Relief from the painted skin, on the islands of the UV map only (no slopes at their edges).
    diffuse = None
    for m in kept:
        if m is None or not m.use_nodes:
            continue
        for n in m.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image is not None and "diffuse" in n.image.name.lower():
                diffuse = n.image
    if diffuse is None:
        print("make_player: no painted skin, no relief map")
        return
    rgb = _pixels(diffuse)
    lum = rgb[..., 0] * 0.3 + rgb[..., 1] * 0.59 + rgb[..., 2] * 0.11
    n = lum.shape[0]
    inside = np.kron(emitted[..., 1] > 0.1, np.ones((n // size, n // size))) if n >= size else (emitted[..., 1] > 0.1)
    inside = _box(inside.astype(np.float32), 3) > 0.999
    # Fine detail only (a few millimetres): coarser, it reads as goose flesh on the arms.
    height = lum - _box(_box(lum, 2), 2)
    height = np.where(inside, height, 0.0)
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    gy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    spread = float(np.std(np.concatenate([gx[inside], gy[inside]])))
    k = 0.1 / max(spread, 1e-6)
    nx, ny = np.clip(-gx * k, -0.6, 0.6), np.clip(-gy * k, -0.6, 0.6)
    if n == relief_size:
        # Veins stand up; the lines of the face are creases (down).
        height = veins * VEIN_SLOPE - lines * LINE_SLOPE
        vx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
        vy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
        nx = np.clip(nx - vx, -0.7, 0.7)
        ny = np.clip(ny - vy, -0.7, 0.7)
    nz = np.sqrt(np.maximum(1.0 - nx * nx - ny * ny, 0.0))
    relief = np.ones((n, n, 4), dtype=np.float32)
    relief[..., 0] = nx * 0.5 + 0.5
    relief[..., 1] = ny * 0.5 + 0.5
    relief[..., 2] = nz * 0.5 + 0.5
    _save(relief, relief_png)
    print("make_player: baked skin detail %s and relief %s" % (detail_png, relief_png))


def _save(pixels, path, alpha=False):
    image = bpy.data.images.new(os.path.basename(path), pixels.shape[1], pixels.shape[0], alpha=alpha)
    image.colorspace_settings.name = "Non-Color"
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = path
    image.file_format = 'PNG'
    if alpha:
        image.alpha_mode = 'STRAIGHT'
    image.save()


class Anatomy:
    """Answers "which part of the body is this face" from bone weights and positions."""

    CHILD = {"upperarm": "lowerarm", "calf": "foot", "thigh": "calf", "lowerarm": "hand"}

    def __init__(self, body, rig, bm):
        self.rig = rig
        self.deform = bm.verts.layers.deform.verify()
        self.bone_of_group = {g.index: g.name for g in body.vertex_groups if g.name in rig.data.bones}
        # The body stands on the ground, so its highest point is its height.
        self.waist = max(v.co.z for v in bm.verts) * BELT_CENTRE
        neck = rig.data.bones["neck_01"]
        head = rig.data.bones["head"]
        self.collar_n = (head.head_local - neck.head_local).normalized()
        self.collar_co = neck.head_local + self.collar_n * 0.012

    def bone(self, face):
        totals = {}
        for v in face.verts:
            for group, weight in v[self.deform].items():
                name = self.bone_of_group.get(group)
                if name:
                    totals[name] = totals.get(name, 0.0) + weight
        return max(totals, key=totals.get) if totals else "head"

    def along(self, bone_name, point):
        stem, side = bone_name.rsplit("_", 1)
        start = self.rig.data.bones[bone_name].head_local
        end = self.rig.data.bones["%s_%s" % (self.CHILD[stem], side)].head_local
        axis = end - start
        return (point - start).dot(axis) / axis.length_squared

    def plane(self, bone_name, fraction):
        stem, side = bone_name.rsplit("_", 1)
        start = self.rig.data.bones[bone_name].head_local
        end = self.rig.data.bones["%s_%s" % (self.CHILD[stem], side)].head_local
        return start.lerp(end, fraction), (end - start).normalized()

    NECK_RADIUS = 0.082

    def v_half_width(self, z):
        """Half the width of the V at a height (0 below its point)."""
        below = z - (self.collar_co.z - V_DEPTH)
        return max(V_TOP_HALF * below / V_DEPTH, 0.0)

    def in_vneck(self, point):
        """Inside the jersey's V at the front (where the undershirt shows)."""
        if point.y > self.collar_co.y or point.z < self.collar_co.z - V_DEPTH:
            return False
        return abs(point.x - self.collar_co.x) < self.v_half_width(point.z)

    def outside_neckline(self, point):
        """Distance (m) from the neck opening; 0 or less means bare neck. The opening is a
        cylinder around the neck, so the tops of the shoulders stay covered."""
        rel = point - self.collar_co
        up = rel.dot(self.collar_n)
        radial = (rel - self.collar_n * up).length
        return max(radial - self.NECK_RADIUS, 0.0) + max(-up, 0.0)

    def region(self, face):
        """Region of a face and how deep it lies under the nearest hem (metres, 0 if exposed)."""
        bone = self.bone(face)
        c = face.calc_center_median()
        if bone == "head":
            return SKIN, 0.0
        if bone == "neck_01" or bone.startswith(("spine_", "clavicle_")) or bone == "pelvis":
            covered = self.outside_neckline(c)
            if covered <= 0.0:
                return SKIN, 0.0
            if self.in_vneck(c):
                return UNDERSHIRT, 0.0
            if c.z > self.waist + BELT_HALF:
                return JERSEY, covered
            return (BELT if c.z > self.waist - BELT_HALF else PANTS), 1.0
        if bone.startswith("upperarm_"):
            t = self.along(bone, c)
            length = (self.rig.data.bones[bone].head_local - self.plane(bone, 1.0)[0]).length
            return (JERSEY, (SLEEVE_HEM - t) * length) if t < SLEEVE_HEM else (SKIN, 0.0)
        if bone.startswith("lowerarm_"):
            return SKIN, 0.0
        if bone.startswith("thigh_"):
            return PANTS, 1.0
        if bone.startswith("calf_"):
            t = self.along(bone, c)
            length = (self.rig.data.bones[bone].head_local - self.plane(bone, 1.0)[0]).length
            return (PANTS, (PANTS_HEM - t) * length) if t < PANTS_HEM else (SOCKS, 0.0)
        if bone.startswith(("foot_", "ball_")):
            return SHOES, 1.0
        return HANDS, 0.0


def cut(bm, anatomy, bones, plane_co, plane_no):
    """Splits the faces of the given bones along a plane so a hem can follow a straight line."""
    faces = [f for f in bm.faces if anatomy.bone(f) in bones]
    geom = set(faces)
    for f in faces:
        geom.update(f.edges)
        geom.update(f.verts)
    bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-5, plane_co=plane_co, plane_no=plane_no)


def prepare_body(body, rig):
    """Removes MakeHuman's helper geometry, cuts hem lines and labels every face with its
    region. Returns the foot vertices per side for the shoes."""
    for modifier in list(body.modifiers):
        if modifier.type == 'MASK':
            body.modifiers.remove(modifier)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    deform = bm.verts.layers.deform.verify()
    body_group = body.vertex_groups["body"].index
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v[deform].get(body_group, 0.0) < 0.5], context='VERTS')

    anatomy = Anatomy(body, rig, bm)
    torso = {"pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "clavicle_l", "clavicle_r"}
    for z in (anatomy.waist + BELT_HALF, anatomy.waist - BELT_HALF):
        cut(bm, anatomy, torso, Vector((0.0, 0.0, z)), Vector((0.0, 0.0, 1.0)))
    # The V of the neckline: two planes through its sides, cutting only the front of the chest
    # near the neck, so its edges are straight lines rather than steps along the faces.
    top = anatomy.collar_co
    tip = Vector((top.x, top.y, top.z - V_DEPTH))
    near = [f for f in bm.faces if anatomy.bone(f) in torso and f.calc_center_median().y < top.y
            and top.z - V_DEPTH - 0.03 < f.calc_center_median().z < top.z + 0.05]
    for sign in (1.0, -1.0):
        along = Vector((sign * V_TOP_HALF, 0.0, V_DEPTH)).normalized()
        normal = along.cross(Vector((0.0, 1.0, 0.0))).normalized()
        geom = set(near)
        for f in near:
            geom.update(f.edges)
            geom.update(f.verts)
        bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-5, plane_co=tip, plane_no=normal)
        bm.faces.ensure_lookup_table()
        near = [f for f in bm.faces if anatomy.bone(f) in torso and f.calc_center_median().y < top.y
                and top.z - V_DEPTH - 0.03 < f.calc_center_median().z < top.z + 0.05]
    for side in ("l", "r"):
        cut(bm, anatomy, {"upperarm_" + side}, *anatomy.plane("upperarm_" + side, SLEEVE_HEM))
        cut(bm, anatomy, {"calf_" + side}, *anatomy.plane("calf_" + side, PANTS_HEM))

    bm.faces.ensure_lookup_table()
    region = bm.faces.layers.int.new("region")
    depth = bm.faces.layers.float.new("depth")
    feet = {"l": [], "r": []}
    for face in bm.faces:
        face.smooth = True
        face[region], face[depth] = anatomy.region(face)
        if face[region] == SHOES:
            feet["l" if face.calc_center_median().x > 0.0 else "r"].extend(v.co.copy() for v in face.verts)
    head = [v.co.copy() for v in bm.verts
            if any(anatomy.bone_of_group.get(g) == "head" and w > 0.6 for g, w in v[deform].items())]
    bm.to_mesh(body.data)
    bm.free()
    return feet, head


def make_garment(body, name, regions, looseness, slots, anatomy_of, snap_neckline=None):
    """Copies the faces of some regions into a new mesh, subdivides it once for a smoother
    outline, lifts every point off the skin by how loose the garment is there (looseness:
    vertex -> metres, docs/13 S11-2), smooths away the anatomy underneath and unwraps it
    front/back. The copied skin weights make it move with the body."""
    obj = body.copy()
    obj.data = body.data.copy()
    obj.name = obj.data.name = name
    bpy.context.scene.collection.objects.link(obj)
    # Clothes do not need the face keys.
    obj.shape_key_clear()

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    region = bm.faces.layers.int["region"]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f[region] not in regions], context='FACES')
    bm.to_mesh(obj.data)
    bm.free()
    # One level of subdivision; applying the modifier carries the bone weights and the face
    # regions over to the new points and faces.
    sub = obj.modifiers.new("Subdivide", 'SUBSURF')
    sub.levels = 1
    sub.render_levels = 1
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier=sub.name)

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    region = bm.faces.layers.int["region"]
    anatomy = anatomy_of(obj, bm)
    bm.normal_update()
    hem = {v for e in bm.edges if e.is_boundary for v in e.verts}
    lifts = {v: looseness(v, anatomy, v in hem) for v in bm.verts}
    for v in bm.verts:
        v.co += v.normal * lifts[v]
    inner = [v for v in bm.verts if v not in hem]
    for _ in range(6):
        bmesh.ops.smooth_vert(bm, verts=inner, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    if snap_neckline is not None:
        snap_neckline(hem, anatomy)
    bm.normal_update()

    # Front/back planar UVs: u runs across the body, v from the bottom to the top of the
    # garment. The front fills the left half of the texture and the back the right half,
    # mirrored so that lettering reads correctly from behind.
    xs = [v.co.x for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        front = face.normal.y < 0.0
        for loop in face.loops:
            across = (loop.vert.co.x - x0) / (x1 - x0)
            u = 0.5 * across if front else 0.5 + 0.5 * (1.0 - across)
            loop[uv].uv = (u, (loop.vert.co.z - z0) / (z1 - z0))
        face.material_index = slots.index(face[region])
    # Slots first, then the mesh: clearing materials afterwards would reset the indices.
    obj.data.materials.clear()
    for slot in slots:
        obj.data.materials.append(material({JERSEY: "Jersey", PANTS: "Pants", BELT: "Belt"}[slot]))
    bm.to_mesh(obj.data)
    bm.free()
    print("make_player: %s %d faces, x %.2f..%.2f m, z %.2f..%.2f m" % (name, len(obj.data.polygons), x0, x1, z0, z1))
    return obj


def bake_folds(garment, body, out_png, pinned, size=1024, frames=40, slack=0.045):
    """Bakes a garment's folds into a normal map (docs/13 S11-2): a finer copy of it is hung
    on the body as cloth, held where it is held in life (pinned(co) -> True), given a little
    more cloth than the body needs (slack) so it gathers into folds as it settles, and the
    difference between the settled copy and the garment is baked onto the garment's own UVs.
    The game lays the map on the uniform; the folds stay where the cloth settled."""
    scene = bpy.context.scene
    hi = garment.copy()
    hi.data = garment.data.copy()
    hi.name = hi.data.name = garment.name + "Cloth"
    scene.collection.objects.link(hi)
    for m in list(hi.modifiers):
        hi.modifiers.remove(m)
    sub = hi.modifiers.new("Finer", 'SUBSURF')
    sub.levels = 2
    with bpy.context.temp_override(object=hi, active_object=hi, selected_objects=[hi]):
        bpy.ops.object.modifier_apply(modifier=sub.name)
    pins = hi.vertex_groups.new(name="Pins")
    pins.add([v.index for v in hi.data.vertices if pinned(v.co)], 1.0, 'REPLACE')

    collide = body.modifiers.new("Collide", 'COLLISION')
    collide.settings.thickness_outer = 0.004
    cloth = hi.modifiers.new("Cloth", 'CLOTH')
    s = cloth.settings
    s.quality = 6
    s.mass = 0.15
    s.air_damping = 2.0
    # Stiff enough in bending to fold in a few broad soft folds, not fine pleats.
    s.tension_stiffness = 10.0
    s.compression_stiffness = 10.0
    s.shear_stiffness = 6.0
    s.bending_stiffness = 0.6
    s.shrink_min = -slack
    s.vertex_group_mass = "Pins"
    cs = cloth.collision_settings
    cs.distance_min = 0.004
    cs.use_self_collision = False
    cloth.point_cache.frame_start = 1
    cloth.point_cache.frame_end = frames
    scene.frame_start = 1
    scene.frame_end = frames
    for f in range(1, frames + 1):
        scene.frame_set(f)
    settled = bpy.data.meshes.new_from_object(hi.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    hi.modifiers.clear()
    hi.data = settled
    body.modifiers.remove(collide)
    scene.frame_set(1)

    # Bake: the settled cloth's surface onto the garment, as tangent-space normals.
    image = bpy.data.images.new(garment.name + "Folds", size, size, alpha=False)
    image.colorspace_settings.name = "Non-Color"
    added = []
    for mat in garment.data.materials:
        mat.use_nodes = True
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        mat.node_tree.nodes.active = node
        added.append((mat, node))
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 1
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = 0.02
    scene.render.bake.max_ray_distance = 0.035
    scene.render.bake.margin = 8
    for obj in bpy.data.objects:
        obj.select_set(obj in (hi, garment))
    bpy.context.view_layer.objects.active = garment
    bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT')
    image.filepath_raw = out_png
    image.file_format = 'PNG'
    image.save()
    # The shade in the folds: how hollow the settled cloth is, carried over the same way
    # (the creases of a real jersey are darker; the light does not reach into them).
    shade = surface_hollows(hi, group=None, strength=0.6)
    attr = hi.data.color_attributes.new("FoldShade", 'FLOAT_COLOR', 'POINT')
    for i, value in enumerate(shade):
        attr.data[i].color = (value, value, value, 1.0)
    emit_mat = bpy.data.materials.new("FoldShadeBake")
    emit_mat.use_nodes = True
    nt = emit_mat.node_tree
    nt.nodes.clear()
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = "FoldShade"
    e = nt.nodes.new("ShaderNodeEmission")
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(a.outputs["Color"], e.inputs["Color"])
    nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    hi.data.materials.clear()
    hi.data.materials.append(emit_mat)
    shade_image = bpy.data.images.new(garment.name + "Shade", size, size, alpha=False)
    shade_image.colorspace_settings.name = "Non-Color"
    shade_image.generated_color = (1.0, 1.0, 1.0, 1.0)
    for mat, node in added:
        node.image = shade_image
    bpy.ops.object.bake(type='EMIT')
    shade_png = out_png.replace("_folds.png", "_shade.png")
    shade_image.filepath_raw = shade_png
    shade_image.file_format = 'PNG'
    shade_image.save()
    for mat, node in added:
        mat.node_tree.nodes.remove(node)
    bpy.data.objects.remove(hi)
    print("make_player: baked %s folds to %s (and the shade in them)" % (garment.name, out_png))


def make_collar(rig):
    """A band round the base of the neck that finishes the jersey's neckline."""
    neck = rig.data.bones["neck_01"]
    axis = (rig.data.bones["head"].head_local - neck.head_local).normalized()
    centre = neck.head_local + axis * 0.012
    side = axis.cross(Vector((0.0, 1.0, 0.0))).normalized()
    front = side.cross(axis).normalized()
    bm = bmesh.new()
    inner, outer = [], []
    segments = 28
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        around = side * math.cos(a) + front * math.sin(a)
        inner.append(bm.verts.new(centre + around * (Anatomy.NECK_RADIUS - 0.012) + axis * 0.016))
        outer.append(bm.verts.new(centre + around * (Anatomy.NECK_RADIUS + 0.02) - axis * 0.01))
    for i in range(segments):
        n = (i + 1) % segments
        bm.faces.new((inner[i], inner[n], outer[n], outer[i]))
    return skinned_object("Collar", bm, rig, lambda co: "spine_03", "Collar")


def strip_body(body):
    """Removes skin that is well under clothing or inside the shoes and sets body materials."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    region = bm.faces.layers.int["region"]
    depth = bm.faces.layers.float["depth"]
    hidden = [f for f in bm.faces if f[region] == SHOES or (f[region] in (JERSEY, BELT, PANTS) and f[depth] > TUCK)]
    bmesh.ops.delete(bm, geom=hidden, context='FACES')
    for face in bm.faces:
        face.material_index = {HANDS: 1, SOCKS: 2, UNDERSHIRT: 3}.get(face[region], 0)
    # Keep the textured skin if there is one; the hands get their own copy so the game can
    # swap them for batting gloves.
    textured = body.data.materials[0] if len(body.data.materials) > 0 else None
    if textured is not None and textured.name not in COLOURS:
        skin = textured
        skin.name = "Skin"
        hands = skin.copy()
        hands.name = "Hands"
    else:
        skin, hands = material("Skin"), material("Hands")
    body.data.materials.clear()
    for mat in (skin, hands, material("Socks"), material("Undershirt")):
        body.data.materials.append(mat)
    bm.to_mesh(body.data)
    bm.free()


def skinned_object(name, bm, rig, weights, mat_name):
    """Wraps a bmesh as an object deformed by the rig. weights(vertex position) -> bone name."""
    for face in bm.faces:
        face.smooth = True
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.materials.append(material(mat_name))
    by_bone = {}
    for v in mesh.vertices:
        by_bone.setdefault(weights(v.co), []).append(v.index)
    for bone, indices in by_bone.items():
        obj.vertex_groups.new(name=bone).add(indices, 1.0, 'REPLACE')
    obj.parent = rig
    obj.modifiers.new("Armature", 'ARMATURE').object = rig
    return obj


def make_shoes(feet, rig):
    """A convex shell around each foot hides the toes and reads as a shoe."""
    bm = bmesh.new()
    for side in ("l", "r"):
        verts = [bm.verts.new(co) for co in feet[side]]
        hull = bmesh.ops.convex_hull(bm, input=verts)
        unused = {g for g in hull.get("geom_unused", []) + hull.get("geom_interior", []) if isinstance(g, bmesh.types.BMVert)}
        bmesh.ops.delete(bm, geom=list(unused), context='VERTS')
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * 0.005
        v.co.z = max(v.co.z, 0.0)

    def weights(co):
        side = "l" if co.x > 0.0 else "r"
        toes = rig.data.bones["ball_" + side].head_local
        return ("ball_" if co.y < toes.y else "foot_") + side
    return skinned_object("Shoes", bm, rig, weights, "Shoes")


def head_box(head_points):
    xs = [p.x for p in head_points]
    ys = [p.y for p in head_points]
    zs = [p.z for p in head_points]
    centre = Vector(((max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5, 0.0))
    return centre, (max(xs) - min(xs)) * 0.5, (max(ys) - min(ys)) * 0.5, max(zs), max(zs) - min(zs)


def dome(bm, centre, rx, ry, rz, down, face_open=None):
    """Half-ellipsoid shell reaching `down` radians below its equator. If face_open is a
    height, vertices on the front (-Y) half are not allowed below it, leaving the face clear."""
    rings, segments = 9, 24
    rows = []
    for r in range(rings + 1):
        phi = (math.pi * 0.5 + down) * r / rings
        row = []
        for seg in range(segments):
            theta = 2.0 * math.pi * seg / segments
            p = centre + Vector((rx * math.sin(phi) * math.cos(theta), ry * math.sin(phi) * math.sin(theta), rz * math.cos(phi)))
            if face_open is not None and math.sin(theta) < -0.25:
                p.z = max(p.z, face_open)
            row.append(bm.verts.new(p))
        rows.append(row)
    for r in range(rings):
        for seg in range(segments):
            n = (seg + 1) % segments
            bm.faces.new((rows[r][seg], rows[r][n], rows[r + 1][n], rows[r + 1][seg]))


def brim(bm, centre, rx, ry, z, reach, spread_deg):
    """Curved strip in front of the face (-Y is forward in Blender)."""
    inner, outer = [], []
    steps = 10
    for i in range(steps + 1):
        a = math.radians(-spread_deg + 2.0 * spread_deg * i / steps)
        inner.append(bm.verts.new(Vector((centre.x + rx * 0.98 * math.sin(a), centre.y - ry * 0.98 * math.cos(a), z))))
        out = reach * math.cos(a) ** 0.6
        outer.append(bm.verts.new(Vector((centre.x + (rx + 0.012) * math.sin(a), centre.y - (ry * math.cos(a) + out), z - 0.012))))
    for i in range(steps):
        bm.faces.new((inner[i], inner[i + 1], outer[i + 1], outer[i]))


def make_cap(head_points, rig):
    """Fitted cap: a dome over the skull and a brim over the eyes."""
    centre, half_w, half_d, top, height = head_box(head_points)
    rx, ry, rz = half_w + 0.010, half_d + 0.010, height * 0.40
    centre.z = top - rz + 0.012
    bm = bmesh.new()
    dome(bm, centre, rx, ry, rz, 0.22)
    brim(bm, centre, rx, ry, centre.z + rz * math.cos(math.pi * 0.5 + 0.12), 0.075, 70.0)
    return skinned_object("Cap", bm, rig, lambda co: "head", "Cap")


def add_hair(body):
    """Fits the four short styles to the body (before its helper geometry is removed: the
    fitting needs the original mesh). Returns the hair objects, named Hair1 to Hair4."""
    import zipfile
    assets = os.path.join(ROOT, ".tools", "mpfb-dl", "system_assets.zip")
    out_dir = os.path.join(ROOT, "build", "hair")
    hair = []
    if not os.path.exists(assets):
        print("make_player: no MakeHuman system assets, no hair")
        return hair
    with zipfile.ZipFile(assets) as z:
        for name in z.namelist():
            if any(name.startswith("hair/%s/" % s) for s in HAIR_STYLES) and not name.endswith("/"):
                z.extract(name, out_dir)
    for i, style in enumerate(HAIR_STYLES):
        mhclo = os.path.join(out_dir, "hair", style, style + ".mhclo")
        obj = HumanService.add_mhclo_asset(mhclo, body, asset_type="Hair", subdiv_levels=0, material_type="MAKESKIN")
        obj.name = obj.data.name = "Hair%d" % (i + 1)
        for slot in obj.material_slots:
            if slot.material is not None:
                slot.material.name = "Hair"
                for node in slot.material.node_tree.nodes if slot.material.node_tree else []:
                    if node.type == 'TEX_IMAGE' and node.image is not None and node.image.size[0] > HAIR_TEXTURE:
                        node.image.scale(HAIR_TEXTURE, HAIR_TEXTURE)
        hair.append(obj)
    return hair


def trim_hair(hair, head_points):
    """Cuts away the hair that would be under the cap (above its rim): a cap fits close to the
    skull, so hair left there would show through it. Returns how many points were left above
    the rim (0)."""
    centre, half_w, half_d, top, height = head_box(head_points)
    rz = height * 0.40
    cap_centre_z = top - rz + 0.012
    rim = cap_centre_z - rz * math.sin(0.22)
    left = 0
    for obj in hair:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > rim - 0.004], context='VERTS')
        left += sum(1 for v in bm.verts if v.co.z > rim)
        bm.to_mesh(obj.data)
        bm.free()
        print("make_player: %s %d faces below the cap" % (obj.name, len(obj.data.polygons)))
    return left


def make_cap_button(head_points, rig):
    """The button on top of the cap."""
    centre, half_w, half_d, top, height = head_box(head_points)
    bm = bmesh.new()
    dome(bm, Vector((centre.x, centre.y, top + 0.012)), 0.009, 0.009, 0.006, 0.0)
    return skinned_object("CapButton", bm, rig, lambda co: "head", "Cap")


def render_preview(path, target_z, close=False):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x, scene.render.resolution_y = 900, 760
    world = bpy.data.worlds.get("Preview") or bpy.data.worlds.new("Preview")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62, 0.66, 0.72, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    sun = bpy.data.objects.get("PreviewSun")
    if sun is None:
        sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", 'SUN'))
        sun.data.energy = 3.0
        sun.rotation_euler = (math.radians(50), 0.0, math.radians(-35))
        scene.collection.objects.link(sun)
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        cam.data.lens = 60
        scene.collection.objects.link(cam)
    cam.location = (2.6, -4.6, target_z + 0.25)
    if close:
        cam.location = (0.55, -0.95, target_z + 0.08)
    direction = Vector((0.0, 0.0, target_z)) - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    clear_scene()
    macro = TargetService.get_default_macro_info_dict()
    macro.update(MACRO)
    macro.update(BUILDS.get(BUILD, {}))
    macro["race"] = dict(RACE)
    # feet_on_ground is left off: it moves the mesh but not the rig that is fitted afterwards.
    # Both are moved to the ground together below.
    # detailed_helpers must be on: it adds the joint markers the rig is fitted to. Without them
    # the rig keeps the joint positions of the default body, and its bones do not line up with
    # this body's shoulders, elbows, hips and knees.
    body = HumanService.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True,
                                     feet_on_ground=False, scale=0.1, macro_detail_dict=macro)
    for name, weight in SHAPE.items():
        TargetService.load_target(body, TargetService.target_full_path(name), weight=weight, name=name)
    rig = HumanService.add_builtin_rig(body, "game_engine", import_weights=True)
    face_parts = add_skin_and_face(body)
    TargetService.bake_targets(body)
    # The face keys stay as keys (weight 0) for the game to set per player.
    for name in FACE_KEYS:
        TargetService.load_target(body, TargetService.target_full_path(name), weight=0.0, name="face_" + name)
    stand_on_ground(body, rig)
    hair = add_hair(body)
    stem = os.path.splitext(OUT_GLB)[0]
    marks = body_marks(body, max(v.co.z for v in body.data.vertices))
    bake_skin_maps(body, rig, [*hair, *[p for p in face_parts if p.name != "Eyes"]], stem + "_skin_detail.png",
                   os.path.join(os.path.dirname(OUT_GLB), "player_skin_relief.png"))
    if os.environ.get("SKIN_ONLY"):
        # Quick look at the skin maps alone (SKIN_ONLY=1): no garments, no export.
        return

    # Width and depth of the trunk at chest and waist height (before the skin under the clothes
    # is removed); the arms hang beside it, so only the middle is measured.
    top = max(v.co.z for v in body.data.vertices)
    for label, frac in (("chest", 0.72), ("waist", 0.61)):
        z = top * frac
        trunk = [v.co for v in body.data.vertices if abs(v.co.z - z) < 0.01 and abs(v.co.x) < 0.17]
        if trunk:
            print("make_player: build %s %s width %.3f m depth %.3f m" % (
                BUILD, label, max(c.x for c in trunk) - min(c.x for c in trunk), max(c.y for c in trunk) - min(c.y for c in trunk)))
    feet, head_points = prepare_body(body, rig)
    def anatomy_of(obj, bm):
        a = Anatomy(obj, rig, bm)
        a.waist = top * BELT_CENTRE
        return a

    chest_z = top * 0.72

    def dominant(v, a):
        best, weight = "", 0.0
        for group, w in v[a.deform].items():
            name = a.bone_of_group.get(group)
            if name and w > weight:
                best, weight = name, w
        return best

    def jersey_looseness(v, a, hem):
        """A uniform top (docs/13 S11-2, A from photographs): 12-18 cm more round the chest
        than the body, roomier below the chest before it is tucked in, close at the collar,
        wide sleeves flaring to the hem above the elbow, a few soft folds where it is tucked."""
        bone = dominant(v, a)
        if bone.startswith("upperarm_"):
            t = min(max(a.along(bone, v.co) / SLEEVE_HEM, 0.0), 1.0)
            return 0.016 + 0.018 * t
        lift = 0.018
        if v.co.z < chest_z:
            lift += 0.004
        if v.co.y > 0.0:
            lift += 0.003
        above_belt = v.co.z - (a.waist + BELT_HALF)
        if above_belt < 0.15:
            lift = 0.012 + (lift - 0.012) * max(above_belt, 0.0) / 0.15
            lift += 0.003 * math.sin(above_belt * 2.0 * math.pi / 0.05)
        neck = a.outside_neckline(v.co)
        if neck < 0.04:
            lift = 0.010 + (lift - 0.010) * neck / 0.04
        return lift

    def pants_looseness(v, a, hem):
        """Baseball trousers: roomy at the seat and thighs, narrowing below the knee to the
        hem, close at the belt, gathered a little over the calf."""
        bone = dominant(v, a)
        if bone.startswith("thigh_"):
            t = min(max(a.along(bone, v.co), 0.0), 1.0)
            seat = 0.003 if v.co.y > 0.0 and t < 0.35 else 0.0
            return 0.022 - 0.006 * t + seat
        if bone.startswith("calf_"):
            t = min(max(a.along(bone, v.co) / PANTS_HEM, 0.0), 1.0)
            return 0.018 - 0.010 * t + 0.003 * math.sin(t * 2.0 * math.pi * 4.0)
        if abs(v.co.z - a.waist) < BELT_HALF + 0.01:
            return 0.010
        return 0.019 + (0.004 if v.co.y > 0.0 else 0.0)

    def snap_neckline(hem, a):
        """Puts the jersey's neckline exactly on its curve (docs/13 S11-7): the V's straight
        sides in front, a circle round the neck elsewhere. Returns how far the edge was from
        the curve before, at most."""
        worst = 0.0
        axis = a.collar_n
        for v in hem:
            rel = v.co - a.collar_co
            up = rel.dot(axis)
            if up < -V_DEPTH - 0.03 or up > 0.06:
                continue
            if v.co.y < a.collar_co.y and v.co.z < a.collar_co.z + 0.005:
                # The V: move across to its side line at this height.
                want = a.v_half_width(v.co.z)
                dx = abs(v.co.x - a.collar_co.x)
                if want > 0.0 and abs(dx - want) < 0.03:
                    worst = max(worst, abs(dx - want))
                    v.co.x = a.collar_co.x + math.copysign(want, v.co.x - a.collar_co.x)
                continue
            radial = rel - axis * up
            if radial.length > 1e-4 and abs(radial.length - (Anatomy.NECK_RADIUS + 0.01)) < 0.03:
                worst = max(worst, abs(radial.length - (Anatomy.NECK_RADIUS + 0.01)))
                v.co = a.collar_co + axis * up + radial.normalized() * (Anatomy.NECK_RADIUS + 0.01)
        print("make_player: neckline snapped (edge was up to %.1f mm off the curve)" % (worst * 1000.0))

    jersey = make_garment(body, "Jersey", (JERSEY,), jersey_looseness, [JERSEY], anatomy_of, snap_neckline)
    pants = make_garment(body, "Pants", (PANTS, BELT), pants_looseness, [PANTS, BELT], anatomy_of)
    # How far the jersey stands off the body at chest height (docs/13 S11-2: 2 to 5 cm).
    depsgraph = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(body, depsgraph)
    gaps = [tree.find_nearest(v.co)[3] for v in jersey.data.vertices if abs(v.co.z - chest_z) < 0.02 and abs(v.co.x) < 0.17]
    if gaps:
        print("make_player: build %s jersey off the chest %.1f cm on average" % (BUILD, 100.0 * sum(gaps) / len(gaps)))
    # Folds (docs/13 S11-2): the jersey hangs from the shoulders and is tucked in at the belt;
    # the trousers hang from the belt and are held at the hem over the socks.
    jz = [v.co.z for v in jersey.data.vertices]
    pz = [v.co.z for v in pants.data.vertices]
    j_top, j_bottom, p_top, p_bottom = max(jz), min(jz), max(pz), min(pz)
    # (NO_FOLDS=1 skips this, for a quick look at the shapes.)
    if not os.environ.get("NO_FOLDS"):
        bake_folds(jersey, body, stem + "_jersey_folds.png",
                   lambda co: co.z > j_top - 0.1 or co.z < j_bottom + 0.035)
        bake_folds(pants, body, stem + "_pants_folds.png",
                   lambda co: co.z > p_top - 0.05 or co.z < p_bottom + 0.03, size=1024)
    # The gear is fitted to the body before the covered skin is removed (tools/blender/gear.py).
    gear.material = material
    helmet, flaps = gear.batting_helmet(body, marks, rig)
    catcher_head = gear.catcher_helmet(body, marks, rig)
    catcher_gear = [gear.chest_protector(jersey, rig, marks), gear.shin_guards(pants, body, rig), *catcher_head]
    umpire = gear.umpire_mask(body, marks, rig)
    strip_body(body)
    trim_hair(hair, head_points)
    optional = [*catcher_gear, umpire, *flaps, helmet]
    parts = [body, jersey, pants, make_shoes(feet, rig), *face_parts, *hair,
             make_cap(head_points, rig), make_cap_button(head_points, rig), *optional]

    for old, new in BONE_NAMES.items():
        if old in rig.data.bones:
            rig.data.bones[old].name = new
    body.name = body.data.name = "Body"
    rig.name = rig.data.name = "PlayerRig"

    height = max(v.co.z for v in body.data.vertices)
    print("make_player: height %.3f m, %d bones, faces: %s" % (
        height, len(rig.data.bones), {p.name: len(p.data.polygons) for p in parts}))

    for obj in bpy.data.objects:
        obj.select_set(obj in (rig, *parts))
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', use_selection=True, export_apply=False,
                              export_yup=True, export_skins=True, export_animations=False, export_morph=True,
                              export_morph_normal=True)
    print("make_player: wrote", OUT_GLB)
    if PREVIEW:
        # The preview shows a catcher in his gear, then close-ups of the catcher's helmet, the
        # batting helmet with its left flap and the umpire's mask over the cap.
        catcher = {o.name for o in catcher_gear}
        looks = [("", catcher, False, height * 0.5), ("_catcher_head", catcher, True, height - 0.12),
                 ("_chest", catcher, True, height * 0.7), ("_shins", catcher, True, height * 0.25),
                 ("_helmet", {"Helmet", "HelmetFlapLeft"}, True, height - 0.12),
                 ("_umpire", {"Mask", "Cap", "CapButton"}, True, height - 0.12)]
        for suffix, shown, close, z in looks:
            for obj in [*optional, *parts]:
                if obj in optional or obj.name in ("Cap", "CapButton"):
                    obj.hide_render = obj.name not in shown
            out = PREVIEW if not suffix else os.path.splitext(PREVIEW)[0] + suffix + ".png"
            render_preview(out, z, close)
            print("make_player: preview", out)


main()
