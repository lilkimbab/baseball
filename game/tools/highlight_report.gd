extends SceneTree
## How often the slow-motion highlights would be shown (PlayHighlight): plays physical games
## between average clubs and counts, for one side's batting, the crushed balls and the chances
## in doubt, and how many of them the rest between highlights lets through.
##
##   godot --headless --path game --script res://tools/highlight_report.gd -- --games 60


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var games := int(str(args.get("games", "60")))
	var seed_value := int(str(args.get("seed", "2026")))
	var catalog := PitchCatalogIO.load_default()
	var env := LeagueEnvIO.load_default("")
	var ovr := LeagueEnvIO.load_overall()
	var gen := LeagueGenerator.new(RosterIO.load_names(), catalog, seed_value)
	var teams: Array[Team] = []
	for i: int in 8:
		teams.append(gen.team(i, 50.0))
	var rng := Rng.new(seed_value).fork(9)
	var balls := 0
	var homers := 0
	var to_the_wall := 0
	var made := 0
	var missed := 0
	var shown_contact := 0
	var shown_chance := 0
	var hard := 0
	for g: int in games:
		var sim := GameSim.create(teams[g % 8], teams[(g + 1 + g / 8) % 8], RuleSet.kbo_2026(), env, catalog, ovr, rng.fork(g), null, null, true)
		var resolver := sim.resolver as PhysicalResolver
		var rested := PlayHighlight.REST
		var guard := 0
		while not sim.state.over and guard < GameSim.MAX_EVENTS:
			resolver.last_play = null
			var batting := sim.state.batting()
			var event := resolver.next_event(sim.state)
			var play := resolver.last_play
			# One side's batting: the away club's.
			if play != null and not play.foul and batting == 0:
				balls += 1
				var exit := resolver.last_duel.contact.exit_speed_kmh() if resolver.last_duel.contact != null else 0.0
				hard += 1 if play.has_hard_chance() else 0
				if play.result == PaResult.Kind.HOME_RUN:
					homers += 1
				elif PlayHighlight.crushed(play, exit):
					to_the_wall += 1
				if PlayHighlight.in_doubt(play):
					if play.hard_made:
						made += 1
					else:
						missed += 1
				var found := PlayHighlight.of(play, exit, rested)
				rested += 1
				for h: PlayHighlight in found:
					rested = 0
					if h.kind == PlayHighlight.Kind.CONTACT:
						shown_contact += 1
					else:
						shown_chance += 1
			var out := GameFlow.apply(sim.state, event)
			sim.scorer.record(sim.state, event, out)
			sim.manager.note_change(sim.state, event)
			guard += 1
	var per := 1.0 / games
	print("highlight: %d games, %.1f balls in play a game (one side batting)" % [games, balls * per])
	print("highlight: home runs %.2f, flies to the wall %.2f, hard chances %.2f a game" % [homers * per, to_the_wall * per, hard * per])
	print("highlight: chances in doubt: caught %.2f, missed %.2f a game" % [made * per, missed * per])
	print("highlight: shown: contact %.2f, chance %.2f a game" % [shown_contact * per, shown_chance * per])
	quit(0)
