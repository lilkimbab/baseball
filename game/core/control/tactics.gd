class_name Tactics
extends RefCounted
## A manager's orders to his team (docs/02 section 9). One order for the
## coming plate appearance, cleared when it ends; the defence, the baserunning and the
## pitcher's approach stay until changed. The computer manager's own choices (bunts,
## intentional walks, steals, positioning) apply whenever no order says otherwise.
##
## Hit-and-run and run-and-hit are not here yet: a steal is still settled before the pitch, so
## a runner going with the pitch needs the play to start with the runner moving (S12).

enum Order { NONE, SWING_AWAY, TAKE, BUNT, SQUEEZE, STEAL, DOUBLE_STEAL, INTENTIONAL_WALK, PITCH_AROUND, ATTACK }
enum Defence { AUTO, NORMAL, INFIELD_IN, DOUBLE_PLAY, NO_DOUBLES }
enum Running { NORMAL, AGGRESSIVE, SAFE }

const OFFENCE_ORDERS: Array[Order] = [Order.SWING_AWAY, Order.TAKE, Order.BUNT, Order.SQUEEZE, Order.STEAL, Order.DOUBLE_STEAL]
const DEFENCE_ORDERS: Array[Order] = [Order.INTENTIONAL_WALK, Order.PITCH_AROUND, Order.ATTACK]
## Seconds a runner adds to (safe) or takes off (aggressive) his own arrival when he judges an
## extra base; the plain judgement is MotionModel.aggression.
const RUNNING_SHIFT: Array[float] = [0.0, -0.12, 0.15]
## Share of the usual in-zone pitches when pitching around a hitter, and the extra share when
## going right at him.
const AROUND_ZONE := 0.6
const ATTACK_ZONE := 0.15

var order := Order.NONE
var defence := Defence.AUTO
var running := Running.NORMAL


static func order_name(o: Order) -> String:
	match o:
		Order.SWING_AWAY:
			return "강공"
		Order.TAKE:
			return "기다리기"
		Order.BUNT:
			return "번트"
		Order.SQUEEZE:
			return "스퀴즈"
		Order.STEAL:
			return "도루"
		Order.DOUBLE_STEAL:
			return "더블 스틸"
		Order.INTENTIONAL_WALK:
			return "고의사구"
		Order.PITCH_AROUND:
			return "유인구 위주"
		Order.ATTACK:
			return "정면 승부"
	return "없음"


static func defence_name(d: Defence) -> String:
	return ["자동", "정상 수비", "전진 수비", "병살 수비", "장타 방지"][d]


static func running_name(r: Running) -> String:
	return ["주루 보통", "주루 적극", "주루 안전"][r]


## Whether an order makes sense now, for the batting side (offence orders) or the fielding
## side (defence orders).
static func can_give(o: Order, state: GameState) -> bool:
	match o:
		Order.BUNT:
			return state.strikes < 2
		Order.SQUEEZE:
			return state.strikes < 2 and state.outs < 2 and not state.base_empty(3)
		Order.STEAL:
			return lead_stealer(state) > 0
		Order.DOUBLE_STEAL:
			return not state.base_empty(1) and not state.base_empty(2) and state.base_empty(3)
		Order.INTENTIONAL_WALK:
			return state.balls == 0 and state.strikes == 0
	return true


## The base of the runner who would steal: the lead runner with the base ahead open (second
## before first), or 0.
static func lead_stealer(state: GameState) -> int:
	for base: int in [2, 1]:
		if not state.base_empty(base) and state.base_empty(base + 1) and not (base == 2 and state.outs == 2):
			return base
	return 0


## The positioning variants for the coming pitch (FieldingAlignment.VARIANTS): the usual
## ones for the situation, or the ordered one.
func variants(state: GameState, expect_bunt: bool) -> Array[String]:
	var out: Array[String] = []
	match defence:
		Defence.AUTO:
			return FieldingAlignment.variants_for(state, expect_bunt)
		Defence.INFIELD_IN:
			out.append("infield_in")
		Defence.DOUBLE_PLAY:
			out.append("double_play")
		Defence.NO_DOUBLES:
			out.append("no_doubles")
	if expect_bunt:
		out.append("bunt")
	return out


func running_shift() -> float:
	return RUNNING_SHIFT[running]


## Share of the usual in-zone intent for the pitcher's approach order.
func zone_factor() -> float:
	if order == Order.PITCH_AROUND:
		return AROUND_ZONE
	return 1.0


func zone_bonus() -> float:
	return ATTACK_ZONE if order == Order.ATTACK else 0.0


## A short line of the orders in force, for the screen ("번트 · 전진 수비").
func summary() -> String:
	var parts: Array[String] = []
	if order != Order.NONE:
		parts.append(order_name(order))
	if defence != Defence.AUTO:
		parts.append(defence_name(defence))
	if running != Running.NORMAL:
		parts.append(running_name(running))
	return " · ".join(parts)
