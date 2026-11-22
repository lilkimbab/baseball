"""Builds the equipment to real sizes: fielder's glove, catcher's mitt, bat and ball.

    blender -b --python tools/blender/make_props.py -- game/assets/props

Sizes follow the playing rules and common equipment:
  ball   circumference 9 to 9 1/4 in  -> diameter 73.2 mm
  bat    33.5 in long, barrel 2.61 in at most, handle about 1 in  -> 0.851 m, 66 mm, 25 mm
  glove  12 in from heel to the tip of the index finger (a pitcher's or infielder's glove)
  mitt   catcher's mitt, 33 in pattern  -> about 0.33 m tall and 0.27 m wide

Gloves are modelled for the left hand in the hand's own frame, which is how the game places
them: origin at the knuckle of the middle finger, X across the palm (the thumb is at -X),
Y along the fingers, Z out of the palm. A hand is about 0.107 m from wrist to that knuckle
and 0.09 m from there to the fingertips, so a 12 in glove reaches some 0.11 m past them.

Shapes are built from overlapping rounded blobs that a voxel remesh fuses into one skin.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "props"
BALL_RADIUS = 0.0366
BAT_LENGTH = 0.851


def hand_to_blender(x, y, z):
    """Hand frame (across, along the fingers, out of the palm) to Blender axes, chosen so that
    the glTF exporter's Y-up conversion gives the hand frame back."""
    return Vector((x, -z, y))


def blob(bm, centre, radii):
    """An ellipsoid given in the hand frame."""
    matrix = Matrix.Translation(hand_to_blender(*centre)) @ Matrix.Diagonal((radii[0], radii[2], radii[1], 1.0))
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0, matrix=matrix)


