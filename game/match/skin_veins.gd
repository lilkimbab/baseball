class_name SkinVeins
extends RefCounted
## The veins and tendons that show under the skin of a ballplayer's arms and hands (docs/13 S11-3;
## the user: "the veins on the arms are too artificial ... model them finely, as in life").
##
## One thick cord winding from elbow to wrist reads as a cable under rubber. In life the
## superficial veins of the arm are a network: two long veins that start from the arch on the
## back of the hand and wind round the forearm (the cephalic on the thumb side, the basilic on
## the little-finger side), a short oblique one joining them across the hollow of the elbow
## (the median cubital), fainter ones up the middle of the inner forearm and over its back that
## run into them, and the cephalic going on up the outer groove of the biceps. They are four
## to six millimetres wide and well under a millimetre proud, they wander, and they come and
## go along their length as the flesh over them thickens. Tendons are different: straight,
## broad, and only where the skin is thin (the back of the hand to each knuckle, the inside of
## the wrist).
##
## The arms' part of the skin texture is too coarse to hold any of that (a texel is 1.4 mm), so
## the skin shader draws them from the arm's own coordinates, which the model carries on every
## vertex (tools/blender/make_player.py, store_limb_coordinates):
##   t      -1 at the shoulder, 0 at the elbow, 1 at the wrist, 2 at the knuckles;
##   angle  round the arm (rad), arms down with the thumbs forward: 0 in front (the thumb side
##          of the forearm, the biceps), + outward (the back of the forearm), - inward (its
##          inner, flexor side); pi is the back of the arm (the little-finger side);
##   u      on the back of the hand, metres across it from its middle, + toward the index finger.
## This class holds where they run and packs it into a small table the shader reads.

## Each vein of the arm: its path as [t, angle] points (angles may run past pi: they wrap), how
## much it wanders (rad), its half-width (m), its height (0..1 of HEIGHT), and how well it
## shows along its length as [t, 0..1] points.
const ARM: Array[Dictionary] = [
	{"name": "cephalic", "wander": 0.07, "half": 0.003, "height": 0.62,
		"path": [[-1.0, 0.55], [-0.7, 0.75], [-0.3, 0.7], [0.0, 0.3], [0.12, 0.15], [0.35, -0.05], [0.6, 0.1], [0.82, 0.4], [1.0, 0.65]],
		"show": [[-0.9, 0.0], [-0.5, 0.35], [-0.15, 0.55], [0.05, 0.85], [0.3, 0.7], [0.55, 0.6], [0.8, 0.9], [1.0, 0.85]]},
	{"name": "basilic", "wander": 0.06, "half": 0.0028, "height": 0.5,
		"path": [[-0.45, 4.9], [-0.2, 4.75], [0.05, 4.35], [0.25, 3.95], [0.5, 3.5], [0.75, 2.95], [1.0, 2.5]],
		"show": [[-0.42, 0.0], [-0.2, 0.5], [0.08, 0.8], [0.4, 0.55], [0.7, 0.45], [1.0, 0.65]]},
	{"name": "median cubital", "wander": 0.03, "half": 0.003, "height": 0.6,
		"path": [[-0.03, -1.85], [0.0, -1.5], [0.1, -0.6], [0.19, 0.02]],
		"show": [[-0.03, 0.0], [0.0, 0.85], [0.16, 0.85], [0.19, 0.0]]},
	{"name": "median antebrachial", "wander": 0.08, "half": 0.0023, "height": 0.42,
		"path": [[0.1, -0.85], [0.22, -1.2], [0.45, -1.42], [0.72, -1.6], [0.97, -1.45]],
		"show": [[0.1, 0.0], [0.14, 0.5], [0.35, 0.28], [0.6, 0.3], [0.8, 0.6], [0.97, 0.5]]},
	{"name": "wrist tributary", "wander": 0.04, "half": 0.002, "height": 0.36,
		"path": [[0.73, -1.6], [0.86, -1.82], [0.99, -1.95]],
		"show": [[0.73, 0.0], [0.86, 0.5], [0.99, 0.3]]},
	{"name": "accessory cephalic", "wander": 0.07, "half": 0.0023, "height": 0.4,
		"path": [[0.13, 0.3], [0.3, 0.75], [0.52, 1.15], [0.78, 1.5]],
		"show": [[0.13, 0.0], [0.2, 0.55], [0.4, 0.5], [0.68, 0.35], [0.78, 0.0]]},
	{"name": "dorsal ulnar", "wander": 0.05, "half": 0.0021, "height": 0.36,
		"path": [[0.77, 2.8], [0.88, 2.1], [1.0, 1.75]],
		"show": [[0.77, 0.0], [0.88, 0.4], [1.0, 0.45]]},
]
## The back of the hand: veins between the knuckles run back to an arch across the hand, and
## the arch's two ends run on to the wrist (into the cephalic and the basilic). Paths are
## [th, u] with th 0 at the wrist and 1 at the knuckles.
const HAND: Array[Dictionary] = [
	{"height": 0.55, "path": [[0.47, 0.0135], [0.7, 0.017], [0.92, 0.0185]], "show": [[0.47, 0.9], [0.8, 0.8], [0.92, 0.0]]},
	{"height": 0.5, "path": [[0.48, 0.001], [0.68, 0.002], [0.9, 0.0005]], "show": [[0.48, 0.9], [0.78, 0.7], [0.9, 0.0]]},
	{"height": 0.5, "path": [[0.44, -0.0135], [0.68, -0.0165], [0.92, -0.018]], "show": [[0.44, 0.9], [0.8, 0.7], [0.92, 0.0]]},
	{"height": 0.6, "path": [[0.0, 0.027], [0.25, 0.024], [0.46, 0.0195]], "show": [[0.0, 0.8], [0.46, 0.9]]},
	{"height": 0.5, "path": [[0.0, -0.023], [0.2, -0.021], [0.42, -0.0175]], "show": [[0.0, 0.7], [0.42, 0.9]]},
]
const ROWS := 16
const COLUMNS := 256

