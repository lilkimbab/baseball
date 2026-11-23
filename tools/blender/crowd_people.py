"""Korean-looking people for the crowd, made with MakeHuman (MPFB, CC0 assets) instead of taken
from Rocketbox's mostly Western cast (the user, 2026-11-23: "make the crowd and the cheerleaders
as Asian as you can, a very few Westerners mixed in"). Each is a body of an age, build and sex
with MakeHuman's Asian proportions and an Asian skin of that age, eyes, brows and lashes, a hair
style in black or near-black, a suit of casual or sports clothes and shoes, on MPFB's game-engine
rig. make_crowd.py poses and photographs them as it does the Rocketbox people.

Each spec: name, gender (0 woman, 1 man), age (MakeHuman: 0.5 is 25, 0.75 about 45, 0.9
about 65), weight, height, hair, suit, shoes.
"""
import os

import bpy

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.locationservice import LocationService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

FACE = [("eyes/low-poly/low-poly.mhclo", "Eyes"), ("eyebrows/eyebrow009/eyebrow009.mhclo", "Eyebrows"), ("eyelashes/eyelashes01/eyelashes01.mhclo", "Eyelashes")]

# The game-engine rig's bones by the Rocketbox (3ds Max biped) names the posing code uses.
BONES = {
    "Bip01 Pelvis": "pelvis", "Bip01 Spine": "spine_01", "Bip01 Spine1": "spine_02", "Bip01 Spine2": "spine_03",
    "Bip01 Neck": "neck_01", "Bip01 Head": "head",
}
for side, s in (("L", "l"), ("R", "r")):
    BONES.update({"Bip01 %s Thigh" % side: "thigh_" + s, "Bip01 %s Calf" % side: "calf_" + s, "Bip01 %s Foot" % side: "foot_" + s,
                  "Bip01 %s Toe0" % side: "ball_" + s, "Bip01 %s UpperArm" % side: "upperarm_" + s, "Bip01 %s Forearm" % side: "lowerarm_" + s,
                  "Bip01 %s Hand" % side: "hand_" + s, "Bip01 %s Clavicle" % side: "clavicle_" + s})
# The top a club's colour dyes (the shirt of the suit), and for a cheerleader her hips and thighs.
TOP = ("spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r")
CHEER_TOP = TOP + ("pelvis", "thigh_l", "thigh_r")

W_HAIR = ["bob01", "long01", "ponytail01", "bob02", "braid01", "short02", "long01", "bob01", "short04"]
W_SUIT = ["female_casualsuit01", "female_casualsuit02", "female_sportsuit01", "female_casualsuit02", "female_casualsuit01",
          "female_elegantsuit01", "female_casualsuit02", "female_sportsuit01", "female_casualsuit01"]
W_AGE = [0.48, 0.5, 0.52, 0.55, 0.5, 0.72, 0.78, 0.6, 0.9]
M_HAIR = ["short02", "short01", "short03", "short04", "short02", "short01", "short03", "short04", "short01"]
M_SUIT = ["male_casualsuit01", "male_casualsuit02", "male_casualsuit03", "male_casualsuit04", "male_casualsuit05",
          "male_casualsuit06", "male_worksuit01", "male_casualsuit03", "male_elegantsuit01"]
M_AGE = [0.5, 0.48, 0.55, 0.52, 0.72, 0.75, 0.8, 0.62, 0.9]


def specs():
    """The crowd's Korean people: nine women and nine men of all ages."""
    out = []
    for i in range(9):
        out.append({"name": "kr_w%02d" % (i + 1), "gender": 0.0, "age": W_AGE[i], "weight": 0.42 + 0.06 * (i % 4), "height": 0.4 + 0.05 * (i % 3),
                    "hair": W_HAIR[i], "suit": W_SUIT[i], "shoes": "shoes0%d" % (1 + i % 6)})
        out.append({"name": "kr_m%02d" % (i + 1), "gender": 1.0, "age": M_AGE[i], "weight": 0.45 + 0.07 * (i % 4), "height": 0.42 + 0.06 * (i % 3),
                    "hair": M_HAIR[i], "suit": M_SUIT[i], "shoes": "shoes0%d" % (1 + (i + 3) % 6)})
    return out


