class_name AiPitcher
extends RefCounted
## Minimal pitcher for stage S3: mixes pitch types and works the edges of the zone.
## Count-based sequencing and batter weaknesses come with the full AI in stage S5.

## Share of pitches aimed inside the strike zone.
const ZONE_RATE := 0.78


static func choose(catalog: Dictionary[StringName, PitchType], zone: StrikeZone, rng: Rng) -> PitchDecision:
	var ids: Array[StringName] = [&"four_seam", &"slider", &"changeup", &"curve", &"two_seam"]
	var weights := PackedFloat64Array([0.46, 0.20, 0.14, 0.10, 0.10])
	var choice := PitchDecision.new()
	choice.type = catalog[ids[rng.pick_weighted(weights)]]
	if rng.chance(ZONE_RATE):
		choice.target = zone.point(lerpf(0.18, 0.82, _edge(rng)), lerpf(0.18, 0.82, _edge(rng)))
	else:
		var u := rng.next_range(-0.25, 1.25)
		var v := rng.next_range(-0.3, 1.3)
		if u > 0.0 and u < 1.0 and v > 0.0 and v < 1.0:
			v = -0.25 if rng.chance(0.6) else 1.25
		choice.target = zone.point(u, v)
	choice.quality = rng.next_range(0.55, 1.0)
	choice.effort = rng.next_range(0.97, 1.0)
	return choice


## A position across the zone that favours the edges over the middle.
static func _edge(rng: Rng) -> float:
	var x := rng.next_float()
	return 0.5 + 0.5 * signf(x - 0.5) * sqrt(absf(2.0 * x - 1.0))
