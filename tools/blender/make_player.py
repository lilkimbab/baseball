"""Builds the base player model and exports it as glTF for the game.

Run through ./dev model, or directly:
    blender -b --python tools/blender/make_player.py -- <out.glb> [preview.png]

A human body is generated with MPFB (MakeHuman) and rigged. The uniform is cut from the body
along straight hem lines, lifted off the skin and smoothed into separate jersey and pants
meshes with front/back UVs for lettering and stripes. Shoes are convex shells around the
feet. A cap and a batting helmet are added, and bones are renamed to the names the game uses
(Godot's humanoid profile). The output of MakeHuman/MPFB is CC0.
"""
import json
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
import fold_maps  # noqa: E402  (softening of the baked fold maps)
import anthropometry  # noqa: E402  (the body's measurements, against published tables)
import kit  # noqa: E402  (the cap, the shoes and the belt buckle)
import officials  # noqa: E402  (the umpires' mask, polo collar and ball bags)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_GLB = ARGS[0] if ARGS else "player_base.glb"
PREVIEW = ARGS[1] if len(ARGS) > 1 and ARGS[1] != "-" else None
BUILD = ARGS[2] if len(ARGS) > 2 else "standard"

# Body shape: a professional ballplayer of about 183 cm and 88 kg (docs/09, section 4). Every
# setting below was chosen by measuring the body it gives (tools/blender/anthropometry.py, which
# prints the table on every build) against the US Army's survey of men (ANSUR II) and, for
# girths, the upper part of its range: a ballplayer is broader in the shoulders and thicker in
# the neck, forearms and legs than a soldier of the same height.
MACRO = {"gender": 1.0, "age": 0.5, "muscle": 1.0, "weight": 0.62, "height": 0.6, "proportions": 0.85}
SHAPE = {
    # Arms: MakeHuman's come out at 29.9% of height from shoulder to wrist against 31.6%.
    "measure-upperarm-length-incr": 0.25, "measure-lowerarm-length-incr": 0.25,
    # Head. MakeHuman's is the right size for an average man (23.6 cm chin to crown at 1.76 m,
    # 58 cm round) but long front to back and narrow (21.4 by 15.1 cm; Korean men average
    # about 19 by 15.7). It is shortened front to back, widened a little, and made a little
    # less tall: a head does not grow with the body, and these are tall men. About 7.7
    # head-heights to the body. (An earlier version enlarged the head by 7% from a wrong
    # measurement and came out 6.9 heads tall with the chin 4 cm above the shoulders.)
    "head-scale-vert-decr": 0.18, "head-scale-horiz-incr": 0.15,
    "head-back-scale-depth-decr": 0.5, "head-scale-depth-decr": 0.3,
    # A man's face: a wider, firmer jaw and chin, cheekbones, a brow ridge.
    # Without these the default face reads as a woman's at close range.
    "chin-width-incr": 0.3, "chin-bones-incr": 0.35, "l-cheek-bones-incr": 0.25, "r-cheek-bones-incr": 0.25,
    "eyebrows-trans-forward": 0.35, "forehead-nubian-incr": 0.2, "head-square": 0.25,
    # Neck. With this much muscle the shoulders rise to 3 cm under the chin; a man's chin is
    # about 8 cm above the tops of his shoulders. Longer, and as thick as an athlete's (41 cm
    # at 1.83 m).
    "neck-scale-vert-incr": 0.65, "measure-neck-circ-incr": 0.7,
    # Shoulders and back: the breadth is the deltoids and the back's muscle (latissimus), not
    # the "V shape" key, which moves the shoulder joints apart past the tables.
    "l-upperarm-shoulder-muscle-incr": 0.3, "r-upperarm-shoulder-muscle-incr": 0.3,
    "torso-muscle-dorsi-incr": 0.5, "torso-muscle-pectoral-incr": 0.3, "torso-scale-depth-incr": 0.2,
    # The trunk below the ribs: MakeHuman's muscular man has a dancer's waist (77 cm) and a
    # small seat. A ballplayer's power is in his hips and legs: waist about 86 cm, seat 98 cm.
    "measure-waist-circ-incr": 0.7, "buttocks-volume-incr": 0.25, "measure-hips-circ-incr": 0.15,
    # Forearms and wrists (25 and 15 cm round on MakeHuman's man; 30 and 17.5 on a real one).
    "l-lowerarm-muscle-incr": 0.4, "r-lowerarm-muscle-incr": 0.4,
    "l-lowerarm-fat-incr": 0.3, "r-lowerarm-fat-incr": 0.3, "measure-wrist-circ-incr": 0.2,
    # Knees, calves and ankles likewise; feet to 27.5 cm.
    "measure-knee-circ-incr": 0.2, "measure-calf-circ-incr": 0.15, "measure-ankle-circ-incr": 0.3,
    "l-foot-scale-incr": 0.2, "r-foot-scale-incr": 0.2,
}
# Faces that differ from player to player: shape keys the game sets per player (morph
# targets in the model). Each name is one key; pairs give both directions.
FACE_KEYS = [
    "head-oval", "head-round", "head-square", "head-triangular",
    "chin-width-incr", "chin-width-decr", "chin-prominent-incr", "chin-prominent-decr",
    "nose-scale-horiz-incr", "nose-scale-horiz-decr", "nose-scale-vert-incr", "nose-hump-incr",
    "mouth-scale-horiz-incr", "mouth-scale-horiz-decr",
    "l-cheek-bones-incr", "r-cheek-bones-incr",
    # (Queue 2-1, 2026-11-23: no two players with one face.) The jaw, lips, nose, forehead,
    # head's age and fullness, the neck.
    "chin-height-incr", "chin-height-decr", "chin-jaw-drop-incr", "chin-bones-incr",
    "mouth-lowerlip-volume-incr", "mouth-lowerlip-volume-decr", "mouth-upperlip-volume-incr", "mouth-upperlip-volume-decr",
    "nose-point-width-incr", "nose-point-width-decr", "nose-base-up", "nose-base-down", "nose-flaring-incr",
    "forehead-scale-vert-incr", "forehead-scale-vert-decr",
    "head-age-incr", "head-fat-incr", "head-fat-decr", "neck-scale-horiz-incr",
]
# The same, made of a left and a right target together (one key for both sides), and those
# around the eyes and brows: the eyes, brows and lashes are separate meshes fitted to the face,
# and they are given each key too, from the same fitting weights (face_keys_to_parts).
PAIRED_KEYS = {
    "eyes-scale-incr": ["l-eye-scale-incr", "r-eye-scale-incr"], "eyes-scale-decr": ["l-eye-scale-decr", "r-eye-scale-decr"],
    "eyes-trans-in": ["l-eye-trans-in", "r-eye-trans-in"], "eyes-trans-out": ["l-eye-trans-out", "r-eye-trans-out"],
    "eyes-trans-up": ["l-eye-trans-up", "r-eye-trans-up"], "eyes-trans-down": ["l-eye-trans-down", "r-eye-trans-down"],
    "eyes-corner-up": ["l-eye-corner1-up", "r-eye-corner1-up"], "eyes-corner-down": ["l-eye-corner1-down", "r-eye-corner1-down"],
    "eyes-fold-down": ["l-eye-eyefold-down", "r-eye-eyefold-down"], "eyes-bag-incr": ["l-eye-bag-incr", "r-eye-bag-incr"],
    "eyes-height-decr": ["l-eye-height1-decr", "r-eye-height1-decr"],
    "cheeks-volume-incr": ["l-cheek-volume-incr", "r-cheek-volume-incr"], "cheeks-volume-decr": ["l-cheek-volume-decr", "r-cheek-volume-decr"],
    "ears-scale-incr": ["l-ear-scale-incr", "r-ear-scale-incr"], "ears-scale-decr": ["l-ear-scale-decr", "r-ear-scale-decr"],
    "ears-flap-incr": ["l-ear-flap-incr", "r-ear-flap-incr"],
    "eyebrows-angle-up": ["eyebrows-angle-up"], "eyebrows-angle-down": ["eyebrows-angle-down"],
    "eyebrows-trans-up": ["eyebrows-trans-up"], "eyebrows-trans-down": ["eyebrows-trans-down"],
}
RACE = {"asian": 1.0, "caucasian": 0.0, "african": 0.0}
# Builds: MPFB weight and muscle for a lean, standard, solid and heavy player
# of the same height. Weight rises with muscle first (athletes), then with mass. The trunk's
# width and depth at chest and waist are printed for the build checks.
BUILDS = {
    "lean": {"muscle": 0.92, "weight": 0.5},
    "standard": {"muscle": 1.0, "weight": 0.62},
    "solid": {"muscle": 0.95, "weight": 0.72},
    "heavy": {"muscle": 0.75, "weight": 1.0},
}
# Settings a build adds to SHAPE. A heavier man carries it on his trunk: with MakeHuman's
# muscle at full and its weight high, the arms came out a bodybuilder's (48 cm round) on a
# 86 cm waist. Weights at 1.83 m: lean 80 kg, standard 89, solid 96, heavy 105.
BUILD_SHAPE = {
    "lean": {"measure-waist-circ-incr": 0.5},
    "solid": {"measure-waist-circ-incr": 0.9},
    "heavy": {"measure-waist-circ-incr": 1.0, "stomach-pregnant-incr": 0.2},
}

