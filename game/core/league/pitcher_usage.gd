class_name PitcherUsage
extends RefCounted
## Who pitched when, and so who can pitch today (docs/13 S7-4).
##
## - Starters work every fifth or sixth day: they need STARTER_REST days off between starts.
## - Relievers: a second day in a row costs them (TIRED, ratings × TIRED_FORM); a third day in
##   a row is not allowed, nor the day after HEAVY pitches or more, nor two days after a long
##   outing (LONG pitches). Days are calendar days, so the Monday off breaks a run of days.

enum Status { FRESH, TIRED, REST }

const STARTER_REST := 4
const HEAVY := 30
const LONG := 50
const TIRED_FORM := 0.93
## Outings kept per pitcher (enough for the rules above).
const KEEP := 6

## Per pitcher: day and pitches of his last outings, oldest first.
var outings: Dictionary[String, Array] = {}


func note(id: String, day: int, pitches: int) -> void:
	if not outings.has(id):
		outings[id] = []
	var list: Array = outings[id]
	list.append(Vector2i(day, pitches))
	while list.size() > KEEP:
		list.pop_front()


func pitches_on(id: String, day: int) -> int:
	var total := 0
	for o: Vector2i in outings.get(id, []):
		if o.x == day:
			total += o.y
	return total


func last_day(id: String) -> int:
	var list: Array = outings.get(id, [])
	if list.is_empty():
		return -1000
	var last: Vector2i = list[-1]
	return last.x


## Days off since his last outing (yesterday's outing → 0).
func rest_days(id: String, today: int) -> int:
	return today - last_day(id) - 1


func can_start(id: String, today: int) -> bool:
	return rest_days(id, today) >= STARTER_REST


func reliever_status(id: String, today: int) -> Status:
	var yesterday := pitches_on(id, today - 1)
	var before := pitches_on(id, today - 2)
	if yesterday > 0 and before > 0:
		return Status.REST
	if yesterday >= HEAVY or before >= LONG:
		return Status.REST
	if yesterday > 0:
		return Status.TIRED
	return Status.FRESH


## Pitches over the last three days, for the bullpen board.
func recent_pitches(id: String, today: int) -> PackedInt32Array:
	return PackedInt32Array([pitches_on(id, today - 3), pitches_on(id, today - 2), pitches_on(id, today - 1)])
