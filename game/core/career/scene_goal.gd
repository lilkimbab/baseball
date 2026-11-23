class_name SceneGoal
extends RefCounted
## The goal of one career scene: shown on the scene card before the
## player goes in, checked when the plate appearance ends. Each counts in one field
## (batting or pitching) and is worth GOAL_GP growth points there.

enum Kind { REACH_BASE, ADVANCE_RUNNER, DRIVE_IN, FAVOURABLE_COUNT, EXTRA_BASES, STRIKEOUT, GET_OUT, NO_RUNS }

const GOAL_GP := 10.0

var kind := Kind.REACH_BASE
var field := "batting"


static func make(k: Kind) -> SceneGoal:
	var g := SceneGoal.new()
	g.kind = k
	g.field = "pitching" if k >= Kind.STRIKEOUT else "batting"
	return g


## The goal for the player's turn at bat in this situation.
static func for_batting(state: GameState) -> SceneGoal:
	var lead := state.lead_of(state.batting())
	if not state.base_empty(3) and state.outs < 2:
		return make(Kind.DRIVE_IN)
	if not state.base_empty(2) and state.base_empty(3) and state.outs == 0:
		return make(Kind.ADVANCE_RUNNER)
	if state.inning >= state.rules.innings - 1 and lead < 0 and lead >= -2 and state.runners_on() == 0:
		return make(Kind.EXTRA_BASES)
	if state.outs == 0 and state.runners_on() == 0:
		return make(Kind.REACH_BASE)
	return make(Kind.FAVOURABLE_COUNT)


## The goal for the player on the mound against this batter.
static func for_pitching(state: GameState) -> SceneGoal:
	if not state.base_empty(2) or not state.base_empty(3):
		return make(Kind.NO_RUNS)
	var slot := state.batting_team().slot_of(state.batter_id())
	if slot >= 2 and slot <= 4:
		return make(Kind.STRIKEOUT)
	return make(Kind.GET_OUT)


func label() -> String:
	match kind:
		Kind.REACH_BASE:
			return "출루하기"
		Kind.ADVANCE_RUNNER:
			return "주자를 진루시키기"
		Kind.DRIVE_IN:
			return "타점 올리기"
		Kind.FAVOURABLE_COUNT:
			return "유리한 볼카운트 만들기"
		Kind.EXTRA_BASES:
			return "장타 치기"
		Kind.STRIKEOUT:
			return "이 타자를 삼진으로"
		Kind.GET_OUT:
			return "이 타자를 잡기"
		Kind.NO_RUNS:
			return "실점 없이 막기"
	return ""


## Whether the plate appearance that just ended met the goal. `best_count` is the best count
## for the batter seen in it (balls, strikes); `runners_before` the bases occupied before.
func achieved(event: GameEvent, out: FlowOutcome, best_count: Vector2i, runners_before: Array[bool]) -> bool:
	var result := event.result
	var reached := PaResult.is_hit(result) or PaResult.is_walk(result) or result == PaResult.Kind.HIT_BY_PITCH or result == PaResult.Kind.REACHED_ON_ERROR
	match kind:
		Kind.REACH_BASE:
			return reached
		Kind.DRIVE_IN:
			return out.scored.size() > 0 and result != PaResult.Kind.DOUBLE_PLAY and result != PaResult.Kind.REACHED_ON_ERROR
		Kind.ADVANCE_RUNNER:
			for m: RunnerMove in event.moves:
				if m.from >= 1 and runners_before[m.from - 1] and m.to > m.from and not m.is_out():
					return true
			return false
		Kind.FAVOURABLE_COUNT:
			return reached or (best_count.x >= 2 and best_count.x > best_count.y)
		Kind.EXTRA_BASES:
			return result == PaResult.Kind.DOUBLE or result == PaResult.Kind.TRIPLE or result == PaResult.Kind.HOME_RUN
		Kind.STRIKEOUT:
			return PaResult.is_strikeout(result)
		Kind.GET_OUT:
			return out.outs_made > 0 and not reached
		Kind.NO_RUNS:
			return out.scored.is_empty() and not PaResult.is_walk(result) and result != PaResult.Kind.HIT_BY_PITCH
	return false