# Hair: MakeHuman's four short styles (CC0, from MPFB's system assets). Every
# model carries all four; the game shows one per player. Hair under the cap is cut away, so
# only the sides, back and sideburns show below it. Textures are scaled down to this size.
HAIR_STYLES = ["short01", "short02", "short03", "short04"]
HAIR_TEXTURE = 512
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# Where the garments end, as a fraction along the limb (0 = upper joint, 1 = lower joint).
# Sleeves end at the middle of the biceps; the trousers reach the tops of the shoes.
SLEEVE_HEM = 0.66
PANTS_HEM = 0.965
# A baseball belt is 1.5 in (38 mm) wide.
BELT_HALF = 0.019
# Centre of the belt as a fraction of standing height. Baseball trousers are worn on the hips,
# with the top of the belt at about the top of the hip bones (59% of height), not at the
# narrowest part of the waist (62%).
BELT_CENTRE = 0.575
# How far skin continues under a hem before it is removed, so no gap shows.
TUCK = 0.05

SKIN, HANDS, JERSEY, BELT, PANTS, SOCKS, SHOES, UNDERSHIRT = range(8)
# The jersey's neckline: a V in front, from the sides of the neck down to
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
    "Soles": (0.9, 0.9, 0.9), "Laces": (0.92, 0.92, 0.92), "Buckle": (0.7, 0.7, 0.72), "Piping": (0.10, 0.15, 0.35),
    "MaskPads": (0.55, 0.38, 0.22),
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
# (path, MakeHuman's kind, the part's name in the model). Four brows a man might have — thick
# and full, straight, medium, a full arch — of which the game shows one per player; the thin
# painted-looking arch (eyebrow001) is gone. (The fuller eye model's iris did not take the
# game's eye texture: the eyes came out blue-white.)
FACE_ASSETS = [("eyes/low-poly/low-poly.mhclo", "Eyes", "Eyes"),
               ("eyebrows/eyebrow009/eyebrow009.mhclo", "Eyebrows", "Eyebrows"),
               ("eyebrows/eyebrow004/eyebrow004.mhclo", "Eyebrows", "Eyebrows2"),
               ("eyebrows/eyebrow012/eyebrow012.mhclo", "Eyebrows", "Eyebrows3"),
               ("eyebrows/eyebrow008/eyebrow008.mhclo", "Eyebrows", "Eyebrows4"),
               ("eyelashes/eyelashes01/eyelashes01.mhclo", "Eyelashes", "Eyelashes")]


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
    for path, kind, name in FACE_ASSETS:
        full = os.path.join(data, path)
        if not os.path.exists(full):
            continue
        before = set(bpy.data.objects)
        HumanService.add_mhclo_asset(full, body, asset_type=kind, subdiv_levels=0, material_type="GAMEENGINE")
        for obj in set(bpy.data.objects) - before:
            obj.name = obj.data.name = name
            obj["mhclo_path"] = full
            extras.append(obj)
    print("make_player: skin texture and", [o.name for o in extras])
    return extras


def paired_keys(body):
    """Loads PAIRED_KEYS: each its targets at full weight, mixed into one key (weight 0)."""
    for name, targets in PAIRED_KEYS.items():
        loaded = []
        for target in targets:
            key = "pair_part_" + target
            TargetService.load_target(body, TargetService.target_full_path(target), weight=1.0, name=key)
            loaded.append(key)
        blocks = body.data.shape_keys.key_blocks
        for kb in blocks:
            if kb.name not in loaded and kb != body.data.shape_keys.reference_key:
                kb.value = 0.0
        mixed = body.shape_key_add(name="face_" + name, from_mix=True)
        mixed.value = 0.0
        for key in loaded:
            body.shape_key_remove(body.data.shape_keys.key_blocks[key])


