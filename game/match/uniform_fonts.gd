class_name UniformFonts
extends RefCounted
## The lettering sewn onto the uniforms (the user: "bring in the number and
## letter faces real ballplayers wear"). Four kinds, as on real jerseys:
##   block   full block, the numbers and names of most MLB and KBO clubs;
##   tuscan  block with split serifs (Boston's and Detroit's kind);
##   script  a baseball script, for a nickname across the chest with a tail under it;
##   name    a heavy Korean face for the name on the back.
## Recreations of the real faces are in the local content pack when it has them
## (content-local/fonts/uniform/, fetched by tools/assets/fetch_uniform_fonts.sh; free for
## private use, not passed on); otherwise open-licence faces of the same kinds, which are in
## the game (game/assets/fonts/uniform/, licences beside them).

const BUNDLED := "res://assets/fonts/uniform/"
const FACES := {
	&"block": ["jersey_m54.ttf", "CollegeBlock-Bold.ttf"],
	&"tuscan": ["mlb_tuscan.ttf", "Rye-Regular.ttf"],
	&"script": ["ballpark_weiner.ttf", "Lobster-Regular.ttf"],
	&"name": ["", "BlackHanSans-Regular.ttf"],
	&"name_square": ["", "DoHyeon-Regular.ttf"],
}

static var _cache: Dictionary[StringName, Font] = {}
static var _from_pack: Dictionary[StringName, bool] = {}


static func face(kind: StringName) -> Font:
	if _cache.has(kind):
		return _cache[kind]
	var names: Array = FACES.get(kind, FACES[&"block"])
	var font: Font = null
	var local := MotionLibrary.pack_root().path_join("fonts/uniform").path_join(str(names[0]))
	if str(names[0]) != "" and FileAccess.file_exists(local):
		var file := FontFile.new()
		if file.load_dynamic_font(local) == OK:
			font = file
			_from_pack[kind] = true
	if font == null:
		font = load(BUNDLED + str(names[1])) as Font
	# Korean falls back to the name face (a block or script face has Latin letters only).
	if kind != &"name" and font is FontFile:
		var with_korean := FontVariation.new()
		with_korean.base_font = font
		with_korean.fallbacks = [face(&"name")]
		font = with_korean
	_cache[kind] = font
	return font


## Whether a face came from the local pack (for the tests and the credits).
static func from_pack(kind: StringName) -> bool:
	face(kind)
	return _from_pack.get(kind, false)
