"""Builds the crowd's picture atlas from Microsoft Rocketbox people (MIT licence).

    blender -b --python tools/blender/make_crowd.py -- <rocketbox folder> <out folder>

Each person in the folder (one sub-folder each: the FBX and its textures, as in the
Rocketbox repository's Assets/Avatars/Adults/<name>/Export and Textures) is posed four ways —
seated, standing, standing with both arms up (cheering), seated clapping — and photographed
from in front against nothing. The pictures go side by side into crowd_atlas.png (8 columns:
two people a row, their four poses each) with a second atlas, crowd_mask.png, white where the
person wears his top: the game dyes that part in the club's colour for the cheering sections
. Pictures are FRAME_W x FRAME_H pixels and cover FRAME_HEIGHT_M metres.
"""
import math
import os
import shutil
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SOURCE = ARGS[0] if ARGS else "content-local/rocketbox"
OUT = ARGS[1] if len(ARGS) > 1 else "game/assets/crowd"
FRAME_W = 128
FRAME_H = 256
FRAME_HEIGHT_M = 2.0
# Eight ways of sitting and standing a row (one person a row of the atlas): people in a
# crowd are never all in one attitude. (With four, and "standing" a soldier at attention,
# the stands looked like ranks of mannequins.)
POSES = ["seated", "seated_lean", "seated_arms", "clapping", "standing", "standing_clap", "cheering", "cheer_one",
         # With things in their hands (the user, 2026-11-23: "the crowd is all the same; close up,
         # people eating, people cheering with sticks"): fried chicken from its box, a beer, a
         # phone held up to film, a pair of inflated thunder sticks up and struck together, the
         # club's towel held up.
         "eating", "drinking", "phone", "sticks_up", "sticks_hit", "towel"]
# Cheerleaders on the cheering stages: two more people, dressed in the club's colour (their
# top, hips and thighs dyed), with pom-poms, their pictures six steps of a dance (repeated to
# fill a person's row of poses).
CHEERLEADERS = ["Female_Adult_01", "Female_Adult_03"]
DANCE = ["dance_v", "dance_low", "dance_chest", "dance_right", "dance_left", "dance_front"]
CHEER_SCALE = 1.25
# Every third fan wears a cap (dyed with his top: the club's cap in the cheering sections).
CAP_EVERY = 3
COLUMNS = 16
# Bones whose skin is the top (shirt, jacket): dyed in the club's colour.
TOP_BONES = ("Spine", "Spine1", "Spine2", "L Clavicle", "R Clavicle", "L UpperArm", "R UpperArm")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# Rocketbox's people keep their own hair now (they are the few Westerners among the Korean crowd).
DARK_HAIR = False


def load_person(folder):
    name = os.path.basename(folder)
    fbx = os.path.join(folder, name + ".fbx")
    bpy.ops.import_scene.fbx(filepath=fbx)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
    textures = {f.lower(): os.path.join(folder, f) for f in os.listdir(folder) if f.lower().endswith(".tga")}
    for mat in mesh.data.materials:
        part = mat.name.split("_")[-1]  # body, head, opacity
        colour = next((p for f, p in textures.items() if f.endswith("%s_color.tga" % part)), None)
        normal = next((p for f, p in textures.items() if f.endswith("%s_normal.tga" % part)), None)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        nodes.clear()
        out = nodes.new("ShaderNodeOutputMaterial")
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Roughness"].default_value = 0.75
        links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        if colour:
            img = nodes.new("ShaderNodeTexImage")
            img.image = bpy.data.images.load(colour)
            if part == "opacity" and DARK_HAIR:
                # The hair (and lashes): black to dark brown, as a Korean crowd's (the user,
                # 2026-11-23: "make the faces Korean — they all look Western"); a few kept a
                # little browner, as some dye theirs.
                dark = nodes.new("ShaderNodeHueSaturation")
                dark.inputs["Saturation"].default_value = 0.55
                dark.inputs["Value"].default_value = 0.22 if sum(map(ord, name)) % 4 else 0.4
                links.new(img.outputs["Color"], dark.inputs["Color"])
                links.new(dark.outputs["Color"], bsdf.inputs["Base Color"])
            else:
                links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
            if part == "opacity":
                links.new(img.outputs["Alpha"], bsdf.inputs["Alpha"])
                mat.blend_method = 'HASHED' if hasattr(mat, "blend_method") else mat.blend_method
        if normal:
            nimg = nodes.new("ShaderNodeTexImage")
            nimg.image = bpy.data.images.load(normal)
            nimg.image.colorspace_settings.name = "Non-Color"
            nmap = nodes.new("ShaderNodeNormalMap")
            links.new(nimg.outputs["Color"], nmap.inputs["Color"])
            links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return name, arm, mesh