def face_keys_to_parts(body, parts):
    """Gives the eyes, brows and lashes each face key of the body: MakeHuman fits each of their
    vertices to three of the body's with fixed weights (their .mhclo), so a key moves them by
    the same mix of the body's movement under it. Without this the eyes stayed where a default
    face has them when the face around them changed."""
    from bl_ext.user_default.mpfb.entities.clothes.mhclo import Mhclo
    keys = [kb for kb in body.data.shape_keys.key_blocks if kb.name.startswith("face_")]
    basis = body.data.shape_keys.reference_key.data
    for part in parts:
        path = part.get("mhclo_path")
        if not path:
            continue
        mhclo = Mhclo()
        mhclo.load(path)
        rest = [v.co.copy() for v in part.data.vertices]
        if part.data.shape_keys is None:
            part.shape_key_add(name="Basis", from_mix=False)
        for kb in keys:
            moved = part.shape_key_add(name=kb.name, from_mix=False)
            for j, co in enumerate(rest):
                info = mhclo.verts.get(j)
                if info is None:
                    moved.data[j].co = co
                    continue
                shift = Vector((0.0, 0.0, 0.0))
                for v, w in zip(info["verts"], info["weights"]):
                    if v < len(basis):
                        shift += w * (kb.data[v].co - basis[v].co)
                moved.data[j].co = co + shift
            moved.value = 0.0
    print("make_player: face keys", len(keys), "on", [p.name for p in parts])


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


def limb_coordinates(body, rig):
    """Per vertex, where on an arm or hand it is: (along, cos, sin) and (weight, across, 0),
    packed into 0..1 for baking. `along` runs -1 at the shoulder, 0 at the elbow, 1 at the
    wrist and on to 2 at the knuckles (stored as (along + 1) / 3); the angle round the arm as
    in the game's match/skin_veins.gd (as cosine and sine, which interpolate across faces where an angle would
    jump); `across` is the distance across the back of the hand; weight is how much the vertex
    is arm or the back of a hand (0 elsewhere)."""
    bones = rig.data.bones
    groups = {g.index: g.name for g in body.vertex_groups}
    limb = [(0.0, 0.5, 0.5)] * len(body.data.vertices)
    extra = [(0.0, 0.5, 0.0)] * len(body.data.vertices)
    pack = lambda t: (t + 1.0) / 3.0
    for side, sign in (("l", 1.0), ("r", -1.0)):
        shoulder = bones["upperarm_" + side].head_local
        elbow = bones["lowerarm_" + side].head_local
        wrist = bones["lowerarm_" + side].tail_local
        knuckle = bones["middle_01_" + side].head_local
        across = bones["index_01_" + side].head_local - bones["pinky_01_" + side].head_local
        hand_axis = knuckle - wrist
        back_of_hand = hand_axis.cross(across).normalized() * -sign
        across_dir = (across - hand_axis * (across.dot(hand_axis) / hand_axis.length_squared)).normalized()
        middle = (bones["index_01_" + side].head_local + bones["pinky_01_" + side].head_local) * 0.5

        def angle_round(co, start, end):
            """The angle round the bone start-end at a point (0 in front, + outward)."""
            d = (end - start).normalized()
            r = co - start
            r -= d * r.dot(d)
            front = Vector((0.0, -1.0, 0.0))
            front = (front - d * front.dot(d)).normalized()
            out = Vector((sign, 0.0, 0.0))
            out = (out - d * out.dot(d)).normalized()
            return math.atan2(r.dot(out), r.dot(front))

        fore_axis = wrist - elbow
        upper_axis = elbow - shoulder
        for v in body.data.vertices:
            upper = fore = hand = 0.0
            for e in v.groups:
                name = groups.get(e.group, "")
                if not name.endswith("_" + side):
                    continue
                if name.startswith("upperarm"):
                    upper += e.weight
                elif name.startswith("lowerarm"):
                    fore += e.weight
                elif name == "hand_" + side:
                    hand += e.weight
            total = upper + fore + hand
            if total < 0.3:
                continue
            if hand > fore and hand > upper:
                t = 1.0 + min(max((v.co - wrist).dot(hand_axis) / hand_axis.length_squared, 0.0), 1.0)
                facing = _smooth(0.1, 0.5, v.normal.dot(back_of_hand))
                limb[v.index] = (pack(t), 0.5, 0.5)
                extra[v.index] = (min(total, 1.0) * facing, (v.co - middle).dot(across_dir) * 5.0 + 0.5, 0.0)
                continue
            # Past the elbow along the forearm (m, negative above it): one coordinate down the
            # whole arm, and the angle taken round the upper arm above the elbow, round the
            # forearm below it and a blend of the two across it (the two bones are not in
            # line, and a jump there would show as a crease in everything drawn from this).
            past = (v.co - elbow).dot(fore_axis.normalized())
            above = (elbow - v.co).dot(upper_axis.normalized())
            if past >= 0.0:
                t = min(past / fore_axis.length, 1.0)
            else:
                t = -min(max(above, 0.0) / upper_axis.length, 1.0)
            w = _smooth(-0.05, 0.05, past)
            a_fore, a_upper = angle_round(v.co, elbow, wrist), angle_round(v.co, shoulder, elbow)
            c = math.cos(a_fore) * w + math.cos(a_upper) * (1.0 - w)
            sn = math.sin(a_fore) * w + math.sin(a_upper) * (1.0 - w)
            norm = math.hypot(c, sn) or 1.0
            limb[v.index] = (pack(t), c / norm * 0.5 + 0.5, sn / norm * 0.5 + 0.5)
            extra[v.index] = (min(total, 1.0), 0.5, 0.0)
    # Points next to the arm that are not of it (the fingers, the chest at the shoulder) take
    # their neighbour's place along the arm, with no weight: across the faces between them
    # the place then stays where it is while the weight fades, instead of running from the
    # knuckles back to the shoulder (which drew bits of sleeve and vein on the fingers).
    for _ in range(2):
        taken = {}
        for e in body.data.edges:
            a, b = e.vertices
            for inside, outside in ((a, b), (b, a)):
                if extra[inside][0] > 0.0 and extra[outside][0] <= 0.0 and outside not in taken:
                    taken[outside] = limb[inside]
        for index, coords in taken.items():
            if extra[index][0] <= 0.0:
                limb[index] = coords
                extra[index] = (1e-6, extra[index][1], 0.0)
    extra = [(0.0 if w <= 1e-5 else w, across, z) for w, across, z in extra]
    return limb, extra


