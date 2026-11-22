class_name Difficulty
extends RefCounted
## How hard the plate and the mound are for the person playing (the user, 2026-11-22: "judge
## the difficulty from the player's side"). Measured with tools/difficulty_report.gd — a
## model of a person's timing and aiming errors playing whole games — and set so that:
##   a person of average skill (timing ±40 ms, aim ±5 cm) on 프로, the default, hits a little
##   better than the league (about .280 / .340 / .440) and gives up a little less (about 4
##   runs a game); a beginner (±60 ms, ±8 cm) has the same on 루키; a practised hand (±25 ms,
##   ±3 cm) on 레전드.
## Only the person's own swings and pitches change: the computer plays as it always does.

enum Level { ROOKIE, PRO, ALL_STAR, LEGEND }

const NAMES: Array[String] = ["루키", "프로", "올스타", "레전드"]
const IDS: Array[String] = ["rookie", "pro", "all_star", "legend"]

## By level:
##   timing   the timing window, as a share of the usual (DuelSettings.timing_scale)
##   floor    share of a small aiming error that still counts (DuelSettings.aim_scale)
##   forgive  aiming error forgiven almost wholly, m (DuelSettings.aim_forgiven)
##   yaw      spread of the bat's angle at contact, degrees (DuelSettings.yaw_spread)
##   barrel   spread of where the barrel meets the ball, as a share (DuelSettings.barrel_scale)
##   scatter  how much more a pitch let go off the moment misses (DuelSettings.hand_scatter; one
##            let go at the right moment goes where it was aimed at every level)
const TABLE := {
	Level.ROOKIE: {"timing": 1.2, "floor": 0.05, "forgive": 0.06, "yaw": 3.0, "barrel": 0.9, "scatter": 1.0},
	Level.PRO: {"timing": 0.83, "floor": 0.47, "forgive": 0.034, "yaw": 9.2, "barrel": 1.18, "scatter": 2.4},
	Level.ALL_STAR: {"timing": 0.7, "floor": 0.7, "forgive": 0.024, "yaw": 11.0, "barrel": 1.4, "scatter": 2.8},
	Level.LEGEND: {"timing": 0.62, "floor": 0.9, "forgive": 0.018, "yaw": 13.0, "barrel": 1.6, "scatter": 3.1},
}


## What a game played at each level pays, as shares of 프로's (the harder the game, the more a
## win is worth; at 레전드 a person of average skill wins less often but earns a little more a
## game, so the step up is worth taking):
##   points  shop points and experience for a game (Profile.record_game)
##   gp      a career game's growth points
##   club    a managed league game's club points
## A game left to the computer (simulated) pays 프로's at most, whatever the setting; and
## 루키 keeps 프로's growth and club points (playing should never earn less than simulating:
## simulated games pay no shop points at all).
const REWARDS := {
	Level.ROOKIE: {"points": 0.8, "xp": 0.8, "gp": 1.0, "club": 1.0},
	Level.PRO: {"points": 1.0, "xp": 1.0, "gp": 1.0, "club": 1.0},
	Level.ALL_STAR: {"points": 1.3, "xp": 1.2, "gp": 1.15, "club": 1.2},
	Level.LEGEND: {"points": 1.7, "xp": 1.5, "gp": 1.3, "club": 1.4},
}


## The other clubs of a league the person manages play above (or below) themselves by this
## share of every rating (the user: "in the league I sign players myself; unless my squad is
## good, 프로 and up should be hard to win — the harder, the stronger the league"). Applied
## to every game of theirs, simulated or played (Season.squad_for). Measured with
## tools/balance_report.gd (--only league, 144 games): the league's middle club / its best
## club win .51 / .71 on 루키, about .38 / .60 on 프로 (at +0.04 it was .33 / .56: an
## ordinary squad finished last), .29 / .46 on 올스타 and .22 / .42 on 레전드 — from 올스타 up
## even the best squad as given has to be built up to contend.
const LEAGUE_FORM := {Level.ROOKIE: -0.03, Level.PRO: 0.025, Level.ALL_STAR: 0.08, Level.LEGEND: 0.12}


static func league_form(level: int) -> float:
	return float(LEAGUE_FORM.get(level, 0.0))


static func reward(level: int, kind: String, played: bool = true) -> float:
	var r: Dictionary = REWARDS.get(level, REWARDS[Level.PRO])
	var share := float(r.get(kind, 1.0))
	return share if played else minf(share, 1.0)


static func by_id(id: String) -> int:
	var i := IDS.find(id)
	return i if i >= 0 else Level.PRO


## The person is at the plate.
static func for_batter(s: DuelSettings, level: int) -> void:
	var t: Dictionary = TABLE.get(level, TABLE[Level.PRO])
	s.timing_scale = float(t["timing"])
	s.aim_scale = float(t["floor"])
	s.aim_forgiven = float(t["forgive"])
	s.aim_forgiving = true
	s.yaw_spread = float(t["yaw"])
	s.barrel_scale = float(t["barrel"])


## The person is on the mound.
static func for_pitcher(s: DuelSettings, level: int) -> void:
	var t: Dictionary = TABLE.get(level, TABLE[Level.PRO])
	s.hand_scatter = float(t["scatter"])