# The bones by Rocketbox's names; a MakeHuman person's are mapped (crowd_people.BONES).
BONE_MAP = {}


def bone(arm, name):
    return arm.pose.bones[BONE_MAP.get(name, name)]


def frame_axes(arm):
    """World up, the person's right and forward, from the eyes."""
    bpy.context.view_layer.update()
    mw = arm.matrix_world
    if "Bip01 LEye" in arm.pose.bones:
        l_eye = mw @ arm.pose.bones["Bip01 LEye"].head
        r_eye = mw @ arm.pose.bones["Bip01 REye"].head
    else:
        # (No eye bones on MakeHuman's game rig: the shoulders give the sides.)
        l_eye = mw @ bone(arm, "Bip01 L UpperArm").head
        r_eye = mw @ bone(arm, "Bip01 R UpperArm").head
    up = Vector((0.0, 0.0, 1.0))
    right = (r_eye - l_eye)
    right.z = 0.0
    right.normalize()
    forward = up.cross(right).normalized()
    return up, right, forward


# The next joint along each limb: a bone points from its own joint to this one. (The
# imported bones' own axes do not run along the limbs: they came from 3ds Max's biped.)
NEXT = {"Thigh": "Calf", "Calf": "Foot", "Foot": "Toe0", "UpperArm": "Forearm", "Forearm": "Hand"}
SPINE_NEXT = {"Bip01 Spine": "Bip01 Spine1", "Bip01 Spine1": "Bip01 Spine2", "Bip01 Spine2": "Bip01 Neck", "Bip01 Neck": "Bip01 Head"}


def aim(arm, bone_name, direction):
    """Turns a pose bone so its limb (joint to next joint) points along `direction` (world),
    children following."""
    bpy.context.view_layer.update()
    name = bone_name
    if BONE_MAP.get(name, name) not in arm.pose.bones:
        return
    pb = bone(arm, name)
    if name in SPINE_NEXT:
        if BONE_MAP.get(SPINE_NEXT[name], SPINE_NEXT[name]) not in arm.pose.bones:
            return
        child = bone(arm, SPINE_NEXT[name])
    else:
        side, part = name.split(" ")[1], name.split(" ")[-1]
        child = bone(arm, "Bip01 %s %s" % (side, NEXT[part]))
    to_arm = arm.matrix_world.inverted().to_3x3()
    want = (to_arm @ direction).normalized()
    m = pb.matrix.copy()
    head = m.translation.copy()
    current = (child.matrix.translation - head).normalized()
    turn = current.rotation_difference(want).to_matrix().to_4x4()
    pb.matrix = Matrix.Translation(head) @ turn @ Matrix.Translation(-head) @ m
    bpy.context.view_layer.update()


