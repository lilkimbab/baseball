class_name Controller
extends RefCounted
## Makes one team's decisions on the field: what to pitch, whether to swing, run or bunt.
## The computer (AiController) answers at once; a person (S5-10) answers through the scene,
## which plays the pitch out in real time and hands the finished PitchDuel to the resolver.


## The pitch to throw now.
func choose_pitch(_state: GameState, _duel: PitchDuel) -> PitchDecision:
	return null


## Called right after release: schedule a swing (or a bunt) on the duel, or leave it.
func react(_state: GameState, _duel: PitchDuel) -> void:
	pass


## Square to bunt in this plate appearance.
func wants_bunt(_state: GameState) -> bool:
	return false


## The runner on `base` tries to steal on this pitch. `margin` is how much sooner he would
## get there than the throw, as he and the bench read it (seconds; negative: he would be out).
func wants_steal(_state: GameState, _base: int, _margin: float) -> bool:
	return false