def store_limb_coordinates(body, rig):
    """Keeps the arm coordinates in the model for the game's skin shader, which draws the
    veins and tendons of the arms and hands from them, as fine as the screen is and different
    on every player (match/skin.gdshader, match/skin_veins.gd): in the vertex colour (along,
    cos, sin, weight) and in a second UV map (across the back of the hand, 1 on a hand)."""
    limb, extra = limb_coordinates(body, rig)
    mesh = body.data
    attr = mesh.color_attributes.get("Limb") or mesh.color_attributes.new("Limb", 'FLOAT_COLOR', 'POINT')
    for v in mesh.vertices:
        attr.data[v.index].color = (*limb[v.index], extra[v.index][0])
    mesh.color_attributes.active_color = attr
    mesh.color_attributes.render_color_index = list(mesh.color_attributes).index(attr)
    layer = mesh.uv_layers.get("Limb") or mesh.uv_layers.new(name="Limb")
    for loop in mesh.loops:
        i = loop.vertex_index
        layer.data[loop.index].uv = (extra[i][1], 1.0 if limb[i][0] > 2.0 / 3.0 + 1e-4 else 0.0)


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
    """Bakes the maps the game's skin shader reads (skin that reads as a
    person's, not a doll's), onto the body's own UVs:
      detail (per build): R ambient occlusion within 7 cm (the creases of the
        eyes, nostrils, mouth and ears, between the fingers; not the shadow of an arm, which
        moves) times the hollows of the surface (between the muscles of the shoulders, arms
        and neck, the collarbones, the knuckles), G roughness (the forehead and nose shine,
        the lips more), B where the beard grows (for stubble), A 1 - half of where the hair
        grows on the scalp (cropped hair, drawn on the skin);
      relief (the same for every build): the painted skin's fine detail (creases, grain,
        knuckles) as the x and y of a normal map, from the texture's own light and dark (the
        high-pass of its brightness taken as height); and in its third channel how
        fine-grained the skin is there.
    (The veins and tendons of the arms are not baked: the arms' part of the texture is too
    coarse for anything a few millimetres wide. The game's shader draws them from the arm
    coordinates kept in the model, see store_limb_coordinates.)
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
    # Cropped hair: the scalp down to the hairline, the sideburns and the nape.
    scalp_attr = body.data.color_attributes.new("Scalp", 'FLOAT_COLOR', 'POINT')
    for v in verts:
        w = scalp_w[v.index] * (1.0 - ears_w[v.index])
        if v.co.y > ear.y + 0.01:
            # The nape: cut in a curve, lowest in the middle and rounding up behind the ears
            # (MakeHuman's own outline there is a stepped block).
            line = ear.z - 0.05 + 0.5 * max(abs(v.co.x) - 0.03, 0.0)
            w *= _smooth(line - 0.01, line + 0.01, v.co.z)
        scalp_attr.data[v.index].color = (w, w, w, 1.0)
    # How fine-grained the skin is, by part: the face keeps all of its painted grain and its
    # pores; the hands most of it; on the arms the same grain is twice the size (their part of
    # the texture is coarser) and reads as goose flesh, so little of it is kept there.
    fine_attr = body.data.color_attributes.new("Fine", 'FLOAT_COLOR', 'POINT')
    for v in verts:
        t, weight = limb[v.index][0] * 3.0 - 1.0, limb_extra[v.index][0]
        on_head = v.co.z > chin.z - 0.03 and v.co.y < ear.y + 0.03
        fine = 1.0 if on_head else (0.3 if weight <= 0.0 else (0.6 if t >= 1.0 else 0.16))
        fine_attr.data[v.index].color = (fine, fine, fine, 1.0)

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
            ('SCALP', 'EMIT', 1, "Scalp", size), ('FINE', 'EMIT', 1, "Fine", relief_size)):
        image = bpy.data.images.new("Skin" + name, bake_size, bake_size, alpha=False, float_buffer=True)
        image.colorspace_settings.name = "Non-Color"
        target.image = image
        attribute.attribute_name = attribute_name
        scene.cycles.samples = samples
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
    for name in ("SkinDetail", "Scalp", "Fine"):
        body.data.color_attributes.remove(body.data.color_attributes[name])

    ao, emitted = images['AO'], images['EMIT']
    detail = np.ones((size, size, 4), dtype=np.float32)
    detail[..., 0] = ao[..., 0] * np.where(emitted[..., 1] > 0.1, emitted[..., 0], 1.0)
    detail[..., 1] = emitted[..., 1]
    detail[..., 2] = emitted[..., 2]
    # Where the hair grows on the scalp. Stored as 1 - half of it: an image importer fills
    # fully clear pixels with their neighbours' colour.
    # (Softened: the hairline follows the mesh's faces otherwise, in straight steps.)
    detail[..., 3] = 1.0 - 0.5 * _box(_box(images['SCALP'][..., 0], 5), 5)
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
    fine = images['FINE'][..., 0] if n == relief_size else np.full((n, n), 0.3, dtype=np.float32)
    fine = _box(fine.astype(np.float32), 4)
    nx, ny = np.clip(-gx * k * fine, -0.6, 0.6), np.clip(-gy * k * fine, -0.6, 0.6)
    relief = np.ones((n, n, 4), dtype=np.float32)
    relief[..., 0] = nx * 0.5 + 0.5
    relief[..., 1] = ny * 0.5 + 0.5
    # (The game rebuilds the normal's third part; this channel says how fine the skin is.)
    relief[..., 2] = fine
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
        self._normals = self.neck_normals()

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

    NECK_RADIUS = 0.08
    NECK_SIDES = 20

    def neck_normals(self):
        """Outward directions of the sides of the neck opening (a many-sided prism round the
        neck's axis: its outline can then be cut exactly, plane by plane)."""
        side = self.collar_n.cross(Vector((0.0, 1.0, 0.0))).normalized()
        fore = side.cross(self.collar_n).normalized()
        return [side * math.cos(2.0 * math.pi * k / self.NECK_SIDES) + fore * math.sin(2.0 * math.pi * k / self.NECK_SIDES)
                for k in range(self.NECK_SIDES)]

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
        prism round the neck, so the tops of the shoulders stay covered."""
        rel = point - self.collar_co
        up = rel.dot(self.collar_n)
        radial = max(rel.dot(n) for n in self._normals)
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
            # The sock goes on down into the shoe: the ankle above the shoe's collar is sock.
            return (SOCKS, 0.0) if c.z > kit.SOCK_LINE else (SHOES, 1.0)
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
    # The neck opening, cut exactly along its outline: each side of the prism round the neck
    # (only the faces that side passes through), then the plane across the base of the neck.
    for normal in anatomy.neck_normals() + [None]:
        bm.faces.ensure_lookup_table()
        chosen = []
        for f in bm.faces:
            rel = f.calc_center_median() - top
            if rel.length > 0.16 or anatomy.bone(f) not in torso:
                continue
            if normal is not None:
                flat = rel - anatomy.collar_n * rel.dot(anatomy.collar_n)
                if flat.length < 1e-4 or flat.normalized().dot(normal) < math.cos(2.6 * math.pi / Anatomy.NECK_SIDES):
                    continue
            chosen.append(f)
        geom = set(chosen)
        for f in chosen:
            geom.update(f.edges)
            geom.update(f.verts)
        if normal is None:
            bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-5, plane_co=top, plane_no=anatomy.collar_n)
        else:
            bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-5, plane_co=top + normal * Anatomy.NECK_RADIUS, plane_no=normal)
    for side in ("l", "r"):
        cut(bm, anatomy, {"upperarm_" + side}, *anatomy.plane("upperarm_" + side, SLEEVE_HEM))
        cut(bm, anatomy, {"calf_" + side}, *anatomy.plane("calf_" + side, PANTS_HEM))

    bm.faces.ensure_lookup_table()
    region = bm.faces.layers.int.new("region")
    depth = bm.faces.layers.float.new("depth")
    sock = bm.faces.layers.int.new("sock")
    feet = {"l": [], "r": []}
    for face in bm.faces:
        face.smooth = True
        face[region], face[depth] = anatomy.region(face)
        face[sock] = 1 if anatomy.bone(face).startswith("calf_") else 0
        if anatomy.bone(face).startswith(("foot_", "ball_")):
            feet["l" if face.calc_center_median().x > 0.0 else "r"].extend(v.co.copy() for v in face.verts)
    head = [v.co.copy() for v in bm.verts
            if any(anatomy.bone_of_group.get(g) == "head" and w > 0.6 for g, w in v[deform].items())]
    bm.to_mesh(body.data)
    bm.free()
    return feet, head


def make_garment(body, name, regions, looseness, slots, anatomy_of, snap_neckline=None, drape=None):
    """Copies the faces of some regions into a new mesh, subdivides it once for a smoother
    outline, lifts every point off the skin by how loose the garment is there (looseness:
    vertex -> metres), smooths away the anatomy underneath and unwraps it
    front/back. The copied skin weights make it move with the body."""
    obj = body.copy()
    obj.data = body.data.copy()
    obj.name = obj.data.name = name
    bpy.context.scene.collection.objects.link(obj)
    # Clothes do not need the face keys.
    obj.shape_key_clear()
    for attr in list(obj.data.color_attributes):
        obj.data.color_attributes.remove(attr)

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
    skin = {v: v.co.copy() for v in bm.verts}
    for v in bm.verts:
        v.co += v.normal * lifts[v]
    if drape is not None:
        drape(bm, anatomy, skin)
    inner = [v for v in bm.verts if v not in hem]
    for _ in range(6):
        bmesh.ops.smooth_vert(bm, verts=inner, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    if snap_neckline is not None:
        snap_neckline(hem, anatomy)
    if drape is not None:
        # Again after the smoothing (which leaves the hems where they were and pulls the
        # rest in a little: the hems came out ragged).
        drape(bm, anatomy, skin)
    # Every hem a clean line: each point of an edge moved toward the middle of its two
    # neighbours along the edge.
    for _ in range(3):
        moved = {}
        for v in hem:
            beside = [e.other_vert(v).co for e in v.link_edges if e.is_boundary]
            if len(beside) == 2:
                moved[v] = v.co * 0.5 + (beside[0] + beside[1]) * 0.25
        for v, co in moved.items():
            v.co = co
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
    wrap_uvs(bm, anatomy_of(obj, bm))
    # Slots first, then the mesh: clearing materials afterwards would reset the indices.
    obj.data.materials.clear()
    for slot in slots:
        obj.data.materials.append(material({JERSEY: "Jersey", PANTS: "Pants", BELT: "Belt"}[slot]))
    bm.to_mesh(obj.data)
    bm.free()
    print("make_player: %s %d faces, x %.2f..%.2f m, z %.2f..%.2f m" % (name, len(obj.data.polygons), x0, x1, z0, z1))
    return obj


def _majorant(values):
    """The least concave curve over a row of numbers: a string pulled tight over their tops.
    Cloth hangs like that between the widest places of the body under it."""
    hull = []
    for i, y in enumerate(values):
        while len(hull) >= 2:
            (x1, y1), (x2, y2) = hull[-2], hull[-1]
            if (y2 - y1) * (i - x1) <= (y - y1) * (x2 - x1):
                hull.pop()
            else:
                break
        hull.append((i, y))
    out = list(values)
    for (x1, y1), (x2, y2) in zip(hull, hull[1:]):
        for i in range(x1, x2 + 1):
            out[i] = y1 + (y2 - y1) * (i - x1) / (x2 - x1)
    return out


def hang(verts, skin, start, end, ease, blend, sectors=12, slices=36, hold=1.0, limit=None, settle=None, rest=0.004):
    """Reshapes part of a garment (a trouser leg, a sleeve, the body of the jersey) from skin
    pushed out along its normals into cloth that hangs: round the axis start-end, at each
    place along it the cloth stands `ease(u)` off the widest the body is there, and between
    two wide places (thigh and calf, chest and belt) it runs straight instead of following
    the body in (`hold` of the way: 1 a taut straight line). `blend(u)` is how much of the new
    shape a point takes (0 leaves it as it was). u is 0 at start and 1 at end.
    `settle` is the way the cloth drops (a sleeve lies on the top of the arm and hangs clear
    under it): it rests `rest` off the body on the side it drops from, and all its ease
    gathers on the other."""
    axis = end - start
    length = axis.length
    d = axis / length
    ref = d.cross(Vector((0.0, 1.0, 0.0)))
    if ref.length < 0.2:
        ref = d.cross(Vector((1.0, 0.0, 0.0)))
    ref.normalize()
    other = d.cross(ref)
    coords = {}
    for v in verts:
        rel = skin[v] - start
        u = rel.dot(d) / length
        coords[v] = (u, Vector((rel.dot(ref), rel.dot(other))))
    us = [c[0] for c in coords.values()]
    lo, hi = min(us), max(us)
    span = max(hi - lo, 1e-6)
    index = lambda u: min(int((u - lo) / span * slices), slices - 1)
    # The middle of the body at each slice, then its reach in each direction from there.
    sums = [[Vector((0.0, 0.0)), 0] for _ in range(slices)]
    for u, q in coords.values():
        k = index(u)
        sums[k][0] = sums[k][0] + q
        sums[k][1] += 1
    centres = [(s[0] / s[1]) if s[1] else None for s in sums]
    known = [c for c in centres if c is not None]
    for k in range(slices):
        if centres[k] is None:
            centres[k] = known[0] if known else Vector((0.0, 0.0))
    for _ in range(4):
        centres = [(centres[max(k - 1, 0)] + centres[k] * 2.0 + centres[min(k + 1, slices - 1)]) * 0.25 for k in range(slices)]
    reach = [[0.0] * sectors for _ in range(slices)]
    for u, q in coords.values():
        k = index(u)
        r = q - centres[k]
        a = (math.atan2(r.y, r.x) / (2.0 * math.pi)) % 1.0
        sct = int(a * sectors) % sectors
        reach[k][sct] = max(reach[k][sct], r.length)
    for k in range(slices):
        got = [x for x in reach[k] if x > 0.0]
        fill = sum(got) / len(got) if got else 0.05
        row = [x if x > 0.0 else fill for x in reach[k]]
        # A cross-section without corners.
        for _ in range(2):
            row = [(row[(i - 1) % sectors] + 2.0 * row[i] + row[(i + 1) % sectors]) * 0.25 for i in range(sectors)]
        reach[k] = row
    drop = None
    if settle is not None:
        drop = Vector((settle.dot(ref), settle.dot(other)))
        drop = drop.normalized() if drop.length > 1e-6 else None
    shifts = [(drop * max(ease(lo + (k + 0.5) / slices * span) - rest, 0.0)) if drop is not None else Vector((0.0, 0.0))
              for k in range(slices)]
    for sct in range(sectors):
        column = [reach[k][sct] + ease(lo + (k + 0.5) / slices * span) for k in range(slices)]
        taut = _majorant(column)
        for k in range(slices):
            reach[k][sct] = column[k] + (taut[k] - column[k]) * hold
    for v in verts:
        u, q = coords[v]
        w = blend(u)
        if w <= 0.0:
            continue
        f = (u - lo) / span * slices - 0.5
        k0 = min(max(int(math.floor(f)), 0), slices - 1)
        k1 = min(k0 + 1, slices - 1)
        fk = min(max(f - k0, 0.0), 1.0)
        centre = centres[k0].lerp(centres[k1], fk)
        r = q - centre
        a = (math.atan2(r.y, r.x) / (2.0 * math.pi)) % 1.0 * sectors - 0.5
        s0 = int(math.floor(a)) % sectors
        s1 = (s0 + 1) % sectors
        fs = a - math.floor(a)
        radius = ((reach[k0][s0] * (1.0 - fs) + reach[k0][s1] * fs) * (1.0 - fk)
                  + (reach[k1][s0] * (1.0 - fs) + reach[k1][s1] * fs) * fk)
        if r.length < 1e-5:
            continue
        flat = centre + shifts[k0].lerp(shifts[k1], fk) + r.normalized() * radius
        target = start + d * (u * length) + ref * flat.x + other * flat.y
        if limit is not None:
            target = limit(target)
        v.co = v.co.lerp(target, w)


# Round each part of a garment, the arc length (m) a pinstripe fabric's stripes are counted in
#: the cloth's own radius about there, so stripes stay about 2.5 cm apart.
WRAP_RADIUS = {"leg": 0.085, "arm": 0.065, "trunk": 0.16}


def wrap_uvs(bm, anatomy):
    """A second UV map ("Wrap", UV2 in the game) in metres of cloth: u round the part (each leg
    from the waist down, the trunk, each sleeve), v along it. The game lays the knit and the
    trousers' pinstripes along it, so they run evenly round a leg. (On the front/back map the
    sides of the legs are squeezed and the stripes came out as thick dark curves.) The seams are
    where a garment has them: down the inside of each leg and between the legs, under each
    sleeve, down the front of the jersey (the placket)."""
    bones = anatomy.rig.data.bones
    wrap = bm.loops.layers.uv.new("Wrap")
    up = Vector((0.0, 0.0, 1.0))
    for face in bm.faces:
        bone = anatomy.bone(face)
        centre = face.calc_center_median()
        if bone.startswith(("thigh_", "calf_", "foot_")) or (bone in ("pelvis", "Root") and centre.z < anatomy.waist + 0.05):
            side = "l" if centre.x > 0.0 else "r"
            a, b = bones["thigh_" + side].head_local, bones["calf_" + side].tail_local
            kind, zero = "leg", Vector((1.0 if side == "l" else -1.0, 0.0, 0.0))
        elif bone.startswith(("upperarm_", "lowerarm_")):
            side = bone[-1]
            a, b = bones["upperarm_" + side].head_local, bones["upperarm_" + side].tail_local
            kind, zero = "arm", up
        else:
            a = Vector((0.0, bones["spine_01"].head_local.y, 0.0))
            b = a + up
            kind, zero = "trunk", Vector((0.0, 1.0, 0.0))
        d = (b - a).normalized()
        # The angle is 0 at `zero` (the outside of a leg, the top of a sleeve, the back of the
        # trunk) and the seam opposite it.
        zero = (zero - d * zero.dot(d)).normalized()
        across = d.cross(zero)
        first = None
        for loop in face.loops:
            rel = loop.vert.co - a
            angle = math.atan2(rel.dot(across), rel.dot(zero))
            # A face across the seam is laid out whole on one side of it.
            if first is None:
                first = angle
            else:
                angle = first + math.atan2(math.sin(angle - first), math.cos(angle - first))
            loop[wrap].uv = (angle * WRAP_RADIUS[kind], rel.dot(d))


def bake_folds(garment, body, out_png, pinned, size=1024, frames=40, slack=0.022):
    """Bakes a garment's folds into a normal map: a finer copy of it is hung
    on the body as cloth, held where it is held in life (pinned(co) -> True), given a little
    more cloth than the body needs (slack: 2%; at 4.5% a fitted jersey settled into lumps that
    made the body under it look uneven) so it gathers into folds as it settles, and the
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
    fold_maps.soften(out_png)
    print("make_player: baked %s folds to %s (and the shade in them)" % (garment.name, out_png))