def pose(arm, which, up, right, forward):
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    down = -up
    seated = which in ("seated", "seated_lean", "seated_arms", "clapping", "eating", "drinking")
    if which.startswith("dance"):
        dance(arm, which, up, right, forward)
        return
    if which == "seated_lean":
        # Elbows on the knees: the back comes forward.
        aim(arm, "Bip01 Spine", up * 0.86 + forward * 0.5)
    elif which in ("cheering", "cheer_one"):
        aim(arm, "Bip01 Spine", up + forward * -0.06)
    for side, s in (("L", -1.0), ("R", 1.0)):
        out = right * s
        if seated:
            aim(arm, "Bip01 %s Thigh" % side, forward * 0.97 + down * 0.08 + out * (0.16 if which == "seated_lean" else 0.08))
            aim(arm, "Bip01 %s Calf" % side, down * 0.97 + forward * (0.02 if which == "seated_lean" else 0.12))
            aim(arm, "Bip01 %s Foot" % side, forward)
        elif which == "standing":
            # Weight on one leg, the other eased forward.
            aim(arm, "Bip01 %s Thigh" % side, down + out * (0.1 if side == "L" else 0.03) + forward * (0.0 if side == "L" else 0.09))
            aim(arm, "Bip01 %s Calf" % side, down + forward * (0.0 if side == "L" else -0.05))
            aim(arm, "Bip01 %s Foot" % side, forward + out * 0.25)
        else:
            aim(arm, "Bip01 %s Thigh" % side, down + out * 0.08)
            aim(arm, "Bip01 %s Calf" % side, down)
            aim(arm, "Bip01 %s Foot" % side, forward + out * 0.15)
        upper, fore = "Bip01 %s UpperArm" % side, "Bip01 %s Forearm" % side
        if which == "cheering":
            # Arms up and out in a V, elbows bent: a cheer, not a signal.
            aim(arm, upper, up * 0.7 + out * 0.62 + forward * 0.15)
            aim(arm, fore, up * 0.95 + out * 0.12 + forward * 0.12)
        elif which == "cheer_one":
            if side == "R":
                aim(arm, upper, up * 0.85 + out * 0.3 + forward * 0.22)
                aim(arm, fore, up + forward * 0.12)
            else:
                aim(arm, upper, down + out * 0.14 + forward * 0.1)
                aim(arm, fore, forward * 0.6 + down * 0.6 - out * 0.1)
        elif which == "clapping":
            aim(arm, upper, down * 0.6 + forward * 0.7 + out * 0.15)
            aim(arm, fore, forward * 0.6 + up * 0.55 - out * 0.45)
        elif which == "standing_clap":
            aim(arm, upper, down * 0.75 + forward * 0.5 + out * 0.2)
            aim(arm, fore, forward * 0.45 + up * 0.68 - out * 0.56)
        elif which == "seated":
            aim(arm, upper, down * 0.9 + forward * 0.3 + out * 0.12)
            aim(arm, fore, forward * 0.85 + down * 0.35 - out * 0.1)
        elif which == "seated_lean":
            aim(arm, upper, down * 0.55 + forward * 0.8 + out * 0.1)
            aim(arm, fore, forward * 0.45 + down * 0.3 - out * 0.6)
        elif which == "eating" and side == "R" or which == "drinking" and side == "R":
            # A hand to the mouth (a drumstick, a cup).
            aim(arm, upper, down * 0.8 + forward * 0.42 + out * 0.2)
            aim(arm, fore, up * 0.92 + forward * 0.12 - out * 0.38)
        elif which in ("eating", "drinking"):
            # The other hand on the lap (the chicken's box) or at rest.
            aim(arm, upper, down * 0.9 + forward * 0.3 + out * 0.12)
            aim(arm, fore, forward * 0.9 + down * 0.25 - out * 0.2)
        elif which == "phone":
            if side == "R":
                # Held up in front at eye height, to film.
                aim(arm, upper, forward * 0.8 + up * 0.2 + out * 0.05)
                aim(arm, fore, forward * 0.8 + up * 0.5 - out * 0.25)
            else:
                aim(arm, upper, down + out * 0.12 + forward * 0.05)
                aim(arm, fore, down + forward * 0.25)
        elif which == "sticks_up":
            # Thunder sticks held up either side of the head, elbows out and forward (kept
            # inside the picture).
            aim(arm, upper, out * 0.3 + forward * 0.85 - up * 0.1)
            aim(arm, fore, up * 0.8 + forward * 0.45 + out * 0.05)
        elif which == "sticks_hit":
            # Struck together in front of the face.
            aim(arm, upper, down * 0.4 + forward * 0.75 + out * 0.2)
            aim(arm, fore, up * 0.75 + forward * 0.45 - out * 0.45)
        elif which == "towel":
            # The club's towel stretched between the hands in front of the chest (a KBO
            # stand's towel cheer), the face over it.
            aim(arm, upper, down * 0.55 + forward * 0.6 + out * 0.35)
            aim(arm, fore, forward * 0.6 + up * 0.7 + out * 0.05)
        elif which == "seated_arms":
            # Arms folded across the chest.
            aim(arm, upper, down * 0.95 + forward * 0.28 + out * 0.1)
            aim(arm, fore, forward * 0.3 + up * 0.12 - out * 0.95)
        else:
            # Standing at ease: one hand up at the waist (a drink, a phone), the other down.
            if side == "L":
                aim(arm, upper, down + out * 0.14 + forward * 0.12)
                aim(arm, fore, forward * 0.85 + down * 0.25 - out * 0.25)
            else:
                aim(arm, upper, down + out * 0.16 + forward * 0.02)
                aim(arm, fore, down + forward * 0.22)


