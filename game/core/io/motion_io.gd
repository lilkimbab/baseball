class_name MotionIO
extends RefCounted
## Reads data/motion.json into a MotionModel and data/fielding_positions.json into a
## FieldingAlignment.

const DEFAULT_PATH := "res://data/motion.json"
const ALIGNMENT_PATH := "res://data/fielding_positions.json"

static var _default: MotionModel
static var _alignment: FieldingAlignment


static func load_default() -> MotionModel:
	if _default == null:
		_default = load_file(DEFAULT_PATH)
	return _default


static func alignment() -> FieldingAlignment:
	if _alignment == null:
		_alignment = load_alignment(ALIGNMENT_PATH)
	return _alignment


static func load_file(path: String) -> MotionModel:
	var r := JsonIO.read_object(path)
	var m := MotionModel.new()
	m.top_speed = _pair(r, "top_speed_ms", m.top_speed)
	m.tau = _value(r, "acceleration_tau_s", m.tau)
	m.leave_box = _sides(r, "batter_leaves_box_s", m.leave_box)
	m.to_first = _sides(r, "batter_to_first_m", m.to_first)
	m.path_factor = _value(r, "base_path_factor", m.path_factor)
	m.rounding = _value(r, "rounding_base_s", m.rounding)
	m.slide_gain = _value(r, "slide_gain_m", m.slide_gain)
	var lead: Dictionary = r.get("lead_m", {})
	m.leads = Vector3(lead.get("first", m.leads.x), lead.get("second", m.leads.y), lead.get("third", m.leads.z))
	m.secondary_lead = _value(r, "secondary_lead_m", m.secondary_lead)
	m.runner_read = _pair(r, "runner_read_s", m.runner_read)
	m.two_out_jump = _value(r, "two_out_jump_s", m.two_out_jump)
	m.steal_jump = _pair(r, "steal_jump_s", m.steal_jump)
	m.delivery = _pair(r, "delivery_s", m.delivery)
	m.reaction = _pair(r, "reaction_s", m.reaction)
	m.outfield_reaction = _pair(r, "outfield_reaction_s", m.outfield_reaction)
	m.efficiency = _pair(r, "route_efficiency", m.efficiency)
	m.backward = _value(r, "backward_speed", m.backward)
	m.warning_track = _value(r, "warning_track_speed", m.warning_track)
	var reach: Dictionary = r.get("reach_m", {})
	m.reach_standing = reach.get("standing", m.reach_standing)
	m.reach_running = reach.get("running", m.reach_running)
	m.reach_diving = reach.get("diving", m.reach_diving)
	m.reach_high = reach.get("high", m.reach_high)
	m.reach_jump = reach.get("jump", m.reach_jump)
	m.transfer = _pair(r, "transfer_s", m.transfer)
	m.catcher_transfer = _pair(r, "catcher_transfer_s", m.catcher_transfer)
	m.outfield_transfer = _value(r, "outfield_extra_transfer_s", m.outfield_transfer)
	var throws: Dictionary = r.get("throw_kmh", {})
	m.throw_infield = Vector2(throws.get("infield_from", 112.0), throws.get("infield_to", 146.0))
	m.throw_outfield = Vector2(throws.get("outfield_from", 120.0), throws.get("outfield_to", 156.0))
	m.throw_catcher = Vector2(throws.get("catcher_from", 110.0), throws.get("catcher_to", 142.0))
	m.throw_pitcher = Vector2(throws.get("pitcher_from", 105.0), throws.get("pitcher_to", 135.0))
	m.throw_kept = _value(r, "throw_speed_kept", m.throw_kept)
	m.one_hop_beyond = _value(r, "one_hop_beyond_m", m.one_hop_beyond)
	m.relay_beyond = _value(r, "relay_beyond_m", m.relay_beyond)
	m.pivot = _pair(r, "pivot_s", m.pivot)
	m.tag = _value(r, "tag_s", m.tag)
	m.bang_bang_sd = _value(r, "bang_bang_sd_s", m.bang_bang_sd)
	m.judgment_sd = _value(r, "runner_judgment_sd_s", m.judgment_sd)
	var c: Dictionary = r.get("catch_chance", {})
	m.routine_slack = c.get("routine_slack_s", m.routine_slack)
	m.comfortable_slack = c.get("comfortable_slack_s", m.comfortable_slack)
	m.running_catch = Vector2(c.get("running_from", 0.9), c.get("running_to", 0.6))
	m.diving_catch = Vector2(c.get("diving_from", 0.5), c.get("diving_to", 0.1))
	m.diving_slack = c.get("diving_slack_s", m.diving_slack)
	m.air_half_slack = c.get("air_half_s", m.air_half_slack)
	m.air_width = c.get("air_width_s", m.air_width)
	m.wall_reach = c.get("wall_m", m.wall_reach)
	m.wall_cost = c.get("wall_s", m.wall_cost)
	var e: Dictionary = r.get("errors", {})
	m.fly_drop = e.get("fly_drop", m.fly_drop)
	m.ground_bobble = e.get("ground_bobble", m.ground_bobble)
	m.hard_bobble_extra = e.get("hard_ground_bobble_extra", m.hard_bobble_extra)
	m.bad_throw = e.get("bad_throw", m.bad_throw)
	m.rushed_throw = e.get("rushed_throw_factor", m.rushed_throw)
	var a: Dictionary = r.get("runner_aggression_s", {})
	m.aggression = Vector2(a.get("normal", 0.35), a.get("two_outs", 0.1))
	m.long_throw_scatter = _value(r, "long_throw_scatter_s", m.long_throw_scatter)
	var k: Dictionary = r.get("catcher", {})
	m.catcher_side = k.get("reach_side_m", m.catcher_side)
	m.catcher_low = k.get("reach_low_m", m.catcher_low)
	m.catcher_high = k.get("reach_high_m", m.catcher_high)
	m.block = Vector2(k.get("block_from", m.block.x), k.get("block_to", m.block.y))
	m.wild_get_away = k.get("wild_get_away_s", m.wild_get_away)
	var h: Dictionary = r.get("hit_by_pitch", {})
	m.body_radius = h.get("body_radius_m", m.body_radius)
	m.body_offset = h.get("body_offset_m", m.body_offset)
	m.body_ankle = h.get("ankle_m", m.body_ankle)
	m.body_shoulder_share = h.get("shoulder_share", m.body_shoulder_share)
	m.dodge_chance = h.get("dodge_chance", m.dodge_chance)
	return m


