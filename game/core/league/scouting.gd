class_name Scouting
extends RefCounted
## The daily scouting report: five candidates a day, better ones in a
## higher division and with a better scout. Candidates are made by the league generator, so
## they are built like every other player (and named the same way).

## Roles a candidate may have, and how often (A).
const ROLES: Array[String] = ["SP", "RP", "RP", "C", "1B", "2B/SS", "SS/3B", "3B/1B", "LF/RF", "CF/LF", "RF/1B"]


static func candidates(gen: LeagueGenerator, division: int, level: int, rules: ClubRules) -> Array[Player]:
	var out: Array[Player] = []
	var mean := rules.scout_talent[clampi(division, 0, rules.scout_talent.size() - 1)] + (clampi(level, 1, rules.scout_max_level) - 1) * rules.scout_level_bonus
	for i: int in rules.scout_candidates:
		var role: String = ROLES[gen.rng.next_int(ROLES.size())]
		var talent := mean + gen.rng.next_normal() * rules.scout_spread
		var p := gen.player(role, talent)
		p.id = "s" + p.id
		out.append(p)
	return out
