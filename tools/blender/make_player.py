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

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_GLB = ARGS[0] if ARGS else "player_base.glb"
PREVIEW = ARGS[1] if len(ARGS) > 1 and ARGS[1] != "-" else None
BUILD = ARGS[2] if len(ARGS) > 2 else "standard"

# Body shape: a professional ballplayer of about 183 cm and 88 kg (docs/12, section 4). More
# muscle and weight than an average man of that height: chest depth about 14% of height.
MACRO = {"gender": 1.0, "age": 0.5, "muscle": 0.9, "weight": 0.65, "height": 0.6, "proportions": 0.55}
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
    "eyebrows-trans-forward": 0.35, "forehead-nubian-incr": 0.2, "measure-neck-circ-incr": 0.45, "head-square": 0.25,
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
    "lean": {"muscle": 0.75, "weight": 0.35},
    "standard": {"muscle": 0.9, "weight": 0.65},
    "solid": {"muscle": 1.0, "weight": 0.82},
    "heavy": {"muscle": 0.95, "weight": 1.0},
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
    "Undershirt": (0.10, 0.15, 0.35),
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


def make_shell(body, rig, name, keep, lift, mat_name):
    """Padding worn over the uniform (chest protector, shin guards): the chosen faces of the
    body, pushed well out and smoothed. keep(face, anatomy, region) picks the faces."""
    obj = body.copy()
    obj.data = body.data.copy()
    obj.name = obj.data.name = name
    bpy.context.scene.collection.objects.link(obj)
    obj.shape_key_clear()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    anatomy = Anatomy(obj, rig, bm)
    region = bm.faces.layers.int["region"]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not keep(f, anatomy, f[region])], context='FACES')
    bm.normal_update()
    edge = {v for e in bm.edges if e.is_boundary for v in e.verts}
    for v in bm.verts:
        v.co += v.normal * (lift * (0.55 if v in edge else 1.0))
    for _ in range(3):
        bmesh.ops.smooth_vert(bm, verts=[v for v in bm.verts if v not in edge], factor=0.5,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    for face in bm.faces:
        face.material_index = 0
    obj.data.materials.clear()
    obj.data.materials.append(material(mat_name))
    bm.to_mesh(obj.data)
    bm.free()
    return obj


TORSO = {"spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"}


def is_chest(face, anatomy, region):
    c = face.calc_center_median()
    return (region == JERSEY and anatomy.bone(face) in TORSO and face.normal.y < -0.2
            and c.z > anatomy.waist + 0.05 and anatomy.outside_neckline(c) > 0.035)


def is_shin(face, anatomy, region):
    bone = anatomy.bone(face)
    if face.normal.y > -0.15:
        return False
    c = face.calc_center_median()
    if bone.startswith("calf_"):
        return anatomy.along(bone, c) < 0.93
    return bone.startswith("thigh_") and anatomy.along(bone, c) > 0.84


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


def make_mask(head_points, rig):
    """Catcher's and umpire's mask: a cage of bars in front of the face under a padded brow."""
    centre, half_w, half_d, top, height = head_box(head_points)
    rx, ry = half_w + 0.03, half_d + 0.05
    brow, chin = top - height * 0.36, top - height * 1.0
    bm = bmesh.new()

    def at(angle_deg, z):
        a = math.radians(angle_deg)
        return Vector((centre.x + rx * math.sin(a), centre.y - ry * math.cos(a), z))

    def strip(points, thickness, direction):
        for p, q in zip(points, points[1:]):
            bm.faces.new((bm.verts.new(p - direction * thickness), bm.verts.new(q - direction * thickness),
                          bm.verts.new(q + direction * thickness), bm.verts.new(p + direction * thickness)))

    up = Vector((0.0, 0.0, 1.0))
    arc = [-68.0 + 136.0 * i / 16 for i in range(17)]
    for row in range(6):
        z = brow + (chin - brow) * row / 5
        strip([at(a, z) for a in arc], 0.014 if row == 0 or row == 5 else 0.0045, up)
    for angle in (-44.0, -22.0, 0.0, 22.0, 44.0):
        columns = [at(angle - 0.9, brow + (chin - brow) * i / 6) for i in range(7)]
        across = (at(angle + 0.9, brow) - at(angle - 0.9, brow)).normalized()
        strip(columns, 0.0045, across)
    return skinned_object("Mask", bm, rig, lambda co: "head", "Bars")


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


def make_helmet(head_points, rig):
    """Batting helmet: a larger shell over the ears and the back of the head, open at the
    face, with a short brim."""
    centre, half_w, half_d, top, height = head_box(head_points)
    rx, ry, rz = half_w + 0.024, half_d + 0.026, height * 0.46
    centre.z = top - rz + 0.022
    brow = centre.z - 0.012
    bm = bmesh.new()
    dome(bm, centre, rx, ry, rz, 0.62, face_open=brow)
    brim(bm, centre, rx, ry, brow, 0.055, 62.0)
    return skinned_object("Helmet", bm, rig, lambda co: "head", "Helmet")


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


def make_helmet_flap(head_points, rig, side):
    """The ear flap of a batting helmet (docs/13 S11-5): a curved plate from the helmet's rim
    down over one ear to the jaw, with the ear hole as a dark ring. Batters wear it on the ear
    toward the pitcher (a right-handed batter on the left); switch hitters on both."""
    centre, half_w, half_d, top, height = head_box(head_points)
    rx, ry, rz = half_w + 0.024, half_d + 0.026, height * 0.46
    cz = top - rz + 0.022
    sign = 1.0 if side == "Left" else -1.0
    bm = bmesh.new()
    rows = []
    # From the helmet's lower edge on that side down to about the jaw, round the ear.
    for i in range(6):
        z = cz - rz * math.sin(0.62) + 0.004 - i * 0.016
        row = []
        for j in range(7):
            a = math.radians(-40.0 + 80.0 * j / 6.0)
            width = 1.0 - 0.25 * (i / 5.0) ** 2
            x = centre.x + sign * (rx + 0.002) * math.cos(a * 0.55) * (0.98 + 0.02 * i)
            y = centre.y + ry * math.sin(a) * 0.62 * width
            row.append(bm.verts.new(Vector((x, y, z))))
        rows.append(row)
    for i in range(5):
        for j in range(6):
            quad = (rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j])
            bm.faces.new(quad if side == "Left" else tuple(reversed(quad)))
    return skinned_object("HelmetFlap" + side, bm, rig, lambda co: "head", "Helmet")


