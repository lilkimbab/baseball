class_name AchievementBook
extends RefCounted
## The achievements and how far along each is (data/achievements.ko.json). Everything is a
## counter: a key counted over every game the person plays (wins, home_runs, walk_off ...)
## or set once from what the modes show (champion, call_up ...). A counter is kept for every
## difficulty too — "wins@2" counts the wins at 올스타 or harder — so the achievements that ask
## for a harder game read their own. Pure: the screens keep the file and pay the rewards
## (Achievements).

class Def:
	var id := ""
	var name := ""
	var about := ""
	var category := ""
	var tier := 0
	var key := ""
	var target := 1
	## Difficulty.Level the games must be played at, or harder (0: any).
	var min_level := 0
	## A special reward ("gear:<name>", "club"), or "".
	var item := ""

	## The counter it reads.
	func counter() -> String:
		return key if min_level <= 0 else "%s@%d" % [key, min_level]


const TIER_NAMES: Array[String] = ["브론즈", "실버", "골드", "플래티넘"]
const CATEGORY_NAMES := {"game": "경기", "batting": "타격", "pitching": "투구", "league": "리그", "career": "커리어", "shop": "수집", "all": "머니볼"}

var defs: Array[Def] = []
var tier_points := PackedInt32Array([100, 250, 600, 3000])
## Special rewards' names by item id.
var item_names: Dictionary[String, String] = {}
var counters: Dictionary[String, int] = {}
## Distinct things counted (the parks won in): key -> {value: true}.
var seen: Dictionary[String, Dictionary] = {}
## Unlocked: id -> the date ("YYYY-MM-DD").
var unlocked: Dictionary[String, String] = {}


static func from_data(d: Dictionary) -> AchievementBook:
	var book := AchievementBook.new()
	book.tier_points = PackedInt32Array(d.get("tier_points", [100, 250, 600, 3000]) as Array)
	var items: Dictionary = d.get("items", {})
	for key: String in items:
		book.item_names[key] = str(items[key])
	for e: Dictionary in (d.get("achievements", []) as Array):
		var def := Def.new()
		def.id = str(e.get("id", ""))
		def.name = str(e.get("name", ""))
		def.about = str(e.get("about", ""))
		def.category = str(e.get("category", "game"))
		def.tier = int(e.get("tier", 0))
		def.key = str(e.get("key", ""))
		def.target = int(e.get("target", 1))
		def.min_level = int(e.get("min_level", 0))
		def.item = str(e.get("item", ""))
		book.defs.append(def)
	return book


func def_of(id: String) -> Def:
	for d: Def in defs:
		if d.id == id:
			return d
	return null


## Counts `amount` of `key` in a game played at `level` (Difficulty.Level). Returns the
## achievements this unlocked.
func count(key: String, amount: int, level: int, today: String = "") -> Array[Def]:
	if amount <= 0:
		return []
	counters[key] = int(counters.get(key, 0)) + amount
	for m: int in range(1, level + 1):
		var k := "%s@%d" % [key, m]
		counters[k] = int(counters.get(k, 0)) + amount
	return check(today)


## Counts a thing once however often it comes (the parks won in): the counter is how many
## different ones.
func distinct(key: String, value: String, level: int, today: String = "") -> Array[Def]:
	var keys: Array[String] = [key]
	for m: int in range(1, level + 1):
		keys.append("%s@%d" % [key, m])
	for k: String in keys:
		if not seen.has(k):
			seen[k] = {}
		seen[k][value] = true
		counters[k] = (seen[k] as Dictionary).size()
	return check(today)


## Sets a counter to at least `value` (a state the modes show: the scouting level reached, the
## kinds of badges held).
func reach(key: String, value: int, level: int = 0, today: String = "") -> Array[Def]:
	counters[key] = maxi(int(counters.get(key, 0)), value)
	for m: int in range(1, level + 1):
		var k := "%s@%d" % [key, m]
		counters[k] = maxi(int(counters.get(k, 0)), value)
	return check(today)


func progress(d: Def) -> int:
	if d.key == "*":
		var done := 0
		for other: Def in defs:
			if other.key != "*" and unlocked.has(other.id):
				done += 1
		return done
	return mini(int(counters.get(d.counter(), 0)), d.target)


func goal(d: Def) -> int:
	if d.key == "*":
		return defs.size() - 1
	return d.target


## Unlocks what has been reached. Returns the newly unlocked, the last one (머니볼) last.
func check(today: String = "") -> Array[Def]:
	var out: Array[Def] = []
	for d: Def in defs:
		if d.key != "*" and not unlocked.has(d.id) and int(counters.get(d.counter(), 0)) >= d.target:
			unlocked[d.id] = today
			out.append(d)
	for d: Def in defs:
		if d.key == "*" and not unlocked.has(d.id) and progress(d) >= goal(d):
			unlocked[d.id] = today
			out.append(d)
	return out


func points_for(d: Def) -> int:
	return tier_points[clampi(d.tier, 0, tier_points.size() - 1)]


## Special rewards unlocked.
func items() -> PackedStringArray:
	var out := PackedStringArray()
	for d: Def in defs:
		if d.item != "" and unlocked.has(d.id):
			out.append(d.item)
	return out


## How many are unlocked in each tier, and in all.
func tally() -> PackedInt32Array:
	var out := PackedInt32Array([0, 0, 0, 0, 0])
	for d: Def in defs:
		if unlocked.has(d.id):
			out[clampi(d.tier, 0, 3)] += 1
			out[4] += 1
	return out


func to_dict() -> Dictionary:
	var s: Dictionary = {}
	for k: String in seen:
		s[k] = (seen[k] as Dictionary).keys()
	return {"format": 1, "counters": counters, "seen": s, "unlocked": unlocked}


func load_dict(d: Dictionary) -> void:
	counters.clear()
	seen.clear()
	unlocked.clear()
	for k: String in (d.get("counters", {}) as Dictionary):
		counters[k] = int(d["counters"][k])
	for k: String in (d.get("seen", {}) as Dictionary):
		var values: Dictionary = {}
		for v: Variant in (d["seen"][k] as Array):
			values[str(v)] = true
		seen[k] = values
	for k: String in (d.get("unlocked", {}) as Dictionary):
		unlocked[k] = str(d["unlocked"][k])
