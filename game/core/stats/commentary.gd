class_name Commentary
extends RefCounted
## The one-line play-by-play (docs/13 S6-7) from templates in data/commentary.ko.json.
## Lines use the scorebook's words; `pick` chooses among a situation's lines so the same
## kind of play reads differently through a game without random numbers.

var templates: Dictionary[String, PackedStringArray] = {}


func line(key: String, pick: int, name: String = "", play: String = "", fielders: String = "", runs: int = 0, runner: String = "", base: int = 0) -> String:
	var options: PackedStringArray = templates.get(key, PackedStringArray(["{name}, {play}"]))
	var out := options[posmod(pick, options.size())]
	out = out.replace("{name}", name).replace("{play}", play).replace("{fielders}", fielders)
	out = out.replace("{runner}", runner).replace("{base}", str(base)).replace("{runs}", str(runs))
	if runs > 0 and not key.begins_with("home_run") and templates.has("runs"):
		var tail: PackedStringArray = templates["runs"]
		out += tail[posmod(pick, tail.size())].replace("{runs}", str(runs))
	return out


## The template for a plate appearance's result; how a strikeout ended is told by `last_call`.
static func key_for(result: PaResult.Kind, last_call: PitchDuel.Result) -> String:
	match result:
		PaResult.Kind.STRIKEOUT:
			if last_call == PitchDuel.Result.CALLED_STRIKE:
				return "strikeout_looking"
			if last_call == PitchDuel.Result.FOUL_TIP:
				return "strikeout_foul_tip"
			return "strikeout_swinging"
		PaResult.Kind.DROPPED_THIRD_STRIKE:
			return "dropped_third_strike"
		PaResult.Kind.WALK:
			return "walk"
		PaResult.Kind.INTENTIONAL_WALK:
			return "intentional_walk"
		PaResult.Kind.HIT_BY_PITCH:
			return "hit_by_pitch"
		PaResult.Kind.SINGLE:
			return "single"
		PaResult.Kind.DOUBLE:
			return "double"
		PaResult.Kind.TRIPLE:
			return "triple"
		PaResult.Kind.HOME_RUN:
			return "home_run"
		PaResult.Kind.GROUND_OUT:
			return "ground_out"
		PaResult.Kind.FLY_OUT:
			return "fly_out"
		PaResult.Kind.LINE_OUT:
			return "line_out"
		PaResult.Kind.POP_OUT:
			return "pop_out"
		PaResult.Kind.DOUBLE_PLAY:
			return "double_play"
		PaResult.Kind.TRIPLE_PLAY:
			return "triple_play"
		PaResult.Kind.SAC_FLY:
			return "sac_fly"
		PaResult.Kind.SAC_BUNT:
			return "sac_bunt"
		PaResult.Kind.FIELDERS_CHOICE:
			return "fielders_choice"
		PaResult.Kind.REACHED_ON_ERROR:
			return "reached_on_error"
	return ""