static func load_alignment(path: String) -> FieldingAlignment:
	var root := JsonIO.read_object(path)
	var a := FieldingAlignment.new()
	var normal: Dictionary = root.get("normal", {})
	for code: String in normal:
		var v: Array = normal[code]
		a.spots[code] = Vector2(v[0], v[1])
	for variant: String in FieldingAlignment.VARIANTS:
		var moves: Dictionary = root.get(variant, {})
		for code: String in moves:
			var v: Array = moves[code]
			a.shifts["%s:%s" % [variant, code]] = Vector2(v[0], v[1])
	var hold: Array = root.get("holding_runner", {}).get("1B", [27.4, 44.0])
	a.hold_first = Vector2(hold[0], hold[1])
	a.pull_shift = _value(root, "pull_shift_deg", a.pull_shift)
	a.outfield_margin = _value(root, "outfield_margin_m", a.outfield_margin)
	return a


static func _value(r: Dictionary, key: String, fallback: float) -> float:
	var d: Dictionary = r.get(key, {})
	return d.get("value", fallback)


static func _pair(r: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var d: Dictionary = r.get(key, {})
	return Vector2(d.get("from", fallback.x), d.get("to", fallback.y))


static func _sides(r: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var d: Dictionary = r.get(key, {})
	return Vector2(d.get("right", fallback.x), d.get("left", fallback.y))