def make_cap_button(head_points, rig):
    """The button on top of the cap."""
    centre, half_w, half_d, top, height = head_box(head_points)
    bm = bmesh.new()
    dome(bm, Vector((centre.x, centre.y, top + 0.012)), 0.009, 0.009, 0.006, 0.0)
    return skinned_object("CapButton", bm, rig, lambda co: "head", "Cap")


def render_preview(path, target_z):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x, scene.render.resolution_y = 900, 760
    world = bpy.data.worlds.new("Preview")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62, 0.66, 0.72, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0.0, math.radians(-35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 60
    scene.collection.objects.link(cam)
    cam.location = (2.6, -4.6, target_z + 0.25)
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
            return 0.020 + 0.026 * t
        lift = 0.025
        if v.co.z < chest_z:
            lift += 0.007
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
            seat = 0.006 if v.co.y > 0.0 and t < 0.35 else 0.0
            return 0.034 - 0.008 * t + seat
        if bone.startswith("calf_"):
            t = min(max(a.along(bone, v.co) / PANTS_HEM, 0.0), 1.0)
            return 0.024 - 0.014 * t + 0.003 * math.sin(t * 2.0 * math.pi * 4.0)
        if abs(v.co.z - a.waist) < BELT_HALF + 0.01:
            return 0.012
        return 0.028 + (0.008 if v.co.y > 0.0 else 0.0)

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
    # Catcher's gear is built from the body before the covered skin is removed.
    gear = [make_shell(body, rig, "ChestProtector", is_chest, 0.045, "Gear"),
            make_shell(body, rig, "ShinGuards", is_shin, 0.032, "Gear")]
    strip_body(body)
    trim_hair(hair, head_points)
    optional = [*gear, make_mask(head_points, rig), make_helmet_flap(head_points, rig, "Left"),
                make_helmet_flap(head_points, rig, "Right"), make_helmet(head_points, rig)]
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
        # The preview shows a catcher's gear and a batting helmet with its left flap.
        for obj in optional:
            obj.hide_render = obj.name == "HelmetFlapRight"
        for obj in parts:
            if obj.name in ("Cap", "CapButton"):
                obj.hide_render = True
        render_preview(PREVIEW, height * 0.5)
        print("make_player: preview", PREVIEW)


main()
