class_name Overall
extends RefCounted
## One overall number per player (docs/07 section 4.2). Position players are weighted by what
## their position asks for; pitchers by stuff, control, speed, breaking balls and staying power.

const ABILITIES: Array[String] = ["contact", "power", "eye", "speed", "baserunning", "range", "hands", "arm", "accuracy"]
## Reference fastball speed for the league (km/h) and one standard deviation of it.
const FASTBALL_MEAN := 144.0
const FASTBALL_SD := 3.5

## Position code -> weight per ability in ABILITIES order. Weights add up to 1.
var weights: Dictionary[String, PackedFloat64Array] = {}


func batter(player: Player, kind: Position.Kind) -> float:
	var code := Position.code(kind)
	var w: PackedFloat64Array = weights.get(code, weights.get("DH", PackedFloat64Array()))
	if w.is_empty():
		return 50.0
	var b := player.batting
	var f := player.fielding
	var fit := lerpf(0.5, 1.0, clampf(player.aptitude(kind), 0.0, 1.0)) if Position.is_field(kind) else 1.0
	var values: Array[float] = [b.contact(), b.power(), b.eye, b.speed, b.baserunning, f.range * fit, f.hands * fit, f.arm * fit, f.accuracy * fit]
	var total := 0.0
	for i: int in values.size():
		total += w[i] * values[i]
	return total


static func pitcher(player: Player, catalog: Dictionary[StringName, PitchType]) -> float:
	var r := player.pitching
	if r == null:
		return 0.0
	var speed := 50.0 + 15.0 * (r.fastball_speed() - FASTBALL_MEAN) / FASTBALL_SD
	var lasting := r.stamina if player.role() == &"SP" else r.composure
	var variety := clampf(50.0 + 10.0 * (r.arsenal.size() - 3), 30.0, 80.0)
	return 0.30 * r.stuff(catalog) + 0.25 * r.control + 0.15 * speed + 0.10 * r.breaking(catalog) + 0.10 * lasting + 0.10 * variety
