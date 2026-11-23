class_name Commentary
extends RefCounted
## The one-line play-by-play (docs/13 S6-7) from templates in data/commentary.ko.json.
## Lines use the scorebook's words; `pick` chooses among a situation's lines so the same
## kind of play reads differently through a game without random numbers.

var templates: Dictionary[String, PackedStringArray] = {}


func line(key: String, pick: int, name: String = "", play: String = "", fielders: String = "", runs: int = 0, runner: String = "", base: int = 0) -> String:
	var options: PackedStringArray = templates.get(key, PackedStringArray(["{name}, {play}"]))
	var out := options[posmod(pick, options.size())]
	# A line that tells its runs itself gets no tail.
	var told := out.contains("{runs}") or key.contains("walk_off")
	out = _particles(out, "{name}", name)
	out = _particles(out, "{runner}", runner)
	out = out.replace("{name}", name).replace("{play}", play).replace("{fielders}", fielders)
	out = out.replace("{runner}", runner).replace("{base}", str(base)).replace("{runs}", str(runs))
	if runs > 0 and not told and not key.begins_with("home_run") and templates.has("runs"):
		var tail: PackedStringArray = templates["runs"]
		out += tail[posmod(pick, tail.size())].replace("{runs}", str(runs))
	return out


## A Korean particle after a name in a template, as the name ends: "{name}을" is 을 after a
## final consonant and 를 after a vowel (이/가, 은/는 likewise).
static func _particles(text: String, slot: String, word: String) -> String:
	for pair: Array in [["을", "를"], ["이", "가"], ["은", "는"]]:
		text = text.replace(slot + str(pair[0]), word + josa(word, str(pair[0]), str(pair[1])))
	return text


## `with_final` after a word whose last syllable ends in a consonant, else `without`.
static func josa(word: String, with_final: String, without: String) -> String:
	if word.is_empty():
		return with_final
	var c := word.unicode_at(word.length() - 1)
	if c >= 0xAC00 and c <= 0xD7A3:
		return with_final if (c - 0xAC00) % 28 != 0 else without
	# Digits and Latin letters as they are read: most end in a consonant sound in Korean.
	return with_final if "013678LMNR".contains(word.right(1).to_upper()) else without


## The situation's own template for a plate appearance, most telling first: a walk-off, a
## grand slam, a lead taken, a game tied, a run driven in (a solo home run), a jam escaped
## (the half over with runners left); the first the file has, else the plain one.
func best_key(key: String, runs: int, walk_off: bool, go_ahead: bool, tying: bool, escape: bool) -> String:
	for k: String in context_keys(key, runs, walk_off, go_ahead, tying, escape):
		if templates.has(k):
			return k
	return key


static func context_keys(key: String, runs: int, walk_off: bool, go_ahead: bool, tying: bool, escape: bool) -> PackedStringArray:
	var hit := key in ["single", "double", "triple"]
	var out := PackedStringArray()
	if walk_off:
		out.append(key + "_walk_off")
		out.append("walk_off")
	if key == "home_run" and runs == 4:
		out.append("home_run_grand_slam")
	if go_ahead:
		out.append(key + "_go_ahead")
		if hit:
			out.append("hit_go_ahead")
	if tying:
		out.append(key + "_tying")
		if hit:
			out.append("hit_tying")
	if key == "home_run" and runs == 1:
		out.append("home_run_solo")
	elif runs > 0:
		out.append(key + "_rbi")
	if escape:
		out.append(key + "_escape")
	out.append(key)
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


## How excited the caster is for a line of this template: a home run, a long hit, a walk-off, a
## lead taken shouted ("hot"); a strikeout, a double play, a jam escaped, a run in lifted
## ("warm"); the rest said ("calm").
static func mood_of(key: String) -> StringName:
	for hot: String in ["home_run", "walk_off", "grand_slam", "go_ahead", "double", "triple"]:
		if key.contains(hot) and not key.begins_with("double_play"):
			return &"hot"
	for warm: String in ["strikeout", "double_play", "escape", "tying", "_rbi", "steal", "caught_stealing", "triple_play"]:
		if key.contains(warm):
			return &"warm"
	return &"calm"
