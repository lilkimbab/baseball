extends SceneTree
## Makes the game's example season pack: the fictional top division played out
## once as "what really happened", written in the season pack format with three scenarios.
## Real seasons come from S17's collector into content-local/seasons/; this one only shows the
## format and lets the mode be played without them.
##
##   godot --headless --path game --script res://tools/make_season_pack.gd -- [--games 72] [--seed 2025]

const OUT := "res://data/seasons/fiction-2025.json"


func _init() -> void:
	var args := {}
	var raw := OS.get_cmdline_user_args()
	for i: int in raw.size():
		if raw[i].begins_with("--"):
			args[raw[i].substr(2)] = raw[i + 1] if i + 1 < raw.size() and not raw[i + 1].begins_with("--") else "true"
	var games := int(args.get("games", "72"))
	var seed_value := int(args.get("seed", "2025"))
	var all := RosterIO.load_pack(LeagueSession.PACK)
	var clubs: Array[Team] = []
	for i: int in 10:
		clubs.append(all[i])
	var ids := PackedStringArray()
	for t: Team in clubs:
		ids.append(t.id)
	var rules := RuleSet.kbo_2026()
	rules.extra_inning_limit = 12
	rules.registered_roster = 28
	rules.active_roster = 27
	rules.asia_quota = 0
	var s := Season.create(clubs, 10, games, seed_value, rules, LeagueEnvIO.load_default(), PitchCatalogIO.load_default(), LeagueEnvIO.load_overall(), null)
	s.season_year = 2025
	s.play_to_end()
	var table: Array = []
	for r: StandingsRow in s.standings[0].ranked():
		table.append([r.team_id, r.wins, r.losses, r.ties])
	var leaders: Array = []
	for c: LeagueRecords.Category in [LeagueRecords.batting_categories()[0], LeagueRecords.batting_categories()[1], LeagueRecords.batting_categories()[2],
			LeagueRecords.pitching_categories()[0], LeagueRecords.pitching_categories()[1], LeagueRecords.pitching_categories()[2]]:
		var board := LeagueRecords.leaders(s, 0, c, 1)
		if not board.is_empty():
			var p := (s.teams[board[0].team_id] as Team).player(board[0].player_id)
			leaders.append([c.name, p.name, board[0].text])
	var champion := s.champion_of(0)
	var sixth := str(table[5][0])
	var last := str(table[table.size() - 1][0])
	var first := str(table[0][0])
	var pack := {
		"format": SeasonPack.FORMAT,
		"id": "fiction-2025",
		"title": "2025 가상 1부 리그",
		"year": 2025,
		"note": "실제 시즌이 아닌 예시입니다. 게임의 가상 1부 리그를 한 번 치른 결과를 '실제 기록'으로 담았습니다. 실제 KBO 시즌은 기록 수집기(S17)가 만든 팩을 content-local/seasons/에 넣으면 여기에 나옵니다.",
		"roster": "res://data/rosters/fiction-2026.json",
		"teams": Array(ids),
		"rules": {"games": games, "extra_innings": 12, "foreign_players": 3, "asia_quota": 0, "registered_roster": 28, "designated_hitter": true, "pitch_clock": false},
		"actual": {"standings": table, "champion": champion, "leaders": leaders},
		"scenarios": [
			{"id": "upset", "title": "여섯 번째의 반란", "team": sixth, "text": "그해 6위로 가을야구에 나가지 못한 팀입니다. 이번에는 우승까지 가 보세요.", "goal": {"kind": "champion"}},
			{"id": "climb", "title": "꼴찌 탈출", "team": last, "text": "그해 꼴찌 팀입니다. 정규 시즌 4위 안에 들어 포스트시즌에 나가세요.", "goal": {"kind": "rank", "at_most": 4}},
			{"id": "dynasty", "title": "더 강한 1위", "team": first, "text": "그해 1위 팀입니다. 실제보다 많은 승리를 거두세요.", "goal": {"kind": "wins", "at_least": int(table[0][1]) + 1}},
		],
	}
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(pack, "  ") + "\n")
	file.close()
	print("make_season_pack: %s (%d games, champion %s)" % [OUT, games, champion])
	quit()
