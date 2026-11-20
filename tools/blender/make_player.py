"""Builds the base player model and exports it as glTF for the game.

Run through ./dev model, or directly:
    blender -b --python tools/blender/make_player.py -- <out.glb> [preview.png]

A human body is generated with MPFB (MakeHuman), rigged, given a painted-on uniform by
assigning materials per body region, fitted with a cap, and its bones are renamed to the
names the game uses (Godot's humanoid profile). The output of MakeHuman/MPFB is CC0.
"""
import math
import sys

import bmesh
import bpy
from mathutils import Vector

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_GLB = ARGS[0] if ARGS else "player_base.glb"
PREVIEW = ARGS[1] if len(ARGS) > 1 else None

# Body shape: an athletic adult man.
MACRO = {"gender": 1.0, "age": 0.5, "muscle": 0.64, "weight": 0.56, "height": 0.6, "proportions": 0.55}
RACE = {"asian": 1.0, "caucasian": 0.0, "african": 0.0}

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

# Material slots, in order. Colours are placeholders: the game recolours jersey, pants,
# socks and cap per team.
MATERIALS = [
    ("Skin", (0.80, 0.60, 0.46)), ("Jersey", (0.92, 0.92, 0.94)), ("Pants", (0.88, 0.88, 0.90)),
    ("Shoes", (0.05, 0.05, 0.06)), ("Belt", (0.04, 0.04, 0.05)), ("Socks", (0.10, 0.15, 0.35)),
    ("Cap", (0.10, 0.15, 0.35)),
]
SLOT = {name: i for i, (name, _) in enumerate(MATERIALS)}
# How far each clothed region is pushed out from the skin (metres).
PUFF = {"Jersey": 0.009, "Pants": 0.007, "Shoes": 0.006, "Belt": 0.011, "Socks": 0.002}


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def make_material(name, rgb):
    mat = bpy.data.materials.new(name)
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.55 if name == "Skin" else 0.8
    mat.use_backface_culling = name != "Cap"
    return mat


def along_bone(rig, bone_name, point):
    """0 at the bone's joint, 1 at the next joint down the limb. The child's position is
    used rather than the bone's own tail, which in this rig does not reach the next joint."""
    child = {"upperarm": "lowerarm", "calf": "foot", "thigh": "calf", "lowerarm": "hand"}
    stem, side = bone_name.rsplit("_", 1)
    start = rig.data.bones[bone_name].head_local
    end = rig.data.bones["%s_%s" % (child[stem], side)].head_local
    axis = end - start
    return (point - start).dot(axis) / axis.length_squared


def region_of(bone_name, point, rig, waist_z):
    if bone_name in ("head", "neck_01"):
        return "Skin"
    if bone_name.startswith(("spine_", "clavicle_")) or bone_name == "pelvis":
        if abs(point.z - waist_z) < 0.03:
            return "Belt"
        return "Jersey" if point.z > waist_z else "Pants"
    if bone_name.startswith("upperarm_"):
        return "Jersey" if along_bone(rig, bone_name, point) < 0.58 else "Skin"
    if bone_name.startswith("thigh_"):
        return "Pants"
    if bone_name.startswith("calf_"):
        return "Pants" if along_bone(rig, bone_name, point) < 0.42 else "Socks"
    if bone_name.startswith(("foot_", "ball_")):
        return "Shoes"
    return "Skin"


def stand_on_ground(body, rig):
    """Moves the rig (and the mesh parented to it) so the soles are at height zero, then
    bakes the move into both so the exported skeleton has its origin on the ground."""
    bpy.context.view_layer.update()
    body_group = body.vertex_groups["body"].index
    lowest = min((body.matrix_world @ v.co).z for v in body.data.vertices
                 if any(g.group == body_group and g.weight > 0.5 for g in v.groups))
    rig.location.z -= lowest
    bpy.context.view_layer.update()
    for obj in bpy.data.objects:
        obj.select_set(obj in (body, rig))
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.update()
    knee = (rig.matrix_world @ rig.data.bones["calf_l"].head_local).z
    ankle = (rig.matrix_world @ rig.data.bones["foot_l"].head_local).z
    print("make_player: moved up %.3f m; knee at %.3f m, ankle at %.3f m" % (-lowest, knee, ankle))


def dress(body, rig):
    """Removes MakeHuman's helper geometry, then paints and pads the uniform."""
    for modifier in list(body.modifiers):
        if modifier.type == 'MASK':
            body.modifiers.remove(modifier)

    # Material slots must exist before faces are given indices into them.
    body.data.materials.clear()
    for name, rgb in MATERIALS:
        body.data.materials.append(make_material(name, rgb))

    bone_of_group = {g.index: g.name for g in body.vertex_groups if g.name in rig.data.bones}
    body_group = body.vertex_groups["body"].index
    waist_z = rig.data.bones["spine_01"].head_local.z + 0.035

    bm = bmesh.new()
    bm.from_mesh(body.data)
    deform = bm.verts.layers.deform.verify()
    helpers = [v for v in bm.verts if v[deform].get(body_group, 0.0) < 0.5]
    bmesh.ops.delete(bm, geom=helpers, context='VERTS')
    bm.normal_update()

    # The rig's origin is at the pelvis while the mesh stands on the ground, so vertex
    # positions are converted to the rig's space before being compared with bones.
    bpy.context.view_layer.update()
    to_rig = rig.matrix_world.inverted() @ body.matrix_world
    print("make_player: rig origin at height %.3f m" % rig.matrix_world.translation.z)
    region = {}
    for v in bm.verts:
        best, best_w = "head", 0.0
        for group, weight in v[deform].items():
            if group in bone_of_group and weight > best_w:
                best, best_w = bone_of_group[group], weight
        region[v.index] = region_of(best, to_rig @ v.co, rig, waist_z)
    for v in bm.verts:
        v.co += v.normal * PUFF.get(region[v.index], 0.0)
    for face in bm.faces:
        votes = {}
        for v in face.verts:
            votes[region[v.index]] = votes.get(region[v.index], 0) + 1
        face.material_index = SLOT[max(votes, key=votes.get)]
        face.smooth = True

    head = [v.co.copy() for v in bm.verts if any(bone_of_group.get(g) == "head" and w > 0.6 for g, w in v[deform].items())]
    counts = {}
    for face in bm.faces:
        counts[face.material_index] = counts.get(face.material_index, 0) + 1
    print("make_player: faces per material", {MATERIALS[i][0]: n for i, n in sorted(counts.items())})
    bm.to_mesh(body.data)
    bm.free()
    return head