def dance(arm, which, up, right, forward):
    """A cheerleader's step: on her feet, knees soft, arms in one of six shapes."""
    down = -up
    for side, s in (("L", -1.0), ("R", 1.0)):
        out = right * s
        aim(arm, "Bip01 %s Thigh" % side, down + out * 0.1 + forward * 0.04)
        aim(arm, "Bip01 %s Calf" % side, down + forward * -0.03)
        aim(arm, "Bip01 %s Foot" % side, forward + out * 0.15)
        upper, fore = "Bip01 %s UpperArm" % side, "Bip01 %s Forearm" % side
        if which == "dance_v":
            aim(arm, upper, up * 0.9 + out * 0.42)
            aim(arm, fore, up * 0.95 + out * 0.3)
        elif which == "dance_low":
            aim(arm, upper, down * 0.85 + out * 0.5)
            aim(arm, fore, down * 0.8 + out * 0.55)
        elif which == "dance_chest":
            # Pom-poms shaken in front of the chest, elbows out.
            aim(arm, upper, down * 0.35 + out * 0.7 + forward * 0.4)
            aim(arm, fore, forward * 0.55 - out * 0.75 + up * 0.35)
        elif which in ("dance_right", "dance_left"):
            punching = (which == "dance_right") == (side == "R")
            if punching:
                aim(arm, upper, up * 0.95 + out * 0.3)
                aim(arm, fore, up + out * 0.15)
            else:
                # A hand on the hip.
                aim(arm, upper, down * 0.6 + out * 0.75 + forward * -0.1)
                aim(arm, fore, down * 0.5 - out * 0.85 + forward * 0.1)
        else:
            aim(arm, upper, forward * 0.8 + up * 0.5 + out * 0.15)
            aim(arm, fore, forward * 0.75 + up * 0.6 + out * 0.05)


def hand_at(arm, side):
    """Where a hand holds things (world), and the way its forearm points."""
    bpy.context.view_layer.update()
    mw = arm.matrix_world
    wrist = mw @ bone(arm, "Bip01 %s Hand" % side).head
    elbow = mw @ bone(arm, "Bip01 %s Forearm" % side).head
    along = (wrist - elbow).normalized()
    return wrist + along * 0.07, along


def material(name, colour, rough=0.6):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (colour[0], colour[1], colour[2], 1.0)
        bsdf.inputs["Roughness"].default_value = rough
    return m


def solid(kind, size, at, axis, colour, dyed, rough=0.6):
    """A primitive (a box, a cylinder, a ball) of `size` at `at`, its length along `axis`."""
    if kind == "box":
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.5, depth=1.0, location=at)
    else:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.5, location=at)
    ob = bpy.context.active_object
    ob.scale = size
    ob.rotation_euler = axis.to_track_quat('Z', 'Y').to_euler()
    ob.data.materials.append(material("Prop%.2f%.2f%.2f" % colour, colour, rough))
    ob["dyed"] = 1.0 if dyed else 0.0
    return ob


def square(ob, x, y, z):
    """Turns a prop so its own axes lie along x, y, z (world)."""
    ob.rotation_euler = Matrix((x, y, z)).transposed().to_euler()


