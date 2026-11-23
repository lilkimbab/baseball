"""Softens the baked uniform fold maps: the cloth simulation settles into many
fine pleats, which baked as is came out as thin sharp lines, dark curves on the trousers like a
pattern rather than folds. The shade is blurred over about a centimetre and halved in depth;
the normals are blurred a little less, so the broad folds stay and the pleats soften.

make_player.py calls soften() after each fold bake. To redo existing maps:
    blender -b --python tools/blender/fold_maps.py -- <..._folds.png> [...]
(each with its ..._shade.png beside it).
"""
import os
import sys

import bpy
import numpy as np

SHADE_RADIUS = 6      # pixels of a 1024 map (about 1 cm on the trousers)
SHADE_DEPTH = 0.55    # how much of the baked darkening is kept
NORMAL_RADIUS = 2


def _box(a, r):
    for axis in (0, 1):
        pad = [(0, 0)] * a.ndim
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
        n = a.shape[axis]
        a = (np.take(c, range(2 * r + 1, 2 * r + 1 + n), axis=axis) - np.take(c, range(0, n), axis=axis)) / (2 * r + 1)
    return a


def _load(path):
    image = bpy.data.images.load(path, check_existing=False)
    image.colorspace_settings.name = "Non-Color"
    px = np.empty(image.size[0] * image.size[1] * 4, dtype=np.float32)
    image.pixels.foreach_get(px)
    return image, px.reshape(image.size[1], image.size[0], 4)


def _store(image, px, path):
    image.pixels.foreach_set(px.ravel())
    image.filepath_raw = path
    image.file_format = 'PNG'
    image.save()
    bpy.data.images.remove(image)


def soften(folds_png):
    shade_png = folds_png.replace("_folds.png", "_shade.png")
    if os.path.exists(shade_png):
        image, px = _load(shade_png)
        shade = px[..., 0]
        # Only inside the garment's islands (the background is white): blur, keep part.
        soft = _box(_box(shade, SHADE_RADIUS), SHADE_RADIUS)
        soft = 1.0 - SHADE_DEPTH * (1.0 - soft)
        for c in range(3):
            px[..., c] = soft
        _store(image, px, shade_png)
    image, px = _load(folds_png)
    n = px[..., :3] * 2.0 - 1.0
    for c in range(3):
        n[..., c] = _box(_box(n[..., c], NORMAL_RADIUS), NORMAL_RADIUS)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    px[..., :3] = n * 0.5 + 0.5
    _store(image, px, folds_png)
    print("fold_maps: softened", folds_png)


if __name__ == "__main__":
    for path in sys.argv[sys.argv.index("--") + 1:]:
        soften(os.path.abspath(path))
