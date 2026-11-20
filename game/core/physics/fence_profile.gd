class_name FenceProfile
extends RefCounted
## Outfield fence between the foul poles: distance from home and height by azimuth.
## Azimuth is in degrees, 0 = dead centre, negative = left field, range -45..+45.
## Distance is a smooth curve through the control points; height is constant from one
## control point to the next, like the wall sections of a real park.

var _az: PackedFloat32Array = PackedFloat32Array()
var _dist: PackedFloat32Array = PackedFloat32Array()
var _height: PackedFloat32Array = PackedFloat32Array()


## Adds a control point. Points must be added in increasing azimuth.
func add_point(az_deg: float, distance: float, height: float) -> FenceProfile:
	_az.append(az_deg)
	_dist.append(distance)
	_height.append(height)
	return self


## A symmetric park from three numbers.
static func symmetric(corner: float, alley: float, center: float, height: float) -> FenceProfile:
	var fence := FenceProfile.new()
	fence.add_point(-45.0, corner, height)
	fence.add_point(-22.5, alley, height)
	fence.add_point(0.0, center, height)
	fence.add_point(22.5, alley, height)
	fence.add_point(45.0, corner, height)
	return fence


func distance_at(az_deg: float) -> float:
	var n := _az.size()
	if n == 0:
		return 0.0
	if az_deg <= _az[0]:
		return _dist[0]
	if az_deg >= _az[n - 1]:
		return _dist[n - 1]
	var i := _segment(az_deg)
	var span := _az[i + 1] - _az[i]
	var t := (az_deg - _az[i]) / span
	var m0 := _slope(i) * span
	var m1 := _slope(i + 1) * span
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * _dist[i] + (t3 - 2.0 * t2 + t) * m0 \
		+ (-2.0 * t3 + 3.0 * t2) * _dist[i + 1] + (t3 - t2) * m1


func height_at(az_deg: float) -> float:
	var n := _az.size()
	if n == 0:
		return 0.0
	if az_deg >= _az[n - 1]:
		return _height[n - 2] if n > 1 else _height[0]
	if az_deg <= _az[0]:
		return _height[0]
	return _height[_segment(az_deg)]


func min_distance() -> float:
	var lowest := INF
	for step: int in 181:
		lowest = minf(lowest, distance_at(-45.0 + float(step) * 0.5))
	return lowest


func _segment(az_deg: float) -> int:
	var i := 0
	while i < _az.size() - 2 and az_deg >= _az[i + 1]:
		i += 1
	return i


## Finite-difference slope at a control point (Catmull-Rom style tangent).
func _slope(i: int) -> float:
	var n := _az.size()
	if n < 2:
		return 0.0
	if i <= 0:
		return (_dist[1] - _dist[0]) / (_az[1] - _az[0])
	if i >= n - 1:
		return (_dist[n - 1] - _dist[n - 2]) / (_az[n - 1] - _az[n - 2])
	return (_dist[i + 1] - _dist[i - 1]) / (_az[i + 1] - _az[i - 1])