def pom_pom(at):
    """A pom-pom: a ball of strips, shaggy (jittered), in the club's colour."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.095, location=at)
    ob = bpy.context.active_object
    import random
    rnd = random.Random(int(at.x * 1000) ^ int(at.z * 1000))
    for v in ob.data.vertices:
        v.co *= rnd.uniform(0.75, 1.25)
    ob.data.materials.append(material("PomPom", (0.92, 0.92, 0.92), 0.9))
    ob["dyed"] = 1.0
    return ob


def props_for(arm, which, up, right, forward, cheerleader):
    """The things in a person's hands in this picture (removed after it is taken)."""
    made = []
    if cheerleader:
        for side in ("L", "R"):
            at, _ = hand_at(arm, side)
            made.append(pom_pom(at))
        return made
    r_at, r_along = hand_at(arm, "R")
    l_at, l_along = hand_at(arm, "L")
    if which == "eating":
        # A fried drumstick, and the box on the lap.
        made.append(solid("ball", Vector((0.07, 0.07, 0.11)), r_at + up * 0.03, up, (0.55, 0.3, 0.1), False, 0.5))
        made.append(solid("box", Vector((0.2, 0.14, 0.06)), l_at + up * 0.02, up, (0.85, 0.15, 0.12), False))
    elif which == "drinking":
        cup = solid("cyl", Vector((0.08, 0.08, 0.14)), r_at + up * 0.04, up, (0.95, 0.7, 0.18), False, 0.2)
        made.append(cup)
        made.append(solid("cyl", Vector((0.082, 0.082, 0.03)), r_at + up * 0.12, up, (0.97, 0.96, 0.92), False, 0.8))
    elif which == "phone":
        # Upright, its back to the camera that sees his face (he films the field).
        phone = solid("box", Vector((0.08, 0.01, 0.16)), r_at + up * 0.06 + forward * 0.02, up, (0.04, 0.04, 0.05), False, 0.2)
        square(phone, right, forward, up)
        made.append(phone)
    elif which in ("sticks_up", "sticks_hit"):
        for at, s in ((r_at, 1.0), (l_at, -1.0)):
            # Up from the hands, a little apart when held up, leaning together when struck.
            way = (up * 0.95 + right * s * (0.12 if which == "sticks_up" else -0.14) + forward * 0.08).normalized()
            made.append(solid("cyl", Vector((0.07, 0.07, 0.28)), at + way * 0.11, way, (0.92, 0.92, 0.92), True, 0.35))
    elif which == "towel":
        # Stretched between the hands, hanging from them over the chest.
        mid = (r_at + l_at) * 0.5
        width = (r_at - l_at).length + 0.1
        towel = solid("box", Vector((width, 0.012, 0.2)), mid - up * 0.08 + forward * 0.03, up, (0.92, 0.92, 0.92), True, 0.9)
        square(towel, right, forward, up)
        made.append(towel)
    return made


def cap_for(arm, up, forward):
    """A baseball cap on the head: a crown and a peak."""
    bpy.context.view_layer.update()
    mw = arm.matrix_world
    if "Bip01 LEye" in arm.pose.bones:
        eyes = (mw @ arm.pose.bones["Bip01 LEye"].head + mw @ arm.pose.bones["Bip01 REye"].head) * 0.5
    else:
        # (MakeHuman's head bone runs from the skull's base to its top: the eyes a little
        # under halfway up, in front.)
        hb = bone(arm, "Bip01 Head")
        eyes = (mw @ hb.head).lerp(mw @ hb.tail, 0.42) + forward * 0.085
    head = mw @ bone(arm, "Bip01 Head").head
    centre = eyes + up * 0.045 - forward * 0.055
    if "Bip01 LEye" not in arm.pose.bones:
        # (MakeHuman: from the top of the skull, the head bone's tip, over the hair.)
        top = mw @ bone(arm, "Bip01 Head").tail
        centre = top - up * 0.075 - forward * 0.01
        eyes = centre - up * 0.045 + forward * 0.055
    tilt = (up + forward * 0.08).normalized()
    crown = solid("ball", Vector((0.205, 0.215, 0.15)), centre + up * 0.02, tilt, (0.92, 0.92, 0.92), True, 0.7)
    peak = solid("box", Vector((0.17, 0.11, 0.012)), eyes + up * 0.05 + forward * 0.1, tilt, (0.92, 0.92, 0.92), True, 0.7)
    peak.rotation_euler = (forward * 1.0 + up * -0.12).normalized().to_track_quat('Y', 'Z').to_euler()
    return [crown, peak]


def lowest_point(mesh):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(deps)
    m = ev.to_mesh()
    z = min((mesh.matrix_world @ v.co).z for v in m.vertices)
    ev.to_mesh_clear()
    return z


