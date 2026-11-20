class_name AnalyticField
extends CollisionProvider
## The playing field as geometry computed from a few numbers: flat ground, the outfield
## fence, the walls along foul territory and the backstop. Used for headless simulation and
## tests; the match scene uses engine colliders built from the same stadium definition.
##
## The boundary is stored as a radial table around home plate (the field is star-shaped as
## seen from home), sampled every half degree.

const SAMPLES := 720
const STEP_DEG := 360.0 / SAMPLES
const SIDE_WALL_HEIGHT := 1.2
const BACKSTOP_HEIGHT := 9.0

## Grass type of the park: &"grass" or &"turf".
var ground_surface: StringName = &"grass"
var warning_track_width := 4.5

var _radius: PackedFloat32Array = PackedFloat32Array()
var _height: PackedFloat32Array = PackedFloat32Array()
var _surface: Array[StringName] = []
var _min_radius := 0.0
var _min_fence := 0.0


## backstop = distance from home to the backstop; foul_width_* = distance from the foul line
## to the side wall, level with the bases and at the foul pole.
static func create(fence: FenceProfile, backstop: float = 16.5, foul_width_base: float = 14.0,
		foul_width_pole: float = 4.0, grass: StringName = &"grass") -> AnalyticField:
	var field := AnalyticField.new()
	field.ground_surface = grass
	field._build(fence, backstop, foul_width_base, foul_width_pole)
	return field


func boundary_distance(az_deg: float) -> float:
	return _radius[_index(az_deg)]


func boundary_height(az_deg: float) -> float:
	return _height[_index(az_deg)]


func sweep(from: Vector3, to: Vector3, radius: float) -> SweepHit:
	var best: SweepHit = null
	if to.z < radius and from.z > to.z and from.z >= radius - 1e-4:
		var f := clampf((from.z - radius) / (from.z - to.z), 0.0, 1.0)
		var at := from.lerp(to, f)
		at.z = radius
		best = SweepHit.make(f, at, Vector3(0.0, 0.0, 1.0), surface_at(at))

	var reach := maxf(from.x * from.x + from.y * from.y, to.x * to.x + to.y * to.y)
	var near := _min_radius - radius - 1.0
	if reach > near * near:
		var wall := _sweep_boundary(from, to, radius)
		if wall != null and (best == null or wall.fraction < best.fraction):
			best = wall
	return best


func surface_at(p: Vector3) -> StringName:
	var r2 := p.x * p.x + p.y * p.y
	var track_start := _min_fence - warning_track_width
	if r2 > track_start * track_start and Field.is_fair(p):
		var az := rad_to_deg(Field.azimuth(p))
		if sqrt(r2) > _radius[_index(az)] - warning_track_width:
			return &"track"

	var home_dx := p.x
	var home_dy := p.y - 0.2
	if home_dx * home_dx + home_dy * home_dy < 3.96 * 3.96:
		return &"dirt"
	var rubber_dy := p.y - Field.RUBBER_Y
	var in_arc := p.x * p.x + rubber_dy * rubber_dy <= Field.INFIELD_ARC_RADIUS * Field.INFIELD_ARC_RADIUS
	if not in_arc or p.y < absf(p.x) - 3.0:
		return ground_surface
	var in_diamond := absf(p.x) + absf(p.y - Field.BASE_DIAGONAL) < Field.BASE_DIAGONAL - 1.0
	if not in_diamond:
		return &"dirt"
	var mound_dy := p.y - Field.MOUND_CENTER_Y
	if p.x * p.x + mound_dy * mound_dy < Field.MOUND_RADIUS * Field.MOUND_RADIUS:
		return &"dirt"
	return ground_surface


func is_out_of_play(p: Vector3) -> bool:
	var az := rad_to_deg(Field.azimuth(p))
	var limit := _radius[_index(az)]
	return p.x * p.x + p.y * p.y > limit * limit


