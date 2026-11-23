class_name Training
extends RefCounted
## Growth of a player's ratings: the club's daily training and, later,
## the career mode's. Each rating in the focus goes up by the step; pitches' movement and
## command for all his pitches, speed in km/h at a fifth of the step.


## `cap`: NATURAL for every club's training; the career's own growth passes MAX.
static func grow(p: Player, ratings: PackedStringArray, step: float, cap: float = RatingScale.NATURAL) -> void:
	for key: String in ratings:
		match key:
			"contact":
				p.batting.contact_r = minf(p.batting.contact_r + step, maxf(cap, RatingScale.NATURAL))
				p.batting.contact_l = minf(p.batting.contact_l + step, maxf(cap, RatingScale.NATURAL))
			"power":
				p.batting.power_r = minf(p.batting.power_r + step, maxf(cap, RatingScale.NATURAL))
				p.batting.power_l = minf(p.batting.power_l + step, maxf(cap, RatingScale.NATURAL))
			"eye":
				p.batting.eye = minf(p.batting.eye + step, maxf(cap, RatingScale.NATURAL))
			"speed":
				p.batting.speed = minf(p.batting.speed + step, maxf(cap, RatingScale.NATURAL))
			"baserunning":
				p.batting.baserunning = minf(p.batting.baserunning + step, maxf(cap, RatingScale.NATURAL))
			"range":
				p.fielding.range = minf(p.fielding.range + step, maxf(cap, RatingScale.NATURAL))
			"hands":
				p.fielding.hands = minf(p.fielding.hands + step, maxf(cap, RatingScale.NATURAL))
			"arm":
				p.fielding.arm = minf(p.fielding.arm + step, maxf(cap, RatingScale.NATURAL))
			"control":
				if p.pitching != null:
					p.pitching.control = minf(p.pitching.control + step, maxf(cap, RatingScale.NATURAL))
			"command", "movement", "velocity":
				if p.pitching == null:
					continue
				for a: ArsenalPitch in p.pitching.arsenal:
					if key == "command":
						a.command = minf(a.command + step, maxf(cap, RatingScale.NATURAL))
					elif key == "movement":
						a.movement = minf(a.movement + step, maxf(cap, RatingScale.NATURAL))
					else:
						a.velo_avg += step * 0.2
						a.velo_max += step * 0.2
