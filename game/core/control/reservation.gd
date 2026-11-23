class_name Reservation
extends RefCounted
## A standing instruction for the manager mode (docs/02 section 9): when
## the situation at the start of a plate appearance matches, tell the player, take over the
## plate appearance, or give an order. "주자 득점권에 나가면 알려 줘", "7회 이후 동점이면 개입".
##
## The condition is a combination; a field left at its default does not restrict.

enum Action { NOTIFY, INTERVENE, ORDER }
enum Side { EITHER, BATTING, FIELDING }

var label := ""
var action := Action.NOTIFY
## Whose turn it must be for the player's club.
var side := Side.EITHER
var from_inning := 1
## Largest score difference either way (−1: any).
var max_margin := -1
var runner_in_scoring_position := false
var min_outs := 0
var max_outs := 2
## Leverage index at least this (0: any).
var min_leverage := 0.0
## Our pitcher's pitch count at least this (0: any).
var min_pitches := 0
var order := Tactics.Order.NONE
## Fires once, or at every plate appearance that matches.
var once := true
var used := false


func matches(state: GameState, my_team: int, leverage: float) -> bool:
	if used and once:
		return false
	if side == Side.BATTING and state.batting() != my_team:
		return false
	if side == Side.FIELDING and state.fielding() != my_team:
		return false
	if state.inning < from_inning:
		return false
	if max_margin >= 0 and absi(state.lead_of(my_team)) > max_margin:
		return false
	if runner_in_scoring_position and state.base_empty(2) and state.base_empty(3):
		return false
	if state.outs < min_outs or state.outs > max_outs:
		return false
	if min_leverage > 0.0 and leverage < min_leverage:
		return false
	if min_pitches > 0:
		var ours := state.teams[my_team]
		if state.fielding() != my_team or int(state.pitch_counts.get(ours.pitcher_id, 0)) < min_pitches:
			return false
	if action == Action.ORDER and not Tactics.can_give(order, state):
		return false
	return true


## The first reservation that matches now, marked used; null if none.
static func check(list: Array[Reservation], state: GameState, my_team: int, leverage: float) -> Reservation:
	for r: Reservation in list:
		if r.matches(state, my_team, leverage):
			r.used = true
			return r
	return null


## The ready-made ones the orders menu offers.
static func presets() -> Array[Reservation]:
	var out: Array[Reservation] = []
	var r := Reservation.new()
	r.label = "득점권 기회에 알림"
	r.side = Side.BATTING
	r.runner_in_scoring_position = true
	r.once = false
	out.append(r)
	r = Reservation.new()
	r.label = "승부처에 알림"
	r.min_leverage = WinExpectancy.HIGH
	r.once = false
	out.append(r)
	r = Reservation.new()
	r.label = "7회 이후 동점이면 개입"
	r.action = Action.INTERVENE
	r.from_inning = 7
	r.max_margin = 0
	out.append(r)
	r = Reservation.new()
	r.label = "우리 투수 90구 넘으면 알림"
	r.side = Side.FIELDING
	r.min_pitches = 90
	out.append(r)
	r = Reservation.new()
	r.label = "8회 이후 1점 차 수비는 전진 수비 알림"
	r.side = Side.FIELDING
	r.from_inning = 8
	r.max_margin = 1
	r.min_leverage = 1.5
	out.append(r)
	return out
