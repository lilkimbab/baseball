"""Tries body-shape settings and prints the measurements, without building the whole model.

    blender -b --python tools/blender/try_shapes.py -- [build] [out.png]
    SHAPE='{"head-scale-vert-incr": 0.1}' MACRO='{"muscle": 1.0}' ... to override make_player's.
    A value of null removes a setting.

With an output path it also renders the bare body from the front and the side (flat, no
perspective) so its outline can be laid over a photograph.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anthropometry  # noqa: E402
import make_player as mp  # noqa: E402

from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402
from bl_ext.user_default.mpfb.services.targetservice import TargetService  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
BUILD = ARGS[0] if ARGS else "standard"
OUT = ARGS[1] if len(ARGS) > 1 else None


def build_body():
    mp.clear_scene()
    macro = TargetService.get_default_macro_info_dict()
    macro.update(mp.MACRO)
    macro.update(mp.BUILDS.get(BUILD, {}))
    macro.update(json.loads(os.environ.get("MACRO", "{}")))
    macro["race"] = dict(mp.RACE)
    shape = dict(mp.SHAPE)
    shape.update(mp.BUILD_SHAPE.get(BUILD, {}) if hasattr(mp, "BUILD_SHAPE") else {})
    shape.update(json.loads(os.environ.get("SHAPE", "{}")))
    body = HumanService.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True,
                                     feet_on_ground=False, scale=0.1, macro_detail_dict=macro)
    for name, weight in shape.items():
        if weight is not None:
            TargetService.load_target(body, TargetService.target_full_path(name), weight=weight, name=name)
    rig = HumanService.add_builtin_rig(body, "game_engine", import_weights=True)
    TargetService.bake_targets(body)
    mp.stand_on_ground(body, rig)
    return body, rig


def outline(body, path):
    """Front and side views without perspective, one image each."""
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'SINGLE'
    scene.display.shading.single_color = (0.75, 0.6, 0.5)
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = 700, 1200
    top = max(v.co.z for v in body.data.vertices)
    cam = bpy.data.objects.new("OutlineCam", bpy.data.cameras.new("OutlineCam"))
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = top * 1.08
    scene.collection.objects.link(cam)
    scene.camera = cam
    for suffix, at in (("_front", Vector((0.0, -6.0, top * 0.5))), ("_side", Vector((6.0, 0.0, top * 0.5)))):
        cam.location = at
        cam.rotation_euler = (Vector((0.0, 0.0, top * 0.5)) - at).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.splitext(path)[0] + suffix + ".png"
        bpy.ops.render.render(write_still=True)
        print("try_shapes: wrote", scene.render.filepath)


def main():
    body, rig = build_body()
    top = max(v.co.z for v in body.data.vertices)
    marks = mp.body_marks(body, top)
    numbers = anthropometry.measure(body, rig, marks, bpy)
    for line in anthropometry.report(numbers):
        print("try_shapes:", line)
    if os.environ.get("ALL"):
        print("try_shapes: all", json.dumps({k: round(v, 4) for k, v in numbers.items()}, sort_keys=True))
    if os.environ.get("PROFILE"):
        # The face's outline down the middle (y forward is negative), from the brow to the neck.
        skin = anthropometry._weights(body, "body")
        mid = sorted(((round(v.co.z, 3), round(v.co.y, 3)) for v in body.data.vertices
                      if skin[v.index] > 0.5 and abs(v.co.x) < 0.006 and v.co.z > top - 0.36 and v.co.y < marks["ear"].y + 0.02),
                     reverse=True)
        print("try_shapes: profile (z, y)", mid)
        print("try_shapes: marks", {k: (tuple(round(c, 3) for c in v) if hasattr(v, "x") else round(v, 3)) for k, v in marks.items()})
        print("try_shapes: neck bone z %.3f head bone z %.3f" % (rig.data.bones["neck_01"].head_local.z, rig.data.bones["head"].head_local.z))
    if OUT:
        for modifier in list(body.modifiers):
            if modifier.type == 'MASK':
                modifier.show_render = True
        outline(body, OUT)


main()
