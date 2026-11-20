class_name AiController
extends Controller
## The computer's decisions on the field, from AiPitcher, AiBatter and the manager.

## A steal is tried only when the runner reads that he beats the throw by this much...
const STEAL_MARGIN := 0.06
## ...and then in this share of the plate appearances where that holds.
const STEAL_GO := 1.0

var manager: AiManager
var catalog: Dictionary[StringName, PitchType]
var rng: Rng

var _options: Dictionary[String, Array] = {}
var _memory: Dictionary[String, AiPitcher.Memory] = {}


func _init(ai: AiManager, pitch_catalog: Dictionary[StringName, PitchType], random: Rng) -> void:
	manager = ai
	catalog = pitch_catalog
	rng = random


func choose_pitch(state: GameState, duel: PitchDuel) -> PitchDecision:
	var pitcher_id := state.pitcher_id()
	var pitcher := state.fielding_team().player(pitcher_id)
	if not _options.has(pitcher_id):
		_options[pitcher_id] = AiPitcher.options_for(pitcher, catalog)
		_memory[pitcher_id] = AiPitcher.Memory.new()
	var options: Array[AiPitcher.Option] = []
	options.assign(_options[pitcher_id])
	if options.is_empty():
		return AiPitcher.choose(catalog, duel.zone, rng)
	var weak := AiBatter.weak_cells(state.batter_id())
	return AiPitcher.decide(options, duel.zone, state.balls, state.strikes, duel.settings.bats_left, weak, _memory[pitcher_id], rng)


func react(state: GameState, duel: PitchDuel) -> void:
	var pitcher := state.fielding_team().player(state.pitcher_id())
	var fastball := pitcher.pitching.fastball_speed() if pitcher != null and pitcher.pitching != null else 145.0
	AiBatter.decide(duel, state.balls, state.strikes, AiBatter.weak_cells(state.batter_id()), fastball, rng)


func wants_bunt(state: GameState) -> bool:
	return manager.wants_bunt(state)


func wants_steal(state: GameState, _base: int, margin: float) -> bool:
	var lead := state.lead_of(state.batting())
	if absi(lead) >= 5 or (state.inning >= state.rules.innings - 1 and lead <= -3):
		return false
	var read := margin + rng.next_normal() * 0.06
	return read > STEAL_MARGIN and rng.chance(STEAL_GO * state.batting_team().steal_style)
