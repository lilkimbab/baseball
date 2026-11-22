class_name Achievements
extends RefCounted
## The person's achievements (AchievementBook), kept in user://achievements.json across every
## mode and save, as Profile is. Counted when a game he played ends (note_game) and checked
## from what the modes show (the league's postseason and title, the career's call-up, the
## shop's gear). Each one unlocked pays its tier's points into the shop's wallet and, for some,
## a special item (a signature-grade piece of gear, club funds); a line for the screen to show
## waits in `toasts`. Nothing is counted without a display (the tests leave the file alone).

const PATH := "user://achievements.json"
const DATA := "res://data/achievements.ko.json"

static var book: AchievementBook
## Lines to show ("업적 달성: 첫 승리  +100P"), taken by the screen that shows them.
static var toasts := PackedStringArray()


static func ensure_loaded() -> void:
	if book != null:
		return
	book = AchievementBook.from_data(JsonIO.read_object(DATA))
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			book.load_dict(parsed)


static func save() -> void:
	if book == null:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(book.to_dict(), "\t"))


static func active() -> bool:
	return DisplayServer.get_name() != "headless" and not Profile.tool_run()


static func _today() -> String:
	return Time.get_date_string_from_system()


## Pays what was unlocked and returns the lines to show.
static func _pay(newly: Array[AchievementBook.Def]) -> PackedStringArray:
	var lines := PackedStringArray()
	for d: AchievementBook.Def in newly:
		var pts := book.points_for(d)
		Profile.earn(pts)
		var line := "업적 달성: %s  +%dP" % [d.name, pts]
		if d.item != "":
			line += "  ·  %s" % str(book.item_names.get(d.item, d.item))
		lines.append(line)
		toasts.append(line)
	save()
	return lines


## A game he played is over: what it counts, at the difficulty it was played at. Returns the
## lines to show after the game.
static func note_game(feats: GameFeats, state: GameState, stats: StatBook, level: int, park_id: String = "") -> PackedStringArray:
	if not active() or feats == null or state == null:
		return PackedStringArray()
	ensure_loaded()
	var newly: Array[AchievementBook.Def] = []
	var c := feats.counts(state, stats)
	for key: String in c:
		newly.append_array(book.count(key, c[key], level, _today()))
	if int(c.get("wins", 0)) > 0 and park_id != "":
		newly.append_array(book.distinct("parks_won", park_id, level, _today()))
	return _pay(newly)


## A state reached (a key set to at least `value`).
static func reach(key: String, value: int = 1, level: int = 0) -> PackedStringArray:
	if not active():
		return PackedStringArray()
	ensure_loaded()
	if int(book.counters.get(key, 0)) >= value and (level == 0 or int(book.counters.get("%s@%d" % [key, level], 0)) >= value):
		return PackedStringArray()
	return _pay(book.reach(key, value, level, _today()))


## The league as it stands: a game played, the postseason, first place, the title (at the
## difficulty most of the managed games were played at), a season of the past won, the
## scouting staff and the badges.
static func check_league(s: Season) -> void:
	if not active() or s == null or s.my_team == "":
		return
	var d := s.division_of(s.my_team)
	var row: StandingsRow = s.standings[d].row(s.my_team) if d >= 0 else null
	if row != null and row.games() > 0:
		reach("league_games")
	if s.phase != Season.Phase.REGULAR and d >= 0 and d < s.postseasons.size() and s.postseasons[d].seeds.has(s.my_team):
		reach("postseason")
	if s.phase != Season.Phase.REGULAR and d >= 0 and s.standings[d].rank_of(s.my_team) == 1:
		reach("pennant")
	if s.champion_of(d) == s.my_team:
		reach("champion", 1, s.managed_level())
	if s.history != null and s.finished():
		var scenario := s.history.scenario(s.scenario_id)
		if scenario != null and SeasonPack.goal_met(scenario, s):
			reach("history")
	if s.club != null:
		if s.club.scout_level >= 3:
			reach("scout_max")
		var kinds: Dictionary = {}
		var gold := false
		for item: Vector2i in s.club.bag:
			kinds[item.x] = true
			gold = gold or item.y >= 2
		for id: String in s.club.traits:
			kinds[s.club.traits[id].x] = true
			gold = gold or s.club.traits[id].y >= 2
		if gold:
			reach("gold_badge")
		reach("badge_kinds", kinds.size())


## The career as it stands.
static func check_career(cs: CareerSeason, last: CareerSeason.Report = null) -> void:
	if not active() or cs == null:
		return
	var c := cs.career
	reach("career_start")
	if c.first_team:
		reach("call_up")
	if cs.all_star_selected.has(c.player.id):
		reach("all_star")
	for line: String in cs.log:
		if line.contains("홈런 더비 우승: %s" % c.player.name):
			reach("derby")
		if line.contains("구종 진화"):
			reach("evolve")
	if last != null and last.rating >= 9.0:
		reach("big_game")
	if UiTheme.shown(ClubRules.player_ovr(c.player, cs.season.ovr, cs.season.catalog)) >= 80.0:
		reach("ovr_80")
	for name: String in c.gear:
		if name.ends_with(" 엘리트"):
			reach("elite")
		if name.ends_with(" 시그니처"):
			reach("signature")


## Something was bought in the shop.
static func bought() -> void:
	reach("bought")


## A special item unlocked by an achievement ("gear:가벼운 배트", "club").
static func has_item(item: String) -> bool:
	ensure_loaded()
	return book.items().has(item)


## The achievement that gives an item (for the shop to say how it is earned).
static func source_of(item: String) -> AchievementBook.Def:
	ensure_loaded()
	for d: AchievementBook.Def in book.defs:
		if d.item == item:
			return d
	return null