def tube(bm, start, end, r0, r1, flat=1.0, steps=7):
    """A row of blobs from start to end; flat < 1 thins it through the palm."""
    for i in range(steps + 1):
        f = i / steps
        centre = [start[k] + (end[k] - start[k]) * f for k in range(3)]
        r = r0 + (r1 - r0) * f
        blob(bm, centre, (r, r, r * flat))


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def fused(name, bm, pocket, length, voxel=0.0045, keep=0.22):
    """Fuses the blobs, presses the pocket in, smooths, and scales to the stated length."""
    rough = new_object(name + "Rough", bm)
    remesh = rough.modifiers.new("Fuse", 'REMESH')
    remesh.mode = 'VOXEL'
    remesh.voxel_size = voxel
    cutter = None
    if pocket:
        ball = bmesh.new()
        blob(ball, pocket[0], (pocket[1],) * 3)
        cutter = new_object(name + "Pocket", ball)
        cut = rough.modifiers.new("Pocket", 'BOOLEAN')
        cut.operation = 'DIFFERENCE'
        cut.object = cutter
    smooth = rough.modifiers.new("Smooth", 'SMOOTH')
    smooth.factor = 0.7
    smooth.iterations = 10
    thin = rough.modifiers.new("Thin", 'DECIMATE')
    thin.ratio = keep
    mesh = bpy.data.meshes.new_from_object(rough.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    mesh.name = name
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    # Heel at the wrist, tip at the stated length: scale about the origin (the knuckle).
    zs = [v.co.z for v in mesh.vertices]
    scale = length / (max(zs) - min(zs))
    for v in mesh.vertices:
        v.co *= scale
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.data.objects.remove(rough)
    if cutter:
        bpy.data.objects.remove(cutter)
    print("make_props: %s  %d faces, %.3f m long, %.3f m wide, %.3f m deep" % (
        name, len(mesh.polygons), length,
        (max(v.co.x for v in mesh.vertices) - min(v.co.x for v in mesh.vertices)),
        (max(v.co.y for v in mesh.vertices) - min(v.co.y for v in mesh.vertices))))
    return obj


def material(name, colour, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*colour, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    return mat


def make_glove():
    """A 12 inch fielder's glove: four finger stalls, a thumb, the web between thumb and index
    finger, a rolled heel, and a pocket under the index finger."""
    bm = bmesh.new()
    blob(bm, (0.0, -0.045, 0.0), (0.078, 0.072, 0.03))                     # palm and back of the hand
    tube(bm, (-0.040, 0.00, 0.0), (-0.064, 0.195, 0.05), 0.022, 0.018, 0.8)   # index
    tube(bm, (-0.012, 0.00, 0.0), (-0.018, 0.200, 0.055), 0.022, 0.018, 0.8)  # middle
    tube(bm, (0.016, 0.00, 0.0), (0.028, 0.190, 0.05), 0.022, 0.018, 0.8)     # ring
    tube(bm, (0.044, -0.01, 0.0), (0.074, 0.165, 0.04), 0.022, 0.019, 0.8)    # little
    tube(bm, (-0.060, -0.075, 0.0), (-0.128, 0.085, 0.045), 0.027, 0.021, 0.85)  # thumb
    for centre in ((-0.094, 0.055, 0.03), (-0.094, 0.095, 0.038), (-0.09, 0.135, 0.046)):  # web
        blob(bm, centre, (0.034, 0.03, 0.011))
    tube(bm, (-0.062, -0.097, 0.012), (0.062, -0.097, 0.012), 0.022, 0.022)    # heel
    glove = fused("Glove", bm, ((-0.035, 0.045, 0.085), 0.064), 0.305)
    glove.data.materials.append(material("Leather", (0.33, 0.18, 0.08), 0.6))
    return glove


def make_outfield_glove():
    """An outfielder's glove (docs/13 S11-8): 12.75 inches, longer finger stalls and a deeper
    web than an infielder's 12 inch one, for reach."""
    bm = bmesh.new()
    blob(bm, (0.0, -0.045, 0.0), (0.078, 0.072, 0.03))
    tube(bm, (-0.040, 0.00, 0.0), (-0.068, 0.215, 0.05), 0.022, 0.017, 0.8)
    tube(bm, (-0.012, 0.00, 0.0), (-0.020, 0.222, 0.055), 0.022, 0.017, 0.8)
    tube(bm, (0.016, 0.00, 0.0), (0.030, 0.212, 0.05), 0.022, 0.017, 0.8)
    tube(bm, (0.044, -0.01, 0.0), (0.078, 0.185, 0.04), 0.022, 0.018, 0.8)
    tube(bm, (-0.060, -0.075, 0.0), (-0.134, 0.095, 0.045), 0.027, 0.021, 0.85)
    for centre in ((-0.098, 0.06, 0.03), (-0.098, 0.105, 0.04), (-0.094, 0.15, 0.048), (-0.088, 0.185, 0.05)):
        blob(bm, centre, (0.036, 0.032, 0.011))
    tube(bm, (-0.062, -0.097, 0.012), (0.062, -0.097, 0.012), 0.022, 0.022)
    glove = fused("OutfieldGlove", bm, ((-0.036, 0.05, 0.09), 0.068), 0.324)
    glove.data.materials.append(material("Leather", (0.33, 0.18, 0.08), 0.6))
    return glove


def make_first_base_mitt():
    """A first baseman's mitt: 12.5 inches long, no separate fingers, a long scoop with a
    wide web, palm no wider than 8 inches."""
    bm = bmesh.new()
    blob(bm, (0.0, 0.02, -0.004), (0.085, 0.15, 0.022))
    for i in range(14):
        a = math.tau * i / 14
        blob(bm, (math.cos(a) * 0.08, 0.03 + math.sin(a) * 0.145, 0.018), (0.028, 0.03, 0.028))
    tube(bm, (-0.045, -0.105, 0.0), (0.045, -0.105, 0.0), 0.026, 0.026, 0.8)
    mitt = fused("FirstBaseMitt", bm, ((-0.005, 0.06, 0.09), 0.075), 0.3175, keep=0.2)
    mitt.data.materials.append(material("Leather", (0.33, 0.18, 0.08), 0.6))
    return mitt


def make_mitt():
    """A catcher's mitt: a thick padded rim round a deep pocket, with no separate fingers; the
    rim one even roll (thicker at the thumb and the heel), a web across the gap between the
    thumb and the fingers, the crease it folds on across the heel."""
    bm = bmesh.new()
    blob(bm, (-0.01, 0.04, -0.008), (0.112, 0.132, 0.02))                   # back and pocket floor
    for i in range(54):                                                     # padded rim
        a = math.tau * i / 54
        # Thicker down the thumb side and round the heel; a notch where the web is.
        thick = 0.031 + 0.006 * max(math.cos(a - math.radians(200.0)), 0.0) + 0.004 * max(math.cos(a - math.radians(270.0)), 0.0)
        if abs(math.atan2(math.sin(a - math.radians(128.0)), math.cos(a - math.radians(128.0)))) < math.radians(13.0):
            thick *= 0.55
        blob(bm, (-0.01 + math.cos(a) * 0.106, 0.04 + math.sin(a) * 0.13, 0.018), (thick, thick, thick * 0.92))
    # The web: a flat panel inside the rim at the notch.
    blob(bm, (-0.01 + math.cos(math.radians(128.0)) * 0.082, 0.04 + math.sin(math.radians(128.0)) * 0.1, 0.012), (0.034, 0.04, 0.009))
    tube(bm, (-0.05, -0.1, 0.0), (0.05, -0.1, 0.0), 0.03, 0.03, 0.8)        # heel, where the hand goes in
    mitt = fused("Mitt", bm, ((-0.012, 0.05, 0.1), 0.085), 0.33, voxel=0.0036, keep=0.2)
    mitt.data.materials.append(material("Leather", (0.3, 0.17, 0.08), 0.78))
    return mitt


def make_bat():
    """A wooden bat turned from its profile: knob, thin handle, taper, barrel, rounded end.
    It lies along the up axis, centred, with the knob at the bottom."""
    profile = [  # distance from the knob end, radius (m)
        (0.000, 0.000), (0.000, 0.021), (0.004, 0.0252), (0.014, 0.0252), (0.022, 0.017), (0.034, 0.0127),
        (0.20, 0.0125), (0.30, 0.0132), (0.40, 0.0158), (0.48, 0.0198), (0.56, 0.0255), (0.63, 0.0305),
        (0.70, 0.0328), (0.80, 0.0331), (0.832, 0.0318), (0.845, 0.026), (0.851, 0.014), (0.851, 0.000),
    ]
    sides = 20
    bm = bmesh.new()
    rings = []
    for along, radius in profile:
        z = along - BAT_LENGTH * 0.5
        if radius == 0.0:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            rings.append([bm.verts.new((math.cos(math.tau * k / sides) * radius, math.sin(math.tau * k / sides) * radius, z)) for k in range(sides)])
    for lower, upper in zip(rings, rings[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            if len(lower) == 1:
                bm.faces.new((lower[0], upper[j], upper[k]))
            elif len(upper) == 1:
                bm.faces.new((lower[k], lower[j], upper[0]))
            else:
                bm.faces.new((lower[k], lower[j], upper[j], upper[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for face in bm.faces:
        face.smooth = True
    bat = new_object("Bat", bm)
    bat.data.materials.append(material("Wood", (0.72, 0.55, 0.34), 0.45))
    print("make_props: Bat  %d faces, %.3f m long, barrel %.1f mm, handle %.1f mm" % (len(bat.data.polygons), BAT_LENGTH, 66.2, 25.0))
    return bat


def make_ball_texture(path, width=1024, height=512):
    """White leather with the two-piece cover's seam and its red stitches, as a picture that
    wraps round a sphere (longitude across, latitude down)."""
    # The seam is one closed curve on the sphere. This form stays exactly on the unit sphere.
    a, b = 0.7, 0.3
    c = 2.0 * math.sqrt(a * b)
    t = np.linspace(0.0, math.tau, 1440, endpoint=False)
    curve = np.stack([a * np.cos(t) + b * np.cos(3 * t), c * np.sin(2 * t), a * np.sin(t) - b * np.sin(3 * t)], axis=1)
    step = np.linalg.norm(np.roll(curve, -1, axis=0) - curve, axis=1)
    along_mm = np.cumsum(step) * BALL_RADIUS * 1000.0

    lon = (np.arange(width) + 0.5) / width * math.tau
    pixels = np.empty((height, width, 4), dtype=np.float32)
    leather = np.array([0.93, 0.92, 0.88, 1.0], dtype=np.float32)
    thread = np.array([0.72, 0.07, 0.07, 1.0], dtype=np.float32)
    crease = np.array([0.70, 0.69, 0.65, 1.0], dtype=np.float32)
    for row in range(height):
        lat = math.pi * 0.5 - (row + 0.5) / height * math.pi
        points = np.stack([math.cos(lat) * np.cos(lon), np.full(width, math.sin(lat)), math.cos(lat) * np.sin(lon)], axis=1)
        dots = points @ curve.T
        nearest = dots.argmax(axis=1)
        away_mm = np.arccos(np.clip(dots.max(axis=1), -1.0, 1.0)) * BALL_RADIUS * 1000.0
        line = np.tile(leather, (width, 1))
        # Stitches: short red threads either side of the seam, 108 pairs round the ball.
        stitch = (away_mm > 0.5) & (away_mm < 4.2) & ((along_mm[nearest] % (along_mm[-1] / 108.0)) < along_mm[-1] / 108.0 * 0.42)
        line[stitch] = thread
        line[away_mm <= 0.5] = crease
        pixels[height - 1 - row] = line  # image rows run bottom to top
    image = bpy.data.images.new("Ball", width, height, alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = path
    image.file_format = 'PNG'
    image.save()
    bpy.data.images.remove(image)
    print("make_props: ball texture", path)


def export(obj, name):
    for other in bpy.context.scene.objects:
        other.select_set(other == obj)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=False,
                              export_yup=True, export_skins=False, export_animations=False, export_morph=False)
    print("make_props: wrote", path)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    export(make_glove(), "glove")
    export(make_mitt(), "mitt")
    export(make_outfield_glove(), "outfield_glove")
    export(make_first_base_mitt(), "first_base_mitt")
    export(make_bat(), "bat")
    make_ball_texture(os.path.join(os.path.abspath(OUT), "ball.png"))


main()
