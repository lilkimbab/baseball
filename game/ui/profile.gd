class_name Profile
extends RefCounted
## What belongs to the person playing, across every mode and save (docs/02): points earned by
## playing (the shop spends them), experience and the level it makes, lifetime numbers, the
## day's goals, and what has been bought. Kept in user://profile.json.

const PATH := "user://profile.json"
## Points and experience for a game played, and more for a win.
const GAME_POINTS := 60
const WIN_POINTS := 90
const GAME_XP := 40
const WIN_XP := 60
## Points for reaching a level: this times the level (the level meant nothing before).
const LEVEL_POINTS := 100
## The day's goals: three of these, chosen by the date. Each: id, words, the number counted
## (a key of `today`), how many, and the points it pays.
const GOALS: Array[Array] = [
	["play", "경기 1회 완료", "games", 1, 100], ["win", "1승 달성", "wins", 1, 150], ["hits", "안타 5개", "hits", 5, 120],
	["homer", "홈런 1개", "home_runs", 1, 150], ["strikeouts", "탈삼진 5개", "strikeouts", 5, 120], ["runs", "5득점", "runs", 5, 120],
]

static var points := 0
static var xp := 0
## Lifetime numbers: games, wins, hits, home_runs, strikeouts, runs.
static var totals: Dictionary[String, int] = {}
## The same, for the day `today_date` (YYYY-MM-DD); goals met today (ids).
static var today: Dictionary[String, int] = {}
static var today_date := ""
static var met: Array[String] = []
## Item id -> how many are owned.
static var owned: Dictionary[String, int] = {}
## Practice: swings, perfect (timing), home_runs, best_exit (km/h), longest (m), pitches,
## strikes, best_miss (cm, the nearest a pitch came to its target).
static var practice: Dictionary[String, float] = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if not _loaded:
		_loaded = true
		load_file()


static func load_file() -> void:
	points = 0
	xp = 0
	totals.clear()
	today.clear()
	met.clear()
	owned.clear()
	practice.clear()
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			var d: Dictionary = parsed
			points = int(d.get("points", 0))
			xp = int(d.get("xp", 0))
			today_date = str(d.get("today_date", ""))
			for key: String in (d.get("totals", {}) as Dictionary):
				totals[key] = int(d["totals"][key])
			for key: String in (d.get("today", {}) as Dictionary):
				today[key] = int(d["today"][key])
			for id: Variant in (d.get("met", []) as Array):
				met.append(str(id))
			for id: String in (d.get("owned", {}) as Dictionary):
				owned[id] = int(d["owned"][id])
			for key: String in (d.get("practice", {}) as Dictionary):
				practice[key] = float(d["practice"][key])
	_roll_day()


## A tool from game/tools is running the game (captures, measurements): it is not the person
## playing, and his profile and achievements are left as they are (a capture of the league
## once paid him an achievement).
static func tool_run() -> bool:
	var loop := Engine.get_main_loop()
	return loop != null and loop.get_script() != null


static func save_file() -> Error:
	if tool_run():
		return OK
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"points": points, "xp": xp, "totals": totals, "today": today, "today_date": today_date, "met": met, "owned": owned, "practice": practice}, "\t"))
	return OK


## A new day: the day's numbers and goals start again.
static func _roll_day() -> void:
	var date := Time.get_date_string_from_system()
	if date != today_date:
		today_date = date
		today.clear()
		met.clear()


## The level the experience makes, and how far along to the next (0..1).
static func level() -> int:
	return 1 + int(floor(sqrt(float(xp) / 100.0)))


static func level_progress() -> float:
	var n := level()
	var from := float((n - 1) * (n - 1)) * 100.0
	var to := float(n * n) * 100.0
	return clampf((float(xp) - from) / maxf(to - from, 1.0), 0.0, 1.0)


## The three goals of the day, each [id, words, key, target, reward].
static func goals_today() -> Array[Array]:
	ensure_loaded()
	var out: Array[Array] = []
	var start := absi(hash(today_date)) % GOALS.size()
	for i: int in 3:
		out.append(GOALS[(start + i * 2) % GOALS.size()])
	return out


## Adds points (a game played, a goal met) and saves.
static func earn(amount: int) -> void:
	ensure_loaded()
	points += maxi(amount, 0)
	save_file()


## Takes points if there are enough; false (and nothing taken) if not.
static func spend(amount: int) -> bool:
	ensure_loaded()
	if amount > points:
		return false
	points -= amount
	save_file()
	return true


## A game is over: what the player's side did in it (hits, home_runs, strikeouts thrown,
## runs). Pays points and experience, counts toward the day's goals, and returns lines to
## show ("경기 완료 +60P", "목표 달성: 안타 5개 +120P").
static func record_game(won: bool, numbers: Dictionary, share: float = 1.0, level: int = Difficulty.Level.PRO) -> PackedStringArray:
	ensure_loaded()
	_roll_day()
	var lines := PackedStringArray()
	var counted := {"games": 1, "wins": 1 if won else 0}
	for key: String in ["hits", "home_runs", "strikeouts", "runs"]:
		counted[key] = int(numbers.get(key, 0))
	for key: String in counted:
		totals[key] = int(totals.get(key, 0)) + int(counted[key])
		today[key] = int(today.get(key, 0)) + int(counted[key])
	var before := level()
	var pay := roundi((GAME_POINTS + (WIN_POINTS if won else 0)) * clampf(share, 0.0, 1.0) * Difficulty.reward(level, "points"))
	points += pay
	xp += roundi((GAME_XP + (WIN_XP if won else 0)) * clampf(share, 0.3, 1.0) * Difficulty.reward(level, "xp"))
	var bonus := "" if level == Difficulty.Level.PRO else "  (%s ×%s)" % [Difficulty.NAMES[level], String.num(Difficulty.reward(level, "points"), 1)]
	lines.append("%s +%dP%s" % ["승리" if won else "경기 완료", pay, bonus])
	for g: Array in goals_today():
		if not met.has(str(g[0])) and int(today.get(str(g[2]), 0)) >= int(g[3]):
			met.append(str(g[0]))
			points += int(g[4])
			lines.append("목표 달성: %s +%dP" % [g[1], int(g[4])])
	# A level is worth something: points for each one reached.
	for n: int in range(before + 1, level() + 1):
		points += LEVEL_POINTS * n
		lines.append("레벨 업! Lv.%d  +%dP" % [n, LEVEL_POINTS * n])
	save_file()
	return lines


## A pitch of practice: what it adds to the counts and the bests (see `practice`). Saved now
## and then (every pitch would write the file every few seconds).
static func record_practice(numbers: Dictionary) -> void:
	ensure_loaded()
	for key: String in ["swings", "perfect", "home_runs", "pitches", "strikes"]:
		if numbers.has(key):
			practice[key] = float(practice.get(key, 0.0)) + float(numbers[key])
	if numbers.has("exit"):
		practice["best_exit"] = maxf(float(practice.get("best_exit", 0.0)), float(numbers["exit"]))
	if numbers.has("distance"):
		practice["longest"] = maxf(float(practice.get("longest", 0.0)), float(numbers["distance"]))
	if numbers.has("miss"):
		var best := float(practice.get("best_miss", 999.0))
		practice["best_miss"] = minf(best, float(numbers["miss"]))
	if int(practice.get("swings", 0.0) + practice.get("pitches", 0.0)) % 5 == 0:
		save_file()
