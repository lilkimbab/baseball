class_name Training
extends RefCounted
## Growth of a player's ratings (docs/02 section 5.4): the club's daily training and, later,
## the career mode's. Each rating in the focus goes up by the step; pitches' movement and
## command for all his pitches, speed in km/h at a fifth of the step.


static func grow(p: Player, ratings: PackedStringArray, step: float) -> void:
	for key: String in ratings:
		match key:
			"contact":
				p.batting.contact_r = minf(p.batting.contact_r + step, 99.0)
				p.batting.contact_l = minf(p.batting.contact_l + step, 99.0)
			"power":
				p.batting.power_r = minf(p.batting.power_r + step, 99.0)
				p.batting.power_l = minf(p.batting.power_l + step, 99.0)
			"eye":
				p.batting.eye = minf(p.batting.eye + step, 99.0)
			"speed":
				p.batting.speed = minf(p.batting.speed + step, 99.0)
			"baserunning":
				p.batting.baserunning = minf(p.batting.baserunning + step, 99.0)
			"range":
				p.fielding.range = minf(p.fielding.range + step, 99.0)
			"hands":
				p.fielding.hands = minf(p.fielding.hands + step, 99.0)
			"arm":
				p.fielding.arm = minf(p.fielding.arm + step, 99.0)
			"control":
				if p.pitching != null:
					p.pitching.control = minf(p.pitching.control + step, 99.0)
			"command", "movement", "velocity":
				if p.pitching == null:
					continue
				for a: ArsenalPitch in p.pitching.arsenal:
					if key == "command":
						a.command = minf(a.command + step, 99.0)
					elif key == "movement":
						a.movement = minf(a.movement + step, 99.0)
					else:
						a.velo_avg += step * 0.2
						a.velo_max += step * 0.2
