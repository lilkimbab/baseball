"""Builds the crowd's picture atlas from Microsoft Rocketbox people (MIT licence).

    blender -b --python tools/blender/make_crowd.py -- <rocketbox folder> <out folder>

Each person in the folder (one sub-folder each: the FBX and its textures, as in the
Rocketbox repository's Assets/Avatars/Adults/<name>/Export and Textures) is posed four ways —
seated, standing, standing with both arms up (cheering), seated clapping — and photographed
from in front against nothing. The pictures go side by side into crowd_atlas.png (8 columns:
two people a row, their four poses each) with a second atlas, crowd_mask.png, white where the
person wears his top: the game dyes that part in the club's colour for the cheering sections
(docs/13 S14). Pictures are FRAME_W x FRAME_H pixels and cover FRAME_HEIGHT_M metres.
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SOURCE = ARGS[0] if ARGS else "content-local/rocketbox"
OUT = ARGS[1] if len(ARGS) > 1 else "game/assets/crowd"
FRAME_W = 128
FRAME_H = 256
FRAME_HEIGHT_M = 2.0
# Eight ways of sitting and standing a row (one person a row of the atlas): people in a
# crowd are never all in one attitude. (With four, and "standing" a soldier at attention,
# the stands looked like ranks of mannequins.)
POSES = ["seated", "seated_lean", "seated_arms", "clapping", "standing", "standing_clap", "cheering", "cheer_one"]
COLUMNS = 8
# Bones whose skin is the top (shirt, jacket): dyed in the club's colour.
TOP_BONES = ("Spine", "Spine1", "Spine2", "L Clavicle", "R Clavicle", "L UpperArm", "R UpperArm")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


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


def frame_axes(arm):
    """World up, the person's right and forward, from the eyes."""
    bpy.context.view_layer.update()
    mw = arm.matrix_world
    pb = arm.pose.bones
    l_eye = mw @ pb["Bip01 LEye"].head
    r_eye = mw @ pb["Bip01 REye"].head
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


def aim(arm, bone, direction):
    """Turns a pose bone so its limb (joint to next joint) points along `direction` (world),
    children following."""
    bpy.context.view_layer.update()
    pb = arm.pose.bones[bone]
    if bone in SPINE_NEXT:
        child = arm.pose.bones.get(SPINE_NEXT[bone])
        if child is None:
            return
    else:
        side, part = bone.split(" ")[1], bone.split(" ")[-1]
        child = arm.pose.bones["Bip01 %s %s" % (side, NEXT[part])]
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
    seated = which in ("seated", "seated_lean", "seated_arms", "clapping")
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


def lowest_point(mesh):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(deps)
    m = ev.to_mesh()
    z = min((mesh.matrix_world @ v.co).z for v in m.vertices)
    ev.to_mesh_clear()
    return z


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


def mark_top(mesh):
    """A per-vertex 'top' attribute: 1 where the strongest bone is one of TOP_BONES."""
    groups = {g.index: g.name for g in mesh.vertex_groups}
    values = []
    for v in mesh.data.vertices:
        best, weight = "", 0.0
        for g in v.groups:
            if g.weight > weight:
                best, weight = groups.get(g.group, ""), g.weight
        values.append(1.0 if any(best.endswith(b) for b in TOP_BONES) else 0.0)
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


def camera_and_light(scene, forward, height_mid):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = FRAME_HEIGHT_M
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = forward * 6.0 + Vector((0.0, 0.0, height_mid))
    cam.rotation_euler = (-forward).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    sun_data = bpy.data.lights.new("Sun", 'SUN')
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("Sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (forward + Vector((0.3, 0.0, 1.2))).normalized().to_track_quat('-Z', 'Y').to_euler()
    return cam


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    # Folders whose name starts with "_" are left out.
    folders = sorted(os.path.join(SOURCE, d) for d in os.listdir(SOURCE)
                     if os.path.isdir(os.path.join(SOURCE, d)) and not d.startswith("_"))
    tmp = os.path.join(OUT, "_frames")
    os.makedirs(tmp, exist_ok=True)
    names = []
    for folder in folders:
        reset()
        name, arm, mesh = load_person(folder)
        names.append(name)
        mark_top(mesh)
        scene = bpy.context.scene
        setup_render(scene)
        up, right, forward = frame_axes(arm)
        materials = list(mesh.data.materials)
        mask = top_mask_material()
        cam = None
        for p in POSES:
            pose(arm, p, up, right, forward)
            # Feet on the ground at z = 0, the frame from the ground up.
            low = lowest_point(mesh)
            arm.location.z -= low
            bpy.context.view_layer.update()
            if cam is None:
                cam = camera_and_light(scene, forward, FRAME_HEIGHT_M * 0.5)
            for i in range(len(materials)):
                mesh.data.materials[i] = materials[i]
            render_to(os.path.join(tmp, "%s_%s.png" % (name, p)))
            for i in range(len(materials)):
                mesh.data.materials[i] = mask
            render_to(os.path.join(tmp, "%s_%s_mask.png" % (name, p)))
            arm.location.z += low
        print("make_crowd:", name, "done")

    rows = math.ceil(len(names) * len(POSES) / COLUMNS)
    atlas = np.zeros((rows * FRAME_H, COLUMNS * FRAME_W, 4), dtype=np.float32)
    masks = np.zeros((rows * FRAME_H, COLUMNS * FRAME_W, 4), dtype=np.float32)
    for n, name in enumerate(names):
        for k, p in enumerate(POSES):
            f = n * len(POSES) + k
            col, row = f % COLUMNS, f // COLUMNS
            for kind, target in (("", atlas), ("_mask", masks)):
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
        f.write("people %d\nposes %s\ncolumns %d\nrows %d\nframe %d %d\nheight_m %.2f\n" % (
            len(names), " ".join(POSES), COLUMNS, rows, FRAME_W, FRAME_H, FRAME_HEIGHT_M))
    print("make_crowd: wrote", os.path.join(OUT, "crowd_atlas.png"), len(names), "people")


main()
