class_name ClubRules
extends RefCounted
## The numbers of club management (data/club.ko.json):
## grades and costs, the first-team cost cap, condition, scouting, training, points, traits
## and team colours. Read by ClubIO.


class Grade:
	var name := "D"
	var min_ovr := 0.0
	var cost := 1


class TraitDef:
	var id := ""
	var name := ""
	## &"batter" or &"pitcher".
	var kind: StringName = &"batter"
	var effect: Dictionary[String, float] = {}
	var note := ""


class ColorDef:
	var id := ""
	var name := ""
	## What is counted: &"batter", &"starter", &"reliever", &"homegrown", &"developed".
	var need_kind: StringName = &"batter"
	var rating := ""
	var at_least := 0.0
	var grade_at_least := ""
	var count := 0
	## Steps for a colour that grows (franchise): 10, 15, 20 players → bonus × 1, 2, 3.
	var steps := PackedInt32Array()
	var bonus: Dictionary[String, float] = {}
	## Who gets it: &"batter", &"starter", &"reliever", &"all", &"club".
	var to: StringName = &"batter"


var grades: Array[Grade] = []
var cost_caps := PackedInt32Array([90, 75, 60])
var condition_levels := PackedStringArray(["최악", "나쁨", "보통", "좋음", "최상"])
var condition_effect := PackedFloat64Array([-0.06, -0.03, 0.0, 0.03, 0.06])
var condition_change := 0.35
var toward_normal := 0.65
var streak_games := 8
var streak_drop := 0.06
var scout_candidates := 5
var scout_talent := PackedFloat64Array([55.0, 50.0, 45.0])
var scout_spread := 8.0
var scout_level_bonus := 2.5
var scout_max_level := 3
var second_team_size := 34
var train_per_day := 3
var train_gain := 0.3
## (age up to, value) rows, youngest first.
var age_rates: Array[Vector2] = []
var headroom: Array[Vector2] = []
var focus: Dictionary[String, PackedStringArray] = {}
var points: Dictionary[String, int] = {}
## Club points to raise the scouting level to 2, to 3.
var scout_upgrade := PackedInt32Array([600, 1200])
var trait_tiers := PackedFloat64Array([1.0, 1.75, 2.5])
var traits: Array[TraitDef] = []
var colors: Array[ColorDef] = []
var color_limit := 2
var color_cap := 5.0


const NORMAL := 2


func grade_of(ovr: float) -> Grade:
	for g: Grade in grades:
		if ovr >= g.min_ovr:
			return g
	return grades[-1]


func grade_rank(name: String) -> int:
	for i: int in grades.size():
		if grades[i].name == name:
			return i
	return grades.size()


## A player's overall: as a pitcher, or at his main position.
static func player_ovr(p: Player, ovr: Overall, catalog: Dictionary[StringName, PitchType]) -> float:
	if p.is_pitcher():
		return Overall.pitcher(p, catalog)
	return ovr.batter(p, p.primary_position())


## Total cost of the first team (1군).
func first_team_cost(team: Team, ovr: Overall, catalog: Dictionary[StringName, PitchType]) -> int:
	var total := 0
	for p: Player in team.first_team():
		total += grade_of(player_ovr(p, ovr, catalog)).cost
	return total


## Cost cap for a division (0 the top).
func cost_cap(division: int) -> int:
	return cost_caps[clampi(division, 0, cost_caps.size() - 1)]


## A value from an (age, value) table: the first row whose age is at least `age`.
static func by_age(table: Array[Vector2], age: int) -> float:
	for row: Vector2 in table:
		if age <= int(row.x):
			return row.y
	return table[-1].y if not table.is_empty() else 0.0


func trait_index(id: String) -> int:
	for i: int in traits.size():
		if traits[i].id == id:
			return i
	return -1
