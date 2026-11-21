class_name HubScreen
extends Screen
## The hub (docs/05 section 5): the main menu in one row along the bottom — quick game, the
## manager league, the career, the practice field, load, settings — and above it what is in
## progress. Every screen is within three clicks of here.

const QUICK := "res://ui/quick_match_screen.tscn"
const LOAD := "res://ui/load_screen.tscn"
const SETTINGS := "res://ui/settings_screen.tscn"
const PRACTICE := "res://match/duel.tscn"


func build() -> void:
	title("허브")
	if LeagueSession.season != null:
		var s := LeagueSession.season
		line("감독 리그 진행 중: %s · %d년 %d일째" % [(s.teams[s.my_team] as Team).name, s.season_year, s.day + 1], UiTheme.INK)
	if CareerSession.career_season != null:
		var cs := CareerSession.career_season
		line("커리어 진행 중: %s · %d년 %d일째" % [cs.career.player.name, cs.season.season_year, cs.season.day + 1], UiTheme.INK)
	if LeagueSession.season == null and CareerSession.career_season == null:
		line("아래에서 고른다. 감독 리그와 커리어는 매일 자동으로 저장된다.", UiTheme.DIM)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.position = Vector2(0.0, 0.0)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 640.0)
	content.add_child(spacer)
	content.add_child(bar)
	button("빠른 경기", func() -> void: go(QUICK), bar, 250.0)
	button("감독 리그", func() -> void: go(LeagueSession.SCREEN), bar, 250.0)
	button("커리어", func() -> void: go(CareerSession.HUB if CareerSession.career_season != null else CareerSession.CREATE), bar, 250.0)
	button("훈련장", func() -> void: go(PRACTICE), bar, 250.0)
	button("불러오기", func() -> void: go(LOAD), bar, 250.0)
	button("설정", func() -> void: go(SETTINGS), bar, 250.0)
	button("끝내기", func() -> void: get_tree().quit(), bar, 150.0)


## Loads a save and opens its screen.
static func load_slot(from: Node, slot: String, mode: String) -> bool:
	if mode == "career":
		var cs := SaveIO.load_career(slot)
		if cs == null:
			return false
		CareerSession.career_season = cs
		CareerSession.career = cs.career
		CareerSession.season = cs.season
		CareerSession.slot = slot
		if from.is_inside_tree():
			from.get_tree().change_scene_to_file(CareerSession.HUB)
		return true
	var s := SaveIO.load_league(slot)
	if s == null:
		return false
	LeagueSession.season = s
	LeagueSession.slot = slot
	if from.is_inside_tree():
		from.get_tree().change_scene_to_file(LeagueSession.SCREEN)
	return true
