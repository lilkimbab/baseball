class_name FieldingAlignment
extends RefCounted
## Where the nine fielders stand before a pitch (data/fielding_positions.json), adjusted for
## the situation and the batter, within the shift rule: two infielders on each side of second
## base, all four on the infield dirt.

const VARIANTS: Array[String] = ["double_play", "infield_in", "no_doubles", "bunt"]

## Position code -> (distance from home, direction in degrees).
var spots: Dictionary[String, Vector2] = {}
## "variant:code" -> (change in distance, change in direction).
var shifts: Dictionary[String, Vector2] = {}
## Where the first baseman stands holding a runner on: (distance, direction).
var hold_first := Vector2(27.4, 44.0)
var pull_shift := 3.0
var outfield_margin := 8.0


static func polar(distance: float, degrees: float) -> Vector2:
	var r := deg_to_rad(degrees)
	return Vector2(distance * sin(r), distance * cos(r))


## Which variants apply now.
static func variants_for(state: GameState, expect_bunt: bool) -> Array[String]:
	var on: Array[String] = []
	var late_close := state.inning >= state.rules.innings - 1 and absi(state.lead_of(state.fielding())) <= 1
	if state.outs < 2 and not state.base_empty(1):
		on.append("double_play")
	if state.outs < 2 and not state.base_empty(3) and late_close:
		on.append("infield_in")
	if late_close and state.inning >= state.rules.innings and state.lead_of(state.fielding()) >= 1:
		on.append("no_doubles")
	if expect_bunt:
		on.append("bunt")
	return on


## Positions on the field (x, y) for the coming pitch. `orders` replaces the usual
## positioning with the manager's (Tactics.defence).
func positions(state: GameState, fence: FenceProfile, bats_left: bool, expect_bunt: bool = false, orders: Tactics = null) -> Dictionary[Position.Kind, Vector2]:
	var on := orders.variants(state, expect_bunt) if orders != null else variants_for(state, expect_bunt)
	var out: Dictionary[Position.Kind, Vector2] = {}
	for code: String in spots:
		var kind := Position.from_code(code)
		var spot: Vector2 = spots[code]
		for variant: String in on:
			spot += shifts.get("%s:%s" % [variant, code], Vector2.ZERO)
		if Position.INFIELD.has(kind) or Position.OUTFIELD.has(kind):
			# Lean toward the batter's pull side: a left-handed batter pulls to first base.
			spot.y += pull_shift if bats_left else -pull_shift
		if Position.OUTFIELD.has(kind) and fence != null:
			spot.x = minf(spot.x, fence.distance_at(spot.y) - outfield_margin)
		out[kind] = polar(spot.x, spot.y)
	if not state.base_empty(1) and state.base_empty(2) and not expect_bunt:
		out[Position.Kind.B1] = polar(hold_first.x, hold_first.y)
	return out


## The shift rule: when the pitch is thrown, two infielders stand on each side of second base
## and all four are on the infield dirt.
static func legal(positions: Dictionary[Position.Kind, Vector2]) -> bool:
	var left := 0
	var right := 0
	for kind: Position.Kind in Position.INFIELD:
		var p := positions[kind]
		if p.x < 0.0:
			left += 1
		else:
			right += 1
		# The infield dirt reaches 95 ft from the front of the pitcher's plate.
		if p.distance_to(Vector2(0.0, Field.RUBBER_Y)) > Field.INFIELD_ARC_RADIUS:
			return false
	return left == 2 and right == 2
