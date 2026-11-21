class_name StadiumDef
extends RefCounted
## A ballpark (docs/06 6.1, docs/13 S13): its fence, foul ground, surface, which way it faces,
## its stands and what stands around it. The scene builds the park from it and the physics
## builds its collision model from the same numbers, so what is drawn is what the ball hits.

## The pattern the grass is mown in.
enum Mow { DIAGONAL, CHECKER, RINGS, STRAIGHT }

var id := ""
var name := ""
## &"grass" or &"turf" (artificial: dirt only in cut-outs round the bases, mound and plate).
var surface: StringName = &"grass"
## &"open" or &"dome".
var roof: StringName = &"open"
## Compass bearing (degrees from north, clockwise) from home plate toward the pitcher.
var orientation_deg := 60.0
## Fence points: azimuth (0 centre field, + toward right), distance (m), height (m).
var fence_points: Array[Vector3] = []
var backstop := 18.3
var foul_width_base := 14.0
var foul_width_pole := 4.0
var mow := Mow.DIAGONAL
## Where the bullpens are: &"outfield" (behind the fence, left and right) or &"foul" (along
## the lines, in play).
var bullpens: StringName = &"outfield"
## Outfield stands begin this far (m) behind the fence, leaving room for the bullpens.
var outfield_setback := 6.0
## Stand sections: from_az, to_az (degrees; from > to runs the long way round, through the
## seats behind home), rows of the lower and upper tiers (0 for none), rake (degrees) of
## each, and whether a roof covers the upper tier.
var stands: Array[Dictionary] = []
## &"hills", &"city", &"sea" or &"none": what is seen beyond the stands.
var backdrop: StringName = &"hills"
var wall_color := Color(0.06, 0.24, 0.18)
var seat_color := Color(0.18, 0.32, 0.55)
var capacity := 20000
## What the stands' outer walls are built of: &"concrete" or &"brick".
var facade: StringName = &"concrete"
## Where the light towers stand (compass bearings from home plate); empty for the usual six.
var towers := PackedFloat32Array()
## A building that belongs to the park itself: &"" or &"warehouse" (a long brick warehouse
## beyond right field).
var landmark: StringName = &""
## What the surroundings are laid out from (the park's id, or a club's, so that two clubs in
## parks of one model do not look out on the same streets).
var place_seed := ""


## The practice park the duel scene and the headless games have always used: 100 m lines,
## 116 m alleys, 122 m to centre, a 2.6 m wall, the default foul ground.
static func standard() -> StadiumDef:
	var s := StadiumDef.new()
	s.id = "standard"
	s.name = "연습 구장"
	for p: Vector2 in [Vector2(-45.0, 100.0), Vector2(-22.5, 116.0), Vector2(0.0, 122.0), Vector2(22.5, 116.0), Vector2(45.0, 100.0)]:
		s.fence_points.append(Vector3(p.x, p.y, 2.6))
	s.backstop = 16.5
	s.foul_width_base = 14.0
	s.foul_width_pole = 4.0
	s.bullpens = &"foul"
	s.outfield_setback = 0.5
	s.stands = [
		{"from_az": 46.0, "to_az": -46.0, "rows": [24], "rake_deg": [24]},
		{"from_az": -44.0, "to_az": 44.0, "rows": [14], "rake_deg": [22]},
	]
	return s


func fence() -> FenceProfile:
	var f := FenceProfile.new()
	for p: Vector3 in fence_points:
		f.add_point(p.x, p.y, p.z)
	return f


## The collision model for the physics, from the same fence and foul ground.
func analytic() -> AnalyticField:
	return AnalyticField.create(fence(), backstop, foul_width_base, foul_width_pole, surface)


static func from_dictionary(data: Dictionary) -> StadiumDef:
	var s := StadiumDef.new()
	s.id = str(data.get("id", ""))
	s.name = str(data.get("name", s.id))
	s.surface = StringName(str(data.get("surface", "grass")))
	s.roof = StringName(str(data.get("roof", "open")))
	s.orientation_deg = float(data.get("orientation_deg", 60.0))
	for p: Dictionary in data.get("fence", []):
		s.fence_points.append(Vector3(float(p["az"]), float(p["dist"]), float(p["height"])))
	var foul: Dictionary = data.get("foul_territory", {})
	s.backstop = float(foul.get("backstop", s.backstop))
	s.foul_width_base = float(foul.get("width_at_base", s.foul_width_base))
	s.foul_width_pole = float(foul.get("width_at_pole", s.foul_width_pole))
	s.mow = Mow.get(str(data.get("mow", "diagonal")).to_upper(), Mow.DIAGONAL)
	s.bullpens = StringName(str(data.get("bullpens", "outfield")))
	s.outfield_setback = float(data.get("outfield_setback", s.outfield_setback))
	for section: Dictionary in data.get("stands", []):
		s.stands.append(section)
	s.backdrop = StringName(str(data.get("backdrop", "hills")))
	if data.has("wall_color"):
		s.wall_color = Color(str(data["wall_color"]))
	if data.has("seat_color"):
		s.seat_color = Color(str(data["seat_color"]))
	s.capacity = int(data.get("capacity", s.capacity))
	s.facade = StringName(str(data.get("facade", "concrete")))
	for az: Variant in data.get("towers", []):
		s.towers.append(float(az))
	s.landmark = StringName(str(data.get("landmark", "")))
	s.place_seed = s.id
	return s
