class_name Settings
extends RefCounted
## The player's settings (docs/05 section 6, docs/13 S9-5), kept in user://settings.json and
## applied when the game starts and whenever they change.

const PATH := "user://settings.json"
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

## Game.
static var innings := 9
static var pitch_clock := true
static var auto_changes := true
## Interventions in a managed quick game: 0, 3, 5 or −1 for no limit.
static var interventions := 3
## Career pitchers face every batter, not just the ones that matter.
static var pitch_all := false
## Screen.
static var fullscreen := false
static var resolution := 2
## 0 low, 1 medium, 2 high: shadows and anti-aliasing.
static var quality := 2
## Upscaling (AMD FSR 2, built into Godot): 0 off, 1 quality (77% of the pixels drawn),
## 2 balanced (67%), 3 native (full size, for its anti-aliasing alone). FSR 2's temporal
## anti-aliasing also calms the shimmer of thin lines far off: seats, nets, chalk.
static var upscale := 1
## Frames a second (0 no limit).
static var fps_limit := 0
## Sound (no sound yet; kept for when it comes).
static var volume := 0.8
## What the match screen shows.
static var landing_spot := true
static var hit_info := true
static var win_chance := true
static var commentary := true
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	load_file()


static func load_file() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not d is Dictionary:
		return
	var s: Dictionary = d
	innings = int(s.get("innings", innings))
	pitch_clock = bool(s.get("pitch_clock", pitch_clock))
	auto_changes = bool(s.get("auto_changes", auto_changes))
	interventions = int(s.get("interventions", interventions))
	pitch_all = bool(s.get("pitch_all", pitch_all))
	fullscreen = bool(s.get("fullscreen", fullscreen))
	resolution = clampi(int(s.get("resolution", resolution)), 0, RESOLUTIONS.size() - 1)
	quality = clampi(int(s.get("quality", quality)), 0, 2)
	upscale = clampi(int(s.get("upscale", upscale)), 0, 3)
	fps_limit = int(s.get("fps_limit", fps_limit))
	volume = float(s.get("volume", volume))
	landing_spot = bool(s.get("landing_spot", landing_spot))
	hit_info = bool(s.get("hit_info", hit_info))
	win_chance = bool(s.get("win_chance", win_chance))
	commentary = bool(s.get("commentary", commentary))


static func save_file() -> Error:
	var d := {
		"format": 1, "innings": innings, "pitch_clock": pitch_clock, "auto_changes": auto_changes,
		"interventions": interventions, "pitch_all": pitch_all, "fullscreen": fullscreen,
		"resolution": resolution, "quality": quality, "upscale": upscale, "fps_limit": fps_limit, "volume": volume,
		"landing_spot": landing_spot, "hit_info": hit_info, "win_chance": win_chance, "commentary": commentary,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "  "))
	return OK


## Puts the screen settings into effect (not in headless runs).
static func apply(tree: SceneTree) -> void:
	Engine.max_fps = fps_limit
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(RESOLUTIONS[resolution])
	apply_rendering(tree)


## The 3D drawing settings alone (a scene started on its own, without the title screen).
static func apply_rendering(tree: SceneTree) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vp := tree.root
	if upscale > 0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = [1.0, 0.77, 0.67, 1.0][upscale]
		# FSR 2 does its own anti-aliasing.
		vp.msaa_3d = Viewport.MSAA_DISABLED
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][quality], true)