def make_collar(jersey, rig, width=0.015):
    """The trim round the jersey's neckline ("Collar"): a band that follows the real edge of
    the opening and down both sides of the V, lying on the cloth."""
    bm = bmesh.new()
    bm.from_mesh(jersey.data)
    bm.normal_update()
    deform = bm.verts.layers.deform.verify()
    names = {g.index: g.name for g in jersey.vertex_groups}
    neck = rig.data.bones["neck_01"].head_local
    axis = (rig.data.bones["head"].head_local - neck).normalized()
    centre = neck + axis * 0.012
    near = lambda v: (v.co - centre).length < Anatomy.NECK_RADIUS + V_DEPTH + 0.05 and v.co.z > centre.z - V_DEPTH - 0.04
    edges = [e for e in bm.edges if e.is_boundary and all(near(v) for v in e.verts)]
    surface = BVHTree.FromBMesh(bm)
    out = bmesh.new()
    rows, weights = {}, {}
    for e in edges:
        for v in e.verts:
            if v in rows:
                continue
            along = Vector()
            for other in v.link_edges:
                if other.is_boundary:
                    w = other.other_vert(v).co - v.co
                    along += w if along.dot(w) >= 0.0 else -w
            inward = Vector()
            for f in v.link_faces:
                inward += f.calc_center_median() - v.co
            if along.length > 1e-6:
                along.normalize()
                inward -= along * inward.dot(along)
            if inward.length < 1e-6:
                continue
            inward.normalize()
            row = []
            for step in (-0.15, 0.5, 1.0):
                p = v.co + inward * width * step
                hit = surface.find_nearest(p)
                normal = hit[1] if hit[0] is not None else v.normal
                if normal.dot(v.normal) < 0.0:
                    normal = -normal
                base = hit[0] if (hit[0] is not None and step > 0.0) else p
                new = out.verts.new(base + normal * 0.0022)
                weights[tuple(round(c, 5) for c in new.co)] = [(names[g], w) for g, w in v[deform].items() if g in names and w > 0.01]
                row.append(new)
            rows[v] = row
    faces = []
    for e in edges:
        a, b = e.verts
        if a not in rows or b not in rows:
            continue
        for k in range(2):
            faces.append(out.faces.new((rows[a][k], rows[b][k], rows[b][k + 1], rows[a][k + 1])))
    gear.orient(faces, lambda c: centre + axis * (c - centre).dot(axis) + Vector((0.0, 0.03, 0.0)))
    bm.free()
    return gear.finish("Collar", out, rig, lambda co: weights.get(tuple(round(c, 5) for c in co), [("spine_03", 1.0)]), ["Collar"])


