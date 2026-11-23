class_name MenuMusic
extends RefCounted
## The menus' music: one loop that goes on from screen to screen without a
## break, and stops for a game (a game has its crowd instead). A menu song in the local content
## pack (content-local/audio/music/menu.ogg) plays instead of the game's own.

static var _player: AudioStreamPlayer


## Starts the loop if it is not playing (called by every menu screen).
static func play(tree: SceneTree) -> void:
	if tree == null or DisplayServer.get_name() == "headless":
		return
	GameAudio.ensure_buses()
	if _player == null or not is_instance_valid(_player):
		_player = AudioStreamPlayer.new()
		_player.bus = &"Music"
		_player.stream = GameAudio.stream("music/menu", true)
		_player.volume_db = -6.0
		tree.root.add_child.call_deferred(_player)
		_player.ready.connect(_player.play, CONNECT_ONE_SHOT)
		return
	if not _player.playing:
		_player.volume_db = -6.0
		_player.play()


static func stop() -> void:
	if _player != null and is_instance_valid(_player) and _player.playing:
		_player.stop()