func _index(az_deg: float) -> int:
	return posmod(roundi(az_deg / STEP_DEG), SAMPLES)


func _sample_point(i: int) -> Vector2:
	var az := deg_to_rad(float(i) * STEP_DEG)
	var r := _radius[posmod(i, SAMPLES)]
	return Vector2(r * sin(az), r * cos(az))


func _sweep_boundary(from: Vector3, to: Vector3, radius: float) -> SweepHit:
	var centre := _index(rad_to_deg(Field.azimuth(to)))
	var best: SweepHit = null
	for offset: int in range(-2, 2):
		var i := centre + offset
		var a := _sample_point(i)
		var b := _sample_point(i + 1)
		var along := b - a
		var length := along.length()
		if length < 1e-6:
			continue
		along /= length
		var inward := Vector2(-along.y, along.x)
		if inward.dot(-a) < 0.0:
			inward = -inward
		var s0 := (Vector2(from.x, from.y) - a).dot(inward) - radius
		var s1 := (Vector2(to.x, to.y) - a).dot(inward) - radius
		if s0 < 0.0 or s1 >= 0.0:
			continue
		var f := s0 / (s0 - s1)
		var at := from.lerp(to, f)
		var across := (Vector2(at.x, at.y) - a).dot(along)
		if across < -radius or across > length + radius:
			continue
		if at.z > _height[posmod(i, SAMPLES)]:
			continue
		if best == null or f < best.fraction:
			best = SweepHit.make(f, at, Vector3(inward.x, inward.y, 0.0), _surface[posmod(i, SAMPLES)])
	return best


func _build(fence: FenceProfile, backstop: float, width_base: float, width_pole: float) -> void:
	_radius.resize(SAMPLES)
	_height.resize(SAMPLES)
	_surface.resize(SAMPLES)
	_min_fence = fence.min_distance()

	var corner := fence.distance_at(45.0)
	var s := sqrt(0.5)
	# Wall along right-field foul territory, in the x >= 0 half; the left side mirrors it.
	var out := Vector2(s, -s)
	var pole := Vector2(corner * s, corner * s)
	var wall: PackedVector2Array = PackedVector2Array([
		pole,
		pole + out * width_pole,
		Vector2(Field.BASE_DIAGONAL, Field.BASE_DIAGONAL) + out * width_base,
		out * backstop,
	])

	for i: int in SAMPLES:
		var az := float(i) * STEP_DEG
		if az > 180.0:
			az -= 360.0
		var side := absf(az)
		if side <= 45.0:
			_radius[i] = fence.distance_at(az)
			_height[i] = fence.height_at(az)
			_surface[i] = &"wall_pad"
		elif side < 135.0:
			var dir := Vector2(sin(deg_to_rad(side)), cos(deg_to_rad(side)))
			_radius[i] = _ray_to_polyline(dir, wall, backstop)
			_height[i] = SIDE_WALL_HEIGHT
			_surface[i] = &"wall_hard"
		else:
			_radius[i] = backstop
			_height[i] = BACKSTOP_HEIGHT
			_surface[i] = &"net"

	_min_radius = INF
	for r: float in _radius:
		_min_radius = minf(_min_radius, r)


## Distance from the origin along `dir` to the nearest segment of the polyline.
static func _ray_to_polyline(dir: Vector2, points: PackedVector2Array, fallback: float) -> float:
	var nearest := INF
	for i: int in points.size() - 1:
		var a := points[i]
		var e := points[i + 1] - a
		var denom := dir.x * e.y - dir.y * e.x
		if absf(denom) < 1e-9:
			continue
		var t := (a.x * e.y - a.y * e.x) / denom
		var u := (a.x * dir.y - a.y * dir.x) / denom
		if t > 0.0 and u >= -1e-6 and u <= 1.0 + 1e-6:
			nearest = minf(nearest, t)
	return fallback if nearest == INF else nearest