def strip_body(body, under_jersey=None):
    """Removes skin that is well under clothing or inside the shoes and sets body materials.
    under_jersey(face) -> True where the skin left under the jersey's edge is undershirt."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    region = bm.faces.layers.int["region"]
    depth = bm.faces.layers.float["depth"]
    # (The calves are kept whole under the trousers, as sock: a player who wears his trousers
    # to the knee shows them, and the game cuts the trousers there for him.)
    sock = bm.faces.layers.int.get("sock")
    is_sock = lambda f: sock is not None and f[sock] == 1
    hidden = [f for f in bm.faces if f[region] == SHOES or (f[region] in (JERSEY, BELT, PANTS) and f[depth] > TUCK and not is_sock(f))]
    bmesh.ops.delete(bm, geom=hidden, context='FACES')
    for face in bm.faces:
        face.material_index = {HANDS: 1, SOCKS: 2, UNDERSHIRT: 3}.get(face[region], 0)
        # What is left of the chest and shoulders under the jersey's edge is his undershirt
        # (it goes on under the jersey; bare skin showed as a band round the V of the neck).
        if face[region] == JERSEY and under_jersey is not None and under_jersey(face):
            face.material_index = 3
        if is_sock(face):
            face.material_index = 2
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


def trim_hair(hair, under_cap):
    """Cuts away the hair that would be under the cap (under_cap(point) -> True): a cap fits
    close to the skull, so hair left there would show through it."""
    for obj in hair:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if under_cap(v.co)], context='VERTS')
        bm.to_mesh(obj.data)
        bm.free()
        print("make_player: %s %d faces below the cap" % (obj.name, len(obj.data.polygons)))


def tailor_views(path, shown, top):
    """Flat views from the front, the side and the back of the given objects in their rest
    pose (TAILOR=<file.png> on a build), for checking how the clothes sit on the body."""
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'MATERIAL'
    scene.render.film_transparent = False
    scene.render.resolution_x, scene.render.resolution_y = 900, 1300
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            obj.hide_render = obj not in shown
    cam = bpy.data.objects.new("TailorCam", bpy.data.cameras.new("TailorCam"))
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = top * 1.06
    scene.collection.objects.link(cam)
    scene.camera = cam
    for suffix, at in (("_front", Vector((0.0, -6.0, top * 0.5))), ("_side", Vector((6.0, 0.0, top * 0.5))),
                       ("_back", Vector((0.0, 6.0, top * 0.5)))):
        cam.location = at
        cam.rotation_euler = (Vector((0.0, 0.0, top * 0.5)) - at).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.splitext(path)[0] + suffix + ".png"
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    for obj in bpy.data.objects:
        obj.hide_render = False


def fit_report(body_tree, garment, label, levels):
    """Prints how far a garment stands off the body at some heights: in front, behind and at
    the sides (cm). levels: {name: z}."""
    for name, z in levels.items():
        gaps = {"front": [], "back": [], "side": []}
        for v in garment.data.vertices:
            if abs(v.co.z - z) > 0.012:
                continue
            where = "side"
            if abs(v.co.x) < 0.06:
                where = "front" if v.co.y < 0.0 else "back"
            elif abs(v.co.x) < 0.1:
                continue
            hit = body_tree.find_nearest(v.co)
            if hit[0] is not None:
                gaps[where].append(hit[3])
        print("make_player: fit %s %s %s" % (BUILD, label, name) + "".join(
            "  %s %.1f cm" % (k, 100.0 * sum(g) / len(g)) for k, g in gaps.items() if g))


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
    for name, weight in {**SHAPE, **BUILD_SHAPE.get(BUILD, {})}.items():
        TargetService.load_target(body, TargetService.target_full_path(name), weight=weight, name=name)
    rig = HumanService.add_builtin_rig(body, "game_engine", import_weights=True)
    face_parts = add_skin_and_face(body)
    TargetService.bake_targets(body)
    # The face keys stay as keys (weight 0) for the game to set per player.
    for name in FACE_KEYS:
        TargetService.load_target(body, TargetService.target_full_path(name), weight=0.0, name="face_" + name)
    paired_keys(body)
    face_keys_to_parts(body, face_parts)
    stand_on_ground(body, rig)
    stem = os.path.splitext(OUT_GLB)[0]
    marks = body_marks(body, max(v.co.z for v in body.data.vertices))
    # The body's measurements against the tables (docs/09 section 4), kept next to the model.
    numbers = anthropometry.measure(body, rig, marks, bpy)
    for line in anthropometry.report(numbers):
        print("make_player: measure %s %s" % (BUILD, line))
    with open(stem + "_measure.json", "w") as f:
        json.dump({k: round(v, 4) for k, v in numbers.items()}, f, indent=1, sort_keys=True)
    if os.environ.get("MEASURE_ONLY"):
        return
    hair = add_hair(body)
    # (The brows' shade baked from the first brow only: four of them over each other darkened
    # the skin under all four.)
    bake_skin_maps(body, rig, [*hair, *[p for p in face_parts if p.name in ("Eyebrows", "Eyelashes")]], stem + "_skin_detail.png",
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
        """How far the cloth starts off the skin (the hang below then lets it fall straight):
        close at the collar, and lying on the tops of the shoulders, where a jersey rests."""
        bone = dominant(v, a)
        if bone.startswith("upperarm_"):
            t = min(max(a.along(bone, v.co) / SLEEVE_HEM, 0.0), 1.0)
            return 0.007 + 0.006 * t
        lift = 0.012
        if v.co.z < chest_z:
            lift += 0.002
        # Cloth lies on whatever faces up.
        lift *= 1.0 - 0.55 * _smooth(0.35, 0.85, v.normal.z)
        above_belt = v.co.z - (a.waist + BELT_HALF)
        if above_belt < 0.04:
            lift = 0.007 + (lift - 0.007) * max(above_belt, 0.0) / 0.04
        neck = a.outside_neckline(v.co)
        if neck < 0.04:
            lift = 0.005 + (lift - 0.005) * neck / 0.04
        return lift

    def jersey_drape(bm, a, skin):
        """A uniform top (from photographs): fitted — it follows the chest and
        the back a centimetre off them, runs a little straighter than the body from the
        chest to where it is tucked in (a tucked jersey is pulled down, not hung), and the
        sleeves lie on the tops of the arms and hang open under them."""
        belt_top = a.waist + BELT_HALF
        # Below the armpits the trunk is the ribs and the back; above, the shoulders (which
        # the jersey rests on and follows).
        armpit = rig.data.bones["upperarm_l"].head_local.z - 0.075
        trunk = [v for v in bm.verts if not dominant(v, a).startswith(("upperarm_", "lowerarm_")) and skin[v].z < armpit]
        mid_y = sum(skin[v].y for v in trunk) / len(trunk)
        low, high = Vector((0.0, mid_y, belt_top)), Vector((0.0, mid_y, armpit))
        tuck = 0.03 / (high.z - low.z)
        hang(trunk, skin, low, high, lambda u: 0.005 + 0.005 * _smooth(0.0, tuck, u),
             lambda u: 1.0 - _smooth(0.5, 1.0, u), sectors=16, hold=0.2)
        for side in ("l", "r"):
            bone = "upperarm_" + side
            sleeve = [v for v in bm.verts if dominant(v, a) == bone]
            start, end = rig.data.bones[bone].head_local, rig.data.bones["lowerarm_" + side].head_local
            d = (end - start).normalized()
            under = Vector((0.0, 0.0, -1.0))
            under = (under - d * under.dot(d)).normalized()
            hang(sleeve, skin, start, end, lambda u: 0.006 + 0.010 * _smooth(0.15, SLEEVE_HEM, u),
                 lambda u: _smooth(0.15, 0.4, u), sectors=10, slices=16, hold=0.5, settle=under)

    def pants_looseness(v, a, hem):
        """How far the cloth starts off the skin (the hang below shapes the legs): close at the
        belt, a little room over the seat."""
        bone = dominant(v, a)
        if bone.startswith("thigh_"):
            return 0.010
        if bone.startswith("calf_"):
            return 0.008
        if abs(v.co.z - a.waist) < BELT_HALF + 0.01:
            return 0.007
        return 0.010 + (0.002 if v.co.y > 0.0 else 0.0)

    def pants_drape(bm, a, skin):
        """Baseball trousers: each leg hangs from the widest of the thigh past the knee to the
        calf and on to an open hem over the shoe. (Skin pushed out along its normals bulged
        at the thigh and pinched at the knee like riding breeches.)"""
        for side, sign in (("l", 1.0), ("r", -1.0)):
            leg = [v for v in bm.verts if dominant(v, a) in ("thigh_" + side, "calf_" + side)]
            start, end = rig.data.bones["thigh_" + side].head_local, rig.data.bones["foot_" + side].head_local

            def ease(u):
                # Room at the thigh and knee, closer over the calf, then out to an open hem
                # wide enough to sit over the shoe.
                return 0.008 - 0.003 * _smooth(0.5, 0.72, u) + 0.010 * _smooth(0.8, 0.98, u)

            def apart(p, sign=sign):
                # The legs of a pair of trousers do not pass through each other.
                if p.x * sign < 0.003:
                    p = p.copy()
                    p.x = 0.003 * sign
                return p

            # (Fitted: with more ease and a straighter fall the legs were two wide tubes, and
            # a batter in his stance looked heavy.)
            hang(leg, skin, start, end, ease, lambda u: _smooth(0.16, 0.34, u), sectors=12, slices=40, hold=0.42, limit=apart)

    jersey = make_garment(body, "Jersey", (JERSEY,), jersey_looseness, [JERSEY], anatomy_of, None, jersey_drape)
    pants = make_garment(body, "Pants", (PANTS, BELT), pants_looseness, [PANTS, BELT], anatomy_of, None, pants_drape)
    # How far the jersey stands off the body at chest height (2 to 5 cm).
    depsgraph = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(body, depsgraph)
    gaps = [tree.find_nearest(v.co)[3] for v in jersey.data.vertices if abs(v.co.z - chest_z) < 0.02 and abs(v.co.x) < 0.17]
    if gaps:
        print("make_player: build %s jersey off the chest %.1f cm on average" % (BUILD, 100.0 * sum(gaps) / len(gaps)))
    belt_top = top * BELT_CENTRE + BELT_HALF
    shoulder_z = rig.data.bones["upperarm_l"].head_local.z
    fit_report(tree, jersey, "jersey", {"shoulder blades": shoulder_z - 0.05, "chest": chest_z, "ribs": (chest_z + belt_top) * 0.5,
                                        "over the belt": belt_top + 0.03})
    knee_z = rig.data.bones["calf_l"].head_local.z
    fit_report(tree, pants, "pants", {"seat": top * 0.5, "thigh": (top * 0.47 + knee_z) * 0.5, "knee": knee_z, "calf": knee_z * 0.68, "hem": 0.11})
    if os.environ.get("TAILOR"):
        tailor_views(os.environ["TAILOR"], [body, jersey, pants], top)
    # Folds: the jersey hangs from the shoulders and is tucked in at the belt;
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
    batter_guards = [gear.elbow_guard(body, jersey, rig), gear.leg_guard(pants, rig)]
    officials.material = material
    umpire = officials.mask(body, marks, rig)
    umpire_kit = [officials.polo_collar(jersey, rig, Anatomy.NECK_RADIUS),
                  officials.ball_bags(pants, rig, top * BELT_CENTRE, BELT_HALF)]
    kit.material = material
    gear.material = material
    collar = make_collar(jersey, rig)
    cap, cap_button, under_cap = kit.cap(body, marks, rig)
    # The plate umpire's cap has a short bill, to go under his mask.
    umpire_kit.append(kit.cap(body, marks, rig, name="UmpireCap", bill=0.034)[0])
    buckle = kit.buckle(pants, rig, top * BELT_CENTRE, BELT_HALF)
    piping = kit.side_piping(pants, rig, top * BELT_CENTRE - BELT_HALF - 0.004, p_bottom + 0.004)
    neck_at = rig.data.bones["neck_01"].head_local
    strip_body(body, lambda f: (f.calc_center_median() - neck_at).length < Anatomy.NECK_RADIUS + V_DEPTH + 0.06
               and abs(f.calc_center_median().x) < Anatomy.NECK_RADIUS + 0.05)
    store_limb_coordinates(body, rig)
    trim_hair(hair, under_cap)
    optional = [*catcher_gear, *batter_guards, umpire, *umpire_kit, *flaps, helmet]
    parts = [body, jersey, collar, pants, buckle, piping, kit.shoes(feet, rig), *face_parts, *hair, cap, cap_button, *optional]

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
                              export_morph_normal=True, export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                              export_active_vertex_color_when_no_material=True)
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


if __name__ == "__main__":
    main()
