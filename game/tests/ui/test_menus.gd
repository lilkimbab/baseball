extends GutTest
## The title, hub and menus (docs/13 S9): every screen within three clicks, a quick game set up
## from the menu, settings kept, a save loaded from the hub.

const TITLE := preload("res://ui/title_screen.tscn")
const HUB := preload("res://ui/hub_screen.tscn")
const QUICK := preload("res://ui/quick_match_screen.tscn")
const SETTINGS := preload("res://ui/settings_screen.tscn")
const LOAD := preload("res://ui/load_screen.tscn")


func after_each() -> void:
	SaveIO.delete_slot("menu_test")
	LeagueSession.season = null
	CareerSession.career_season = null
	QuickMatchScreen.pending = false


func _buttons(node: Node) -> Array[String]:
	var out: Array[String] = []
	for b: Node in node.find_children("*", "Button", true, false):
		out.append((b as Button).text)
	return out


func test_the_hub_reaches_every_part_in_one_click() -> void:
	var hub := HUB.instantiate() as HubScreen
	add_child_autofree(hub)
	var labels := _buttons(hub)
	for want: String in ["빠른 경기", "감독 리그", "커리어", "훈련장", "불러오기", "설정"]:
		assert_true(labels.has(want), want)
	var title := TITLE.instantiate() as TitleScreen
	add_child_autofree(title)
	assert_true(_buttons(title).has("시작"))
	for path: String in [HubScreen.QUICK, HubScreen.LOAD, HubScreen.SETTINGS, HubScreen.PRACTICE, LeagueSession.SCREEN, CareerSession.CREATE]:
		assert_true(ResourceLoader.exists(path), path)


func test_a_quick_game_from_the_menu_uses_its_choices() -> void:
	var quick := QUICK.instantiate() as QuickMatchScreen
	add_child_autofree(quick)
	QuickMatchScreen.away_index = 4
	QuickMatchScreen.home_index = 7
	QuickMatchScreen.side = "away"
	Settings.innings = 3
	QuickMatchScreen.pending = true
	var scene := (load("res://match/match.tscn") as PackedScene).instantiate() as MatchScene
	scene.use_motion = false
	add_child_autofree(scene)
	assert_false(QuickMatchScreen.pending, "read once")
	assert_true(scene.from_menu)
	assert_eq(scene.innings, 3)
	assert_eq(scene.human_team, 0)
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	assert_eq(scene.game.teams[0].team_id, clubs[4].id)
	assert_eq(scene.game.teams[1].team_id, clubs[7].id)


func test_settings_are_kept_between_runs() -> void:
	var before := Settings.pitch_clock
	Settings.pitch_clock = not before
	Settings.innings = 6
	assert_eq(Settings.save_file(), OK)
	Settings.pitch_clock = before
	Settings.innings = 9
	Settings.load_file()
	assert_eq(Settings.pitch_clock, not before)
	assert_eq(Settings.innings, 6)
	Settings.pitch_clock = before
	Settings.innings = 9
	Settings.save_file()
	var screen := SETTINGS.instantiate() as SettingsScreen
	add_child_autofree(screen)
	assert_true(_buttons(screen).has("허브로"))


func test_a_saved_league_shows_on_the_load_screen_and_loads() -> void:
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	LeagueSession.start(clubs[21].id, 36, 3)
	LeagueSession.season.play_day()
	LeagueSession.slot = "menu_test"
	LeagueSession.autosave()
	var day := LeagueSession.season.day
	LeagueSession.season = null
	var screen := LOAD.instantiate() as LoadScreen
	add_child_autofree(screen)
	assert_true(_buttons(screen).has("불러오기"))
	# Loading through the hub changes scenes, which a test cannot; this is what it reads.
	var s := SaveIO.load_league("menu_test")
	assert_not_null(s)
	assert_eq(s.day, day)
	assert_eq(s.my_team, clubs[21].id)


func test_the_player_card_shows_every_rating() -> void:
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var s := LeagueSession.start(clubs[22].id, 36, 4)
	var hub := HUB.instantiate() as HubScreen
	add_child_autofree(hub)
	var hitter: Player = null
	var pitcher: Player = null
	for p: Player in (s.teams[s.my_team] as Team).first_team():
		if p.is_pitcher() and pitcher == null:
			pitcher = p
		if not p.is_pitcher() and hitter == null:
			hitter = p
	var card := PlayerCard.open_for(hub, hitter, s)
	assert_gte(card.find_children("*", "ProgressBar", true, false).size(), 10)
	var pcard := PlayerCard.open_for(hub, pitcher, s)
	assert_gte(pcard.find_children("*", "ProgressBar", true, false).size(), 4 + pitcher.pitching.arsenal.size())