def flat_mask(name, white):
    """A prop's look in the mask: white (dyed) or black (kept), light-independent."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0 if white else 0.0
    mat.node_tree.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def top_mask_material():
    """White where the top is (from the skin weights), black elsewhere, light-independent."""
    mat = bpy.data.materials.new("TopMask")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    attr = nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "top"
    mat.node_tree.links.new(attr.outputs["Fac"], emit.inputs["Strength"])
    mat.node_tree.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def mark_top(mesh, bones=TOP_BONES):
    """A per-vertex 'top' attribute: 1 where the strongest bone is one of `bones`."""
    groups = {g.index: g.name for g in mesh.vertex_groups}
    values = []
    for v in mesh.data.vertices:
        best, weight = "", 0.0
        for g in v.groups:
            if g.weight > weight:
                best, weight = groups.get(g.group, ""), g.weight
        values.append(1.0 if any(best.endswith(b) for b in bones) else 0.0)
    attr = mesh.data.attributes.new("top", 'FLOAT', 'POINT')
    attr.data.foreach_set("value", values)


def setup_render(scene):
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = FRAME_W
    scene.render.resolution_y = FRAME_H
    scene.render.film_transparent = True
    # No view transform: the game applies its own, and the mask must come out pure white.
    scene.view_settings.view_transform = 'Standard'
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.75, 0.78, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world


def camera_and_light(scene, forward, height_mid, name="Cam", span=FRAME_HEIGHT_M):
    """A camera looking at the person from `forward` (his front; minus it, his back), and a sun
    over that shoulder. Returns (camera, sun)."""
    cam_data = bpy.data.cameras.new(name)
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = span
    cam = bpy.data.objects.new(name, cam_data)
    scene.collection.objects.link(cam)
    cam.location = forward * 6.0 + Vector((0.0, 0.0, height_mid))
    cam.rotation_euler = (-forward).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    sun_data = bpy.data.lights.new(name + "Sun", 'SUN')
    sun_data.energy = 3.0
    sun = bpy.data.objects.new(name + "Sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (forward + Vector((0.3, 0.0, 1.2))).normalized().to_track_quat('-Z', 'Y').to_euler()
    return cam, sun


# Each person from the back as well (the user, 2026-11-23: seen from behind the stands, the fans
# faced the camera, not the game): the game shows a fan's back when the eye is behind him.
VIEWS = ["", "_back"]


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# A few of Rocketbox's people among the Korean crowd (the user: "a very few Westerners").
WESTERNERS = ["Female_Adult_02", "Male_Adult_01", "Male_Adult_06"]


def main():
    global BONE_MAP
    import crowd_people
    tmp = os.path.join(OUT, "_frames")
    os.makedirs(tmp, exist_ok=True)
    names = []
    # The Korean fans (MakeHuman), a few Westerners (Rocketbox), then the cheerleaders.
    jobs = [("mh", spec, False) for spec in crowd_people.specs()]
    jobs += [("rb", os.path.join(SOURCE, w), False) for w in WESTERNERS if os.path.isdir(os.path.join(SOURCE, w))]
    jobs += [("mh", spec, True) for spec in crowd_people.cheerleader_specs()]
    fans_count = sum(1 for j in jobs if not j[2])
    for n, (source, what, cheerleader) in enumerate(jobs):
        reset()
        if source == "mh":
            name, arm, meshes, top = crowd_people.build(what, cheerleader)
            BONE_MAP = crowd_people.BONES
            for m in meshes:
                if m.get("dyed_top"):
                    mark_top(m, top)
        else:
            name, arm, mesh = load_person(what)
            BONE_MAP = {}
            meshes = [mesh]
            mark_top(mesh, TOP_BONES + (("Pelvis", "L Thigh", "R Thigh") if cheerleader else ()))
        name = name + ("_cheer" if cheerleader and not name.endswith(("cheer1", "cheer2")) else "")
        names.append(name)
        scene = bpy.context.scene
        setup_render(scene)
        up, right, forward = frame_axes(arm)
        materials = {m.name: list(m.data.materials) for m in meshes}
        mask = top_mask_material()
        mask_on, mask_off = flat_mask("MaskOn", True), flat_mask("MaskOff", False)
        views = None
        capped = not cheerleader and n % CAP_EVERY == 1
        done = {}
        for k, p in enumerate(POSES):
            which = DANCE[k % len(DANCE)] if cheerleader else p
            if which in done:
                # A dance step already taken: the same pictures again.
                for view in VIEWS:
                    for kind in ("", "_mask"):
                        shutil.copy(os.path.join(tmp, "%s_%s%s%s.png" % (name, done[which], view, kind)), os.path.join(tmp, "%s_%s%s%s.png" % (name, p, view, kind)))
                continue
            done[which] = p
            pose(arm, which, up, right, forward)
            # The person stands where the file puts him (feet on the ground; seated, at seat
            # height in his picture). (Moving the armature to put a seated man's feet on the
            # ground did nothing for Rocketbox's people: rendering plays the file's animation,
            # which sets its place back — and the props, placed from the moved bones, were left
            # floating.)
            things = props_for(arm, which, up, right, forward, cheerleader) + (cap_for(arm, up, forward) if capped else [])
            if views is None:
                # A cheerleader's picture covers more (her arms and pom-poms reach wide): the
                # game draws her card that much bigger (crowd_atlas.txt cheer_scale).
                span = FRAME_HEIGHT_M * (CHEER_SCALE if cheerleader else 1.0)
                views = {"": camera_and_light(scene, forward, span * 0.5, "Front", span),
                         "_back": camera_and_light(scene, -forward, span * 0.5, "Back", span)}
            for view in VIEWS:
                cam, sun = views[view]
                scene.camera = cam
                for other, (_, other_sun) in views.items():
                    other_sun.hide_render = other != view
                for m in meshes:
                    for i, mat in enumerate(materials[m.name]):
                        m.data.materials[i] = mat
                kept = [(t, t.data.materials[0]) for t in things]
                render_to(os.path.join(tmp, "%s_%s%s.png" % (name, p, view)))
                # The mask: white where a club's colour goes (the top it dyes), black elsewhere
                # (skin, hair, trousers, shoes all hide what is behind them).
                for m in meshes:
                    dyed = "top" in m.data.attributes
                    for i in range(len(m.data.materials)):
                        m.data.materials[i] = mask if dyed else mask_off
                for t in things:
                    t.data.materials[0] = mask_on if t["dyed"] else mask_off
                render_to(os.path.join(tmp, "%s_%s%s_mask.png" % (name, p, view)))
                for t, m in kept:
                    t.data.materials[0] = m
            for t in things:
                bpy.data.objects.remove(t, do_unlink=True)
        print("make_crowd:", name, "done")
    folders = [None] * fans_count
    fans = len(folders)

    # The fronts first (person by person, pose by pose), then the backs in the same order.
    rows = math.ceil(len(VIEWS) * len(names) * len(POSES) / COLUMNS)
    atlas = np.zeros((rows * FRAME_H, COLUMNS * FRAME_W, 4), dtype=np.float32)
    masks = np.zeros((rows * FRAME_H, COLUMNS * FRAME_W, 4), dtype=np.float32)
    for v, view in enumerate(VIEWS):
      for n, name in enumerate(names):
        for k, p in enumerate(POSES):
            f = (v * len(names) + n) * len(POSES) + k
            col, row = f % COLUMNS, f // COLUMNS
            for kind, target in ((view, atlas), (view + "_mask", masks)):
                img = bpy.data.images.load(os.path.join(tmp, "%s_%s%s.png" % (name, p, kind)))
                px = np.array(img.pixels[:], dtype=np.float32).reshape(FRAME_H, FRAME_W, 4)
                # Blender's pixels run bottom-up; the atlas is written bottom-up too.
                y0 = (rows - 1 - row) * FRAME_H
                target[y0:y0 + FRAME_H, col * FRAME_W:(col + 1) * FRAME_W] = px
                bpy.data.images.remove(img)
    for kind, data in (("crowd_atlas", atlas), ("crowd_mask", masks)):
        img = bpy.data.images.new(kind, COLUMNS * FRAME_W, rows * FRAME_H, alpha=True)
        img.pixels = data.ravel()
        img.filepath_raw = os.path.join(OUT, kind + ".png")
        img.file_format = 'PNG'
        img.save()
    with open(os.path.join(OUT, "crowd_atlas.txt"), "w") as f:
        f.write("cheer_scale %.2f\n" % CHEER_SCALE)
        f.write("names %s\n" % " ".join(names))
        f.write("people %d\nfans %d\nposes %s\ncolumns %d\nrows %d\nframe %d %d\nheight_m %.2f\nviews %d\n" % (
            len(names), fans, " ".join(POSES), COLUMNS, rows, FRAME_W, FRAME_H, FRAME_HEIGHT_M, len(VIEWS)))
    print("make_crowd: wrote", os.path.join(OUT, "crowd_atlas.png"), len(names), "people")


main()
