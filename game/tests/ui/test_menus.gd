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


## The words on every button under a node (a small icon button's word is its "word" meta).
func _buttons(node: Node) -> Array[String]:
	var out: Array[String] = []
	for b: Node in node.find_children("*", "Button", true, false):
		out.append((b as Button).text if (b as Button).text != "" else str(b.get_meta(&"word", "")))
	return out


func _count(node: Node, script: Script) -> int:
	var n := 1 if node.get_script() == script else 0
	for child: Node in node.get_children():
		n += _count(child, script)
	return n


func test_the_hub_reaches_every_part_in_one_click() -> void:
	var hub := HUB.instantiate() as HubScreen
	add_child_autofree(hub)
	var labels := _buttons(hub)
	# The tabs of the top bar, its small buttons, and the cards.
	for want: String in ["친선 경기", "리그", "커리어", "연습", "상점", "불러오기", "환경 설정", "게임 종료", "리그 모드", "커리어 모드", "연습 모드"]:
		assert_true(labels.has(want), want)
	var title := TITLE.instantiate() as TitleScreen
	add_child_autofree(title)
	assert_true(_buttons(title).has("게임 시작"))
	for path: String in [Screen.QUICK, Screen.LOAD, Screen.SETTINGS, Screen.PRACTICE, Screen.SHOP, LeagueSession.SCREEN, CareerSession.CREATE, CareerSession.HUB]:
		assert_true(ResourceLoader.exists(path), path)
	# Every part of the game opens a screen that builds.
	for id: String in ["quick", "league", "career", "practice", "shop", "load", "settings"]:
		var screen := (load(Screen.dock_path(id)) as PackedScene).instantiate() as Screen
		add_child_autofree(screen)
		assert_not_null(screen.content, id)


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
	assert_true(_buttons(screen).has("뒤로"))
	# Each group of settings builds.
	for group: String in ["game", "screen", "sound", "show"]:
		SettingsScreen.group = group
		screen.refresh()
	SettingsScreen.group = "game"
	assert_gt(_count(screen, Switch), 0, "switches for what is on or off")


func test_a_saved_league_shows_on_the_load_screen_and_loads() -> void:
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	LeagueSession.start(clubs[1].id, 36, 3)
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
	assert_eq(s.my_team, clubs[1].id)


func test_the_player_card_shows_every_rating() -> void:
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var s := LeagueSession.start(clubs[2].id, 36, 4)
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
	assert_gte(_count(card, StatBar), 10, "every rating as a bar")
	assert_eq(_count(card, RadarChart), 1)
	assert_eq(_count(card, FieldDiagram), 1, "the positions he plays")
	var pcard := PlayerCard.open_for(hub, pitcher, s)
	assert_gte(_count(pcard, StatBar), 4 + pitcher.pitching.arsenal.size())


func test_the_shop_sells_what_the_modes_in_progress_can_use() -> void:
	var before := Profile.points
	var shop := (load(Screen.SHOP) as PackedScene).instantiate() as ShopScreen
	add_child_autofree(shop)
	assert_gt(shop.items().size(), 8, "gear, training and funds")
	# Nothing in progress: nothing can be bought.
	for item: Dictionary in shop.items():
		assert_ne(shop.problem(item), "", str(item["id"]))
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var s := LeagueSession.start(clubs[3].id, 36, 6)
	var club_points := s.club.points
	Profile.points = ShopScreen.FUNDS_PRICE - 1
	assert_string_contains(shop.buy("club"), "부족")
	assert_eq(s.club.points, club_points)
	Profile.points = ShopScreen.FUNDS_PRICE + 30
	assert_string_contains(shop.buy("club"), "구매 완료")
	assert_eq(s.club.points, club_points + ShopScreen.FUNDS_POINTS, "the club has its funds")
	assert_eq(Profile.points, 30, "and the points are spent")
	shop.refresh()
	Profile.points = before
	Profile.save_file()


func test_points_and_goals_come_from_games() -> void:
	var before := [Profile.points, Profile.xp, Profile.totals.duplicate(), Profile.today.duplicate(), Profile.met.duplicate()]
	Profile.points = 0
	Profile.today.clear()
	Profile.met.clear()
	var lines := Profile.record_game(true, {"hits": 9, "home_runs": 2, "runs": 7, "strikeouts": 8})
	assert_gte(Profile.points, Profile.GAME_POINTS + Profile.WIN_POINTS, "a win pays")
	assert_string_contains(lines[0], "승리")
	assert_eq(Profile.goals_today().size(), 3)
	Profile.points = before[0]
	Profile.xp = before[1]
	Profile.totals.assign(before[2])
	Profile.today.assign(before[3])
	Profile.met.assign(before[4])
	Profile.save_file()


func test_the_career_screen_builds_every_tab() -> void:
	var rules := CareerIO.load_default()
	var spec := PlayerCreator.Spec.new()
	spec.name = "한도윤"
	spec.type_id = rules.batter_types[0].id
	spec.body_id = rules.bodies[1].id
	spec.skin = rules.skins[1]
	spec.hair = rules.hairs[0]
	spec.beard = rules.beards[0]
	var clubs := LeagueSession.league_clubs()
	CareerSession.start(PlayerCreator.create(spec, rules, PitchCatalogIO.load_default()), clubs[4].id, 36, 9)
	CareerSession.slot = "menu_test"
	# (The futures league has days off: to a day with his game.)
	var guard := 0
	while not CareerSession.career_season.has_game() and guard < 10:
		CareerSession.career_season.next_day()
		guard += 1
	var screen := (load(CareerSession.HUB) as PackedScene).instantiate() as CareerScreen
	add_child_autofree(screen)
	for tab: String in ["home", "growth", "table"]:
		screen.set("_tab", tab)
		screen.refresh()
	assert_gt(_count(screen, DataTable), 0, "the division table")
	screen.quick()
	assert_not_null(CareerSession.last_report, "a game settled at once leaves its report")
	screen.set("_tab", "home")
	screen.refresh()
	# With a career on, the shop sells his gear and training.
	var shop := (load(Screen.SHOP) as PackedScene).instantiate() as ShopScreen
	add_child_autofree(shop)
	var before := Profile.points
	var gp := float(CareerSession.career.gp.get("batting", 0.0))
	Profile.points = ShopScreen.TRAINING_PRICE
	assert_string_contains(shop.buy("gp:batting"), "구매 완료")
	assert_almost_eq(float(CareerSession.career.gp.get("batting", 0.0)), gp + ShopScreen.TRAINING_GP, 0.01)
	assert_string_contains(shop.buy("gp:pitching"), "투수 전용")
	Profile.points = before
	Profile.save_file()
	CareerSession.last_report = null