static var _table: ImageTexture


## The table the skin shader reads (match/skin.gdshader): a row for each vein, along it t from
## -1 to 1 (the hand's veins: th from 0 to 1). R the path (angle in rad, or u in m), G how well
## it shows times its height, B the path's slope (per unit of t), A its half-width (mm).
static func table() -> ImageTexture:
	if _table != null:
		return _table
	var image := Image.create(COLUMNS, ROWS, false, Image.FORMAT_RGBAF)
	for row: int in ARM.size():
		_fill(image, row, ARM[row], -1.0, 1.0, float(ARM[row]["half"]) * 1000.0)
	for i: int in HAND.size():
		_fill(image, ARM.size() + i, HAND[i], 0.0, 1.0, 1.6)
	_table = ImageTexture.create_from_image(image)
	return _table


## A vein's path and how it shows at a place along it: [value, shown], shown 0 beyond its ends.
static func sample(vein: Dictionary, t: float) -> Vector2:
	var path: Array = vein["path"]
	if t < float(path[0][0]) or t > float(path[path.size() - 1][0]):
		return Vector2(_curve(path, clampf(t, float(path[0][0]), float(path[path.size() - 1][0]))), 0.0)
	return Vector2(_curve(path, t), _curve(vein["show"], t) * float(vein["height"]))


static func _fill(image: Image, row: int, vein: Dictionary, from: float, to: float, half_mm: float) -> void:
	for x: int in COLUMNS:
		var t := lerpf(from, to, (x + 0.5) / COLUMNS)
		var here := sample(vein, t)
		var step := (to - from) / COLUMNS
		var slope := (sample(vein, t + step).x - sample(vein, t - step).x) / (2.0 * step)
		image.set_pixel(x, row, Color(here.x, here.y, slope, half_mm))


## A smooth curve through [x, y] points (x rising): Catmull-Rom between them, flat beyond.
static func _curve(points: Array, x: float) -> float:
	var n := points.size()
	if x <= float(points[0][0]):
		return float(points[0][1])
	if x >= float(points[n - 1][0]):
		return float(points[n - 1][1])
	var i := 0
	while i < n - 2 and x > float(points[i + 1][0]):
		i += 1
	var x0 := float(points[i][0])
	var x1 := float(points[i + 1][0])
	var f := (x - x0) / (x1 - x0)
	var y0 := float(points[i][1])
	var y1 := float(points[i + 1][1])
	# Tangents from the neighbours (the ends' from their own segment).
	var before := float(points[maxi(i - 1, 0)][1])
	var before_x := float(points[maxi(i - 1, 0)][0])
	var after := float(points[mini(i + 2, n - 1)][1])
	var after_x := float(points[mini(i + 2, n - 1)][0])
	var m0 := (y1 - before) / maxf(x1 - before_x, 1e-6) * (x1 - x0)
	var m1 := (after - y0) / maxf(after_x - x0, 1e-6) * (x1 - x0)
	var f2 := f * f
	var f3 := f2 * f
	return (2.0 * f3 - 3.0 * f2 + 1.0) * y0 + (f3 - 2.0 * f2 + f) * m0 + (-2.0 * f3 + 3.0 * f2) * y1 + (f3 - f2) * m1