def make_cap(head_points, rig):
    """A simple fitted cap: a dome over the skull and a brim over the eyes."""
    xs = [p.x for p in head_points]
    ys = [p.y for p in head_points]
    zs = [p.z for p in head_points]
    top = max(zs)
    height = top - min(zs)
    rx = (max(xs) - min(xs)) * 0.5 + 0.010
    ry = (max(ys) - min(ys)) * 0.5 + 0.010
    rz = height * 0.40
    centre = Vector(((max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5, top - rz + 0.012))

    bm = bmesh.new()
    rings, segments = 7, 20
    rows = []
    for r in range(rings + 1):
        phi = (math.pi * 0.5 + 0.22) * r / rings          # 0 at the crown, past the equator at the rim
        row = []
        for s in range(segments):
            theta = 2.0 * math.pi * s / segments
            row.append(bm.verts.new(centre + Vector((rx * math.sin(phi) * math.cos(theta),
                                                     ry * math.sin(phi) * math.sin(theta),
                                                     rz * math.cos(phi)))))
        rows.append(row)
    for r in range(rings):
        for s in range(segments):
            n = (s + 1) % segments
            bm.faces.new((rows[r][s], rows[r][n], rows[r + 1][n], rows[r + 1][s]))

    # Brim: a curved strip in front of the face (-Y is forward in Blender).
    brim_z = centre.z + rz * math.cos(math.pi * 0.5 + 0.12)
    inner, outer = [], []
    for i in range(11):
        a = math.radians(-70.0 + 14.0 * i)
        inner.append(bm.verts.new(Vector((centre.x + rx * 0.98 * math.sin(a), centre.y - ry * 0.98 * math.cos(a), brim_z))))
        reach = 0.075 * math.cos(a) ** 0.6
        outer.append(bm.verts.new(Vector((centre.x + (rx + 0.012) * math.sin(a), centre.y - (ry * math.cos(a) + reach), brim_z - 0.012))))
    for i in range(10):
        bm.faces.new((inner[i], inner[i + 1], outer[i + 1], outer[i]))
    for face in bm.faces:
        face.smooth = True

    mesh = bpy.data.meshes.new("Cap")
    bm.to_mesh(mesh)
    bm.free()
    cap = bpy.data.objects.new("Cap", mesh)
    bpy.context.scene.collection.objects.link(cap)
    return cap


def join_cap(body, cap, rig):
    for name, _ in MATERIALS:
        cap.data.materials.append(bpy.data.materials[name])
    for poly in cap.data.polygons:
        poly.material_index = SLOT["Cap"]
    group = cap.vertex_groups.new(name="head")
    group.add(list(range(len(cap.data.vertices))), 1.0, 'REPLACE')
    with bpy.context.temp_override(active_object=body, object=body, selected_editable_objects=[body, cap], selected_objects=[body, cap]):
        bpy.ops.object.join()


def render_preview(path, target_z):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x, scene.render.resolution_y = 900, 760
    world = bpy.data.worlds.new("Preview")
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
    macro["race"] = dict(RACE)
    # feet_on_ground is left off: it moves the mesh but not the rig that is fitted afterwards.
    # Both are moved to the ground together below.
    body = HumanService.create_human(mask_helpers=True, detailed_helpers=False, extra_vertex_groups=True,
                                     feet_on_ground=False, scale=0.1, macro_detail_dict=macro)
    rig = HumanService.add_builtin_rig(body, "game_engine", import_weights=True)
    TargetService.bake_targets(body)
    stand_on_ground(body, rig)

    head_points = dress(body, rig)
    join_cap(body, make_cap(head_points, rig), rig)
    for old, new in BONE_NAMES.items():
        if old in rig.data.bones:
            rig.data.bones[old].name = new
    body.name = body.data.name = "Player"
    rig.name = rig.data.name = "PlayerRig"

    height = max(v.co.z for v in body.data.vertices)
    print("make_player: height %.3f m, %d vertices, %d faces, %d bones" % (
        height, len(body.data.vertices), len(body.data.polygons), len(rig.data.bones)))

    for obj in bpy.data.objects:
        obj.select_set(obj in (body, rig))
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', use_selection=True, export_apply=False,
                              export_yup=True, export_skins=True, export_animations=False, export_morph=False)
    print("make_player: wrote", OUT_GLB)
    if PREVIEW:
        render_preview(PREVIEW, height * 0.5)
        print("make_player: preview", PREVIEW)


main()
