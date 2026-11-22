class_name Excitement
extends RefCounted
## How worked up each side's fans are (docs/11 section 2), 0 to 1: a base from the game (how
## full the park is, how much the moment matters, the late innings, runners in scoring
## position, a full count) and jolts from what happens, fading over a few seconds. The home
## and away fans are apart: the same home run lifts one side and quiets the other.

## [for the side that gains, for the other, seconds to fade].
const JOLTS := {
	&"home_run": [0.6, -0.25, 4.0],
	&"hit": [0.35, -0.15, 2.0],
	&"run": [0.35, -0.15, 2.0],
	&"strikeout": [0.3, -0.1, 2.0],
	&"out": [0.1, 0.0, 1.5],
	&"walk": [0.1, 0.0, 1.5],
	&"double_play": [0.35, -0.25, 2.5],
	&"error": [0.25, -0.15, 2.0],
	&"great_catch": [0.4, -0.2, 2.5],
}

## Share of the seats filled (0..1).
var fill := 0.6
## The fans of each side: [away, home].
var _jolt := PackedFloat32Array([0.0, 0.0])
var _fade := PackedFloat32Array([1.0, 1.0])


## The base from the game's state; `leverage` as WinExpectancy gives it (2.0 and up: a big
## moment).
func base(state: GameState, leverage: float) -> float:
	var b := 0.25 + 0.15 * fill
	b += 0.2 * clampf(leverage / 2.0, 0.0, 1.0)
	if state.inning >= 7:
		b += 0.1
	if not state.base_empty(2) or not state.base_empty(3):
		b += 0.1
	if state.balls == 3 and state.strikes == 2:
		b += 0.05
	return b


## Something happened that `gaining` side's fans like (0 away, 1 home).
func jolt(kind: StringName, gaining: int) -> void:
	var j: Array = JOLTS.get(kind, [0.1, 0.0, 1.5])
	_jolt[gaining] = maxf(_jolt[gaining], float(j[0]))
	_fade[gaining] = float(j[2])
	_jolt[1 - gaining] = minf(_jolt[1 - gaining], float(j[1])) if float(j[1]) < 0.0 else _jolt[1 - gaining]
	if float(j[1]) < 0.0:
		_fade[1 - gaining] = float(j[2])


func step(delta: float) -> void:
	for side: int in 2:
		_jolt[side] *= exp(-delta / maxf(_fade[side], 0.1))


## A side's fans now (0 away, 1 home).
func value(side: int, state: GameState, leverage: float) -> float:
	return clampf(base(state, leverage) + _jolt[side], 0.0, 1.0)


## The jolt still in a side's fans.
func jolt_of(side: int) -> float:
	return _jolt[side]
