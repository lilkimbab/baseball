extends GutTest
## Saves of older formats load and play on (queue stage 1, 2026-11-23); and nothing new is
## saved without its place among the formats (SaveIO.ADDED).

const F := preload("res://tests/core/rules/rules_fixture.gd")
const SLOT := "test_formats"


func after_each() -> void:
	SaveIO.delete_slot(SLOT)
	CareerSession.career_season = null
	CareerSession.season = null
	CareerSession.career = null


func _league(per_division: int, clubs_count: int) -> Season:
	var clubs := RosterIO.load_pack(LeagueSession.PACK).slice(0, clubs_count)
	var s := Season.create(clubs, per_division, 36, 3, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), ClubIO.load_default())
	s.manage(clubs[0].id)
	for i: int in 5:
		s.play_day(true)
		s.advance()
	return s


func _career() -> CareerSeason:
	var spec := PlayerCreator.Spec.new()
	spec.name = "저장시험"
	spec.position = "CF"
	spec.type_id = "speed"
	CareerSession.start(PlayerCreator.create(spec, CareerIO.load_default(), F.catalog()), LeagueSession.league_clubs()[1].id, 36, 4)
	var cs := CareerSession.career_season
	for i: int in 6:
		if cs.has_game():
			cs.quick()
		cs.next_day()
	return cs


## A save as an older game wrote it: format 1, without what later formats added.
static func _as_format_1(data: Dictionary) -> Dictionary:
	var old := data.duplicate(true)
	old.erase("format")
	for part: String in ["season", "career"]:
		if old.has(part):
			for key: String in (SaveIO.ADDED[2] as Dictionary).get(part, {}):
				(old[part] as Dictionary).erase(key)
	return old


func test_every_saved_key_belongs_to_a_format() -> void:
	var season_keys := SaveIO.known_keys("season")
	for key: String in SaveIO.season_to(_league(10, 10)):
		assert_true(season_keys.has(key), "season key '%s' is in no format (SaveIO.ADDED)" % key)
	var career_keys := SaveIO.known_keys("career")
	for key: String in SaveIO.career_to(_career()):
		assert_true(career_keys.has(key), "career key '%s' is in no format (SaveIO.ADDED)" % key)


func test_a_format_1_league_loads_and_plays_on() -> void:
	for shape: Array in [[10, 10], [10, 30]]:
		var s := _league(int(shape[0]), int(shape[1]))
		var old := _as_format_1({"season": SaveIO.season_to(s)})
		assert_eq(SaveIO.write(SaveIO.slot_path(SLOT) + "/league.json", old), OK)
		var back := SaveIO.load_league(SLOT)
		assert_not_null(back, "%d clubs" % shape[1])
		assert_eq(back.day, s.day)
		assert_eq(back.difficulty, Difficulty.Level.PRO, "an old league is played at 프로")
		assert_false(back.school)
		# It plays on, and saves as the new format.
		for i: int in 3:
			back.play_day(true)
			back.advance()
		assert_eq(SaveIO.save_league(SLOT, back, 0.0), OK)
		var again := SaveIO.read(SaveIO.slot_path(SLOT) + "/league.json")
		assert_eq(int(again["format"]), SaveIO.FORMAT)


func test_a_format_1_career_loads_and_plays_on() -> void:
	var cs := _career()
	var data := {"season": SaveIO.season_to(cs.season), "career": SaveIO.career_to(cs)}
	var old := _as_format_1(data)
	assert_false((old["career"] as Dictionary).has("salary"))
	assert_eq(SaveIO.write(SaveIO.slot_path(SLOT) + "/career.json", old), OK)
	var back := SaveIO.load_career(SLOT)
	assert_not_null(back)
	assert_eq(back.career.player.id, cs.career.player.id)
	assert_eq(back.career.salary, CareerContract.MINIMUM, "the minimum salary")
	assert_eq(back.pro_games, cs.season.games_per_team, "its pro seasons as long as its season")
	assert_eq(back.career.pro_years, 0)
	var guard := 0
	while not back.season.finished() and guard < 200:
		if back.has_game():
			back.quick()
		back.next_day()
		guard += 1
	assert_true(back.season.finished(), "played to the end of the season")


func test_a_save_without_a_number_is_format_1_and_a_newer_one_is_left_alone() -> void:
	var migrated := SaveIO.migrate({"season": {"games": 72}, "career": {}})
	assert_eq(int(migrated["format"]), SaveIO.FORMAT)
	assert_eq((migrated["career"] as Dictionary)["pro_games"], 72)
	assert_eq((migrated["season"] as Dictionary)["difficulty"], 1)
	var newer := SaveIO.migrate({"format": SaveIO.FORMAT + 5, "season": {}})
	assert_eq(int(newer["format"]), SaveIO.FORMAT + 5)
	assert_false((newer["season"] as Dictionary).has("difficulty"), "nothing filled into a newer save")
