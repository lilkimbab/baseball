class_name Rng
extends RefCounted
## Deterministic random numbers: PCG32 (XSH-RR 64/32).
##
## Implemented here instead of using the engine generator so that results never change with
## the engine version: replays and regression tests depend on identical sequences.
## Use fork() to give each consumer (pitch execution, batter decisions, presentation...) its
## own stream, so drawing extra numbers in one place cannot shift results in another.

const MULTIPLIER := 6364136223846793005
const MASK32 := 0xFFFFFFFF
const TWO_POW_32 := 4294967296.0
# splitmix64 constants, written as the signed 64-bit equivalents of the usual hex values.
const MIX_GAMMA := -7046029254386353131
const MIX_A := -4658895280553007687
const MIX_B := -7723592293110705685

var _state: int = 0
var _inc: int = 1
var _seed: int = 0
var _stream: int = 0
var _spare_normal := 0.0
var _has_spare := false


func _init(seed_value: int = 0, stream: int = 0) -> void:
	reseed(seed_value, stream)


func reseed(seed_value: int, stream: int = 0) -> void:
	_seed = seed_value
	_stream = stream
	_state = 0
	_inc = (stream << 1) | 1
	next_u32()
	_state += seed_value
	next_u32()
	_has_spare = false


## Uniform integer in [0, 2^32).
func next_u32() -> int:
	var old := _state
	_state = old * MULTIPLIER + _inc
	var xorshifted := _lsr(_lsr(old, 18) ^ old, 27) & MASK32
	var rot := _lsr(old, 59)
	return ((xorshifted >> rot) | (xorshifted << ((32 - rot) & 31))) & MASK32


## Uniform float in [0, 1).
func next_float() -> float:
	return float(next_u32()) / TWO_POW_32


## Uniform float in [low, high).
func next_range(low: float, high: float) -> float:
	return low + (high - low) * next_float()


## Uniform integer in [0, count). Unbiased (rejection sampling).
func next_int(count: int) -> int:
	if count <= 1:
		return 0
	var threshold := (4294967296 - count) % count
	while true:
		var r := next_u32()
		if r >= threshold:
			return r % count
	return 0


## Uniform integer in [low, high], both ends included.
func next_int_range(low: int, high: int) -> int:
	return low + next_int(high - low + 1)


## True with the given probability.
func chance(probability: float) -> bool:
	return next_float() < probability


## Standard normal variate (mean 0, standard deviation 1), Box-Muller.
func next_normal() -> float:
	if _has_spare:
		_has_spare = false
		return _spare_normal
	var u1 := 1.0 - next_float()
	var u2 := next_float()
	var radius := sqrt(-2.0 * log(u1))
	_spare_normal = radius * sin(TAU * u2)
	_has_spare = true
	return radius * cos(TAU * u2)


## Index drawn with probability proportional to its weight. Returns -1 if all weights are zero.
func pick_weighted(weights: PackedFloat64Array) -> int:
	var total := 0.0
	for w: float in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return -1
	var x := next_float() * total
	for i: int in weights.size():
		x -= maxf(weights[i], 0.0)
		if x < 0.0:
			return i
	return weights.size() - 1


## Independent generator derived from this one's seed and a key. It does not depend on how
## many numbers have been drawn, so streams stay stable when call order changes.
func fork(key: int) -> Rng:
	return Rng.new(_mix(_seed ^ _mix(key)), _mix(_stream + key + 1) & 0x7FFFFFFFFFFFFFFF)


## State for save games and replays.
func get_state() -> PackedInt64Array:
	return PackedInt64Array([_state, _inc, _seed, _stream])


func set_state(state: PackedInt64Array) -> void:
	_state = state[0]
	_inc = state[1]
	_seed = state[2]
	_stream = state[3]
	_has_spare = false


## Logical (unsigned) right shift for 64-bit values; n must be 1..63.
static func _lsr(x: int, n: int) -> int:
	return (x >> n) & ((1 << (64 - n)) - 1)


static func _mix(x: int) -> int:
	var z := x + MIX_GAMMA
	z = (z ^ _lsr(z, 30)) * MIX_A
	z = (z ^ _lsr(z, 27)) * MIX_B
	return z ^ _lsr(z, 31)
