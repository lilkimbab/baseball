class_name Player
extends RefCounted
## One player: who he is, how he plays, and how he looks. Read and written by RosterIO.

var id := ""
var name := ""
var number := 0
var born := 2000
## &"R", &"L" or &"S" (switch hitter).
var bats: StringName = &"R"
## &"R" or &"L".
var throws: StringName = &"R"
var height_cm := 183.0
var weight_kg := 88.0
## Position code ("SS", "SP", ...) -> aptitude 0..100.
var positions: Dictionary[String, float] = {}
var batting := BattingRatings.new()
var fielding := FieldingRatings.new()
## Null for a position player.
var pitching: PitchingRatings
## Form ids for motion: "batting", "pitching".
var forms: Dictionary[String, String] = {}


func is_pitcher() -> bool:
	return pitching != null


## &"SP", &"RP" or &"" for a position player.
func role() -> StringName:
	if positions.has("SP"):
		return &"SP"
	if positions.has("RP") or is_pitcher():
		return &"RP"
	return &""


## Main position: the one with the highest aptitude.
func primary_position() -> Position.Kind:
	var best := ""
	var best_value := -1.0
	for code: String in positions:
		if positions[code] > best_value:
			best = code
			best_value = positions[code]
	return Position.from_code(best) if best != "" else Position.Kind.DH


## How well he plays a position, 0..1. Anyone can be a designated hitter; nobody untrained
## can catch or pitch.
func aptitude(kind: Position.Kind) -> float:
	if kind == Position.Kind.DH or kind == Position.Kind.PH or kind == Position.Kind.PR:
		return 1.0
	var code := Position.code(kind)
	if kind == Position.Kind.P:
		return 1.0 if is_pitcher() else 0.0
	if positions.has(code):
		return positions[code] / 100.0
	if kind == Position.Kind.C:
		return 0.0
	# Out of position: an outfielder anywhere in the outfield, anyone at first base.
	if kind == Position.Kind.B1:
		return 0.6
	if Position.OUTFIELD.has(kind):
		for other: Position.Kind in Position.OUTFIELD:
			if positions.has(Position.code(other)):
				return 0.7
	return 0.3


## Fielding ratings scaled by how well he knows the position: a player in a position he cannot
## play fields at half strength, a non-catcher catching at 30%.
func fielding_at(kind: Position.Kind) -> float:
	var fit := aptitude(kind)
	if kind == Position.Kind.C and fit <= 0.0:
		fit = 0.3
	return fielding.overall() * lerpf(0.5, 1.0, clampf(fit, 0.0, 1.0))


## The side he bats from against a pitcher: a switch hitter takes the opposite side.
func batting_side(pitcher_throws: StringName) -> StringName:
	if bats == &"S":
		return &"L" if pitcher_throws == &"R" else &"R"
	return bats