def cheerleader_specs():
    return [{"name": "kr_cheer1", "gender": 0.0, "age": 0.47, "weight": 0.38, "height": 0.52, "hair": "ponytail01", "suit": "female_sportsuit01", "shoes": "shoes02"},
            {"name": "kr_cheer2", "gender": 0.0, "age": 0.49, "weight": 0.38, "height": 0.5, "hair": "long01", "suit": "female_sportsuit01", "shoes": "shoes02"}]


def _skin(spec):
    sex = "female" if spec["gender"] < 0.5 else "male"
    age = "young" if spec["age"] < 0.65 else ("middleage" if spec["age"] < 0.85 else "old")
    return "skins/%s_asian_%s/%s_asian_%s.mhmat" % (age, sex, age, sex)


def _darken(obj, value):
    """Hair to black or near-black: the colour texture through a darkening step."""
    for slot in obj.material_slots:
        m = slot.material
        if m is None or not m.use_nodes:
            continue
        nodes = m.node_tree.nodes
        links = m.node_tree.links
        bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if bsdf is None:
            continue
        base = bsdf.inputs["Base Color"]
        if base.is_linked:
            src = base.links[0].from_socket
            hs = nodes.new("ShaderNodeHueSaturation")
            hs.inputs["Saturation"].default_value = 0.5
            hs.inputs["Value"].default_value = value
            links.new(src, hs.inputs["Color"])
            links.new(hs.outputs["Color"], base)
        else:
            base.default_value = (0.03, 0.025, 0.022, 1.0)


def build(spec, cheerleader=False):
    """Makes one person. Returns (name, armature, meshes, the bones to dye)."""
    data = LocationService.get_user_data()
    macro = TargetService.get_default_macro_info_dict()
    macro["gender"] = spec["gender"]
    macro["age"] = spec["age"]
    macro["weight"] = spec["weight"]
    macro["height"] = spec["height"]
    macro["muscle"] = 0.5
    macro["proportions"] = 0.5
    macro["race"] = {"asian": 1.0, "caucasian": 0.0, "african": 0.0}
    body = HumanService.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True, feet_on_ground=False, scale=0.1, macro_detail_dict=macro)
    rig = HumanService.add_builtin_rig(body, "game_engine", import_weights=True)
    skin = os.path.join(data, _skin(spec))
    if os.path.exists(skin):
        HumanService.set_character_skin(skin, body, skin_type="GAMEENGINE", material_instances=False)
    meshes = [body]
    for path, kind in FACE:
        full = os.path.join(data, path)
        if os.path.exists(full):
            meshes.append(HumanService.add_mhclo_asset(full, body, asset_type=kind, subdiv_levels=0, material_type="GAMEENGINE"))
    hair = os.path.join(data, "hair", spec["hair"], spec["hair"] + ".mhclo")
    if os.path.exists(hair):
        h = HumanService.add_mhclo_asset(hair, body, asset_type="Hair", subdiv_levels=0, material_type="MAKESKIN")
        _darken(h, 0.18 if sum(map(ord, spec["name"])) % 5 else 0.34)
        meshes.append(h)
    for kind, asset in (("Clothes", spec["suit"]), ("Clothes", spec["shoes"])):
        path = os.path.join(data, "clothes", asset, asset + ".mhclo")
        if os.path.exists(path):
            obj = HumanService.add_mhclo_asset(path, body, asset_type=kind, subdiv_levels=0, material_type="MAKESKIN")
            if asset == spec["suit"]:
                obj["dyed_top"] = True
            meshes.append(obj)
    TargetService.bake_targets(body)
    # Feet on the ground: the rig and all parented to it moved together, then applied.
    bpy.context.view_layer.update()
    lowest = min((body.matrix_world @ v.co).z for v in body.data.vertices)
    rig.location.z -= lowest
    bpy.context.view_layer.update()
    for obj in bpy.data.objects:
        obj.select_set(obj == rig or obj.parent == rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.update()
    return spec["name"], rig, [m for m in meshes if m is not None], CHEER_TOP if cheerleader else TOP
