class_name CheerSequencer
extends RefCounted
## The batting side's cheering: drums, thunder sticks, a whistle and
## shouted calls on the beat the visible crowd moves to (Crowd.BEATS_PER_SECOND), one of
## twelve patterns of eight beats, quieter ones when the fans are calm and busier ones as
## they warm up, special ones for a full count and for runners in scoring position. It goes
## while the batter waits, quiets as the pitcher winds up, and gives way to the crowd's
## reaction when the ball is in play. The patterns are the game's own; a club's real chant in
## the local content pack (content-local/audio/chants/<club>.ogg) is played instead.

const BEATS := 8
## Each pattern: [beat (halves allowed), sound] — sounds are cheer/<name>.
const PATTERNS: Array = [
	# Calm (0-3).
	[[0, "drum_low"], [2, "drum_low"], [4, "drum_low"], [6, "drum_low"]],
	[[0, "drum_low"], [3, "drum_low"], [4, "drum_low"], [6, "sticks"]],
	[[0, "sticks"], [2, "sticks"], [4, "sticks"], [5, "sticks"], [6, "sticks"]],
	[[0, "drum_low"], [1, "sticks"], [2, "drum_low"], [3, "sticks"], [4, "drum_low"], [5, "sticks"], [6, "drum_low"], [7, "sticks"]],
	# Warm (4-7).
	[[0, "drum_low"], [1, "drum_high"], [2, "drum_low"], [3, "drum_high"], [4, "drum_low"], [5, "drum_high"], [6, "hey"]],
	[[0, "drum_low"], [0.5, "drum_low"], [1, "drum_high"], [2, "drum_low"], [3, "sticks"], [4, "drum_low"], [4.5, "drum_low"], [5, "drum_high"], [6, "hey"], [7, "hey"]],
	[[0, "sticks"], [1, "sticks"], [2, "drum_low"], [3, "sticks"], [4, "sticks"], [5, "sticks"], [6, "drum_low"], [6.5, "drum_low"], [7, "hey"]],
	[[0, "drum_low"], [1, "oh"], [2, "drum_low"], [3, "oh"], [4, "drum_low"], [5, "oh"], [6, "drum_high"], [7, "hey"]],
	# Hot (8-9).
	[[0, "drum_low"], [0.5, "drum_high"], [1, "drum_low"], [1.5, "drum_high"], [2, "hey"], [3, "drum_low"], [3.5, "drum_high"], [4, "drum_low"], [4.5, "drum_high"], [5, "drum_low"], [6, "hey"], [7, "hey"]],
	[[0, "whistle"], [0.5, "drum_low"], [1, "drum_low"], [2, "hey"], [3, "drum_low"], [4, "whistle"], [4.5, "drum_low"], [5, "drum_low"], [6, "hey"], [7, "hey"]],
	# A full count (10), runners in scoring position (11).
	[[0, "drum_low"], [2, "drum_low"], [4, "drum_low"], [5, "drum_low"], [6, "drum_low"], [6.5, "drum_low"], [7, "drum_low"], [7.5, "drum_low"]],
	[[0, "drum_low"], [0.5, "sticks"], [1, "hey"], [2, "drum_low"], [2.5, "sticks"], [3, "hey"], [4, "drum_low"], [4.5, "drum_high"], [5, "drum_high"], [6, "oh"], [7, "hey"]],
]

var pattern := 0
## The last beat played (the crowd's beat clock).
var _last_beat := -1.0
var _bars := 0


## The pattern for the fans' mood: calm, warm or hot, or a special one.
static func choose(excitement: float, full_count: bool, scoring_position: bool, roll: float) -> int:
	if full_count:
		return 10
	if scoring_position and excitement >= 0.45:
		return 11
	var band := Vector2i(0, 3) if excitement < 0.45 else (Vector2i(4, 7) if excitement < 0.75 else Vector2i(8, 9))
	return band.x + clampi(int(roll * (band.y - band.x + 1)), 0, band.y - band.x)


## The sounds due between the last call and `beat` (the crowd's beat clock), and the pattern
## changed at the top of each eight-beat bar by `pick` (a Callable returning a pattern).
func due(beat: float, pick: Callable) -> PackedStringArray:
	var out := PackedStringArray()
	if _last_beat < 0.0 or beat < _last_beat or beat - _last_beat > BEATS:
		_last_beat = beat
		return out
	var from := _last_beat
	_last_beat = beat
	var bar_from := floori(from / BEATS)
	var bar_to := floori(beat / BEATS)
	if bar_to > bar_from:
		_bars += 1
		pattern = int(pick.call())
	for bar: int in range(bar_from, bar_to + 1):
		for hit: Array in PATTERNS[pattern]:
			var at := bar * BEATS + float(hit[0])
			if at >= from and at < beat:
				out.append(str(hit[1]))
	return out


func reset() -> void:
	_last_beat = -1.0
