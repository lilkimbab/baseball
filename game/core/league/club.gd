class_name Club
extends RefCounted
## The player's club in the manager league (docs/02 section 5, docs/13 S7-9): points, the
## scouting level and today's candidates, traits on players and in the bag, who trains today,
## how much each player has grown, and which players came up through the club (its second-team
## prospects and the players it scouted: the franchise colour counts them on the first team)
## or were raised by it (grade up by training: the development colour).

var team_id := ""
var points := 0
var scout_level := 1
## Player id → (trait index, tier 0..2).
var traits: Dictionary[String, Vector2i] = {}
## Traits not on anyone: (trait index, tier).
var bag: Array[Vector2i] = []
var homegrown: Dictionary[String, bool] = {}
var developed: Dictionary[String, bool] = {}
## Rating points each player has gained by training, against his headroom.
var gained: Dictionary[String, float] = {}
## Today's training: player id → focus ("batting", "running", "fielding", "stuff", "control",
## "breaking").
var training: Dictionary[String, String] = {}
## Today's scouting candidates; one may be signed a day.
var candidates: Array[Player] = []
var signed_today := false
## Another scouting report was bought today.
var reported_today := false


static func for_team(team: Team) -> Club:
	var c := Club.new()
	c.team_id = team.id
	for p: Player in team.second_team():
		c.homegrown[p.id] = true
	return c


# --- Traits ---


## Puts a trait from the bag on a player of the right kind; the one he had goes to the bag.
func equip(p: Player, bag_index: int, rules: ClubRules) -> bool:
	if bag_index < 0 or bag_index >= bag.size():
		return false
	var item := bag[bag_index]
	var def := rules.traits[item.x]
	if (def.kind == &"pitcher") != p.is_pitcher():
		return false
	bag.remove_at(bag_index)
	if traits.has(p.id):
		bag.append(traits[p.id])
	traits[p.id] = item
	return true


func unequip(player_id: String) -> void:
	if traits.has(player_id):
		bag.append(traits[player_id])
		traits.erase(player_id)


## Two of the same trait at the same tier make one a tier higher (up to the third).
func merge(i: int, j: int, rules: ClubRules) -> bool:
	if i == j or i < 0 or j < 0 or i >= bag.size() or j >= bag.size():
		return false
	var a := bag[i]
	var b := bag[j]
	if a != b or a.y >= rules.trait_tiers.size() - 1:
		return false
	bag.remove_at(maxi(i, j))
	bag.remove_at(mini(i, j))
	bag.append(Vector2i(a.x, a.y + 1))
	return true


## Buys a random first-tier trait for the bag with points (docs/02 section 5.4: traits come
## as rewards; until there are other rewards, points buy them). Returns its index or −1.
func buy_trait(rules: ClubRules, rng: Rng) -> int:
	var price := int(rules.points.get("trait", 0))
	if points < price or rules.traits.is_empty():
		return -1
	points -= price
	var pick := rng.next_int(rules.traits.size())
	bag.append(Vector2i(pick, 0))
	return pick


## The first two bag items that can be merged, or (−1, −1).
func mergeable(rules: ClubRules) -> Vector2i:
	for i: int in bag.size():
		for j: int in range(i + 1, bag.size()):
			if bag[i] == bag[j] and bag[i].y < rules.trait_tiers.size() - 1:
				return Vector2i(i, j)
	return Vector2i(-1, -1)


## Rating changes from a player's trait.
func trait_deltas(p: Player, rules: ClubRules) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	if not traits.has(p.id):
		return out
	var item := traits[p.id]
	var def := rules.traits[item.x]
	var tier := rules.trait_tiers[clampi(item.y, 0, rules.trait_tiers.size() - 1)]
	for key: String in def.effect:
		out[key] = def.effect[key] * tier
	return out


# --- Training ---


func assign_training(player_id: String, focus: String, rules: ClubRules) -> bool:
	if not rules.focus.has(focus):
		return false
	if not training.has(player_id) and training.size() >= rules.train_per_day:
		return false
	training[player_id] = focus
	return true


## Today's training: each assigned player grows in his focus, faster when young, until his
## headroom (which also shrinks with age) is used up. Returns player id → points gained.
## A player whose grade goes up this way counts as raised by the club.
func train(team: Team, age_of: Callable, rules: ClubRules, ovr: Overall, catalog: Dictionary[StringName, PitchType], boost: float = 0.0) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	for id: String in training:
		var p := team.player(id)
		if p == null:
			continue
		var age: int = age_of.call(p)
		var room := ClubRules.by_age(rules.headroom, age) - float(gained.get(id, 0.0))
		if room <= 0.0:
			continue
		var step := minf(rules.train_gain * ClubRules.by_age(rules.age_rates, age) * (1.0 + boost), room)
		var before := rules.grade_of(ClubRules.player_ovr(p, ovr, catalog)).name
		Training.grow(p, rules.focus[training[id]], step)
		gained[id] = float(gained.get(id, 0.0)) + step
		out[id] = step
		var after := rules.grade_of(ClubRules.player_ovr(p, ovr, catalog)).name
		if rules.grade_rank(after) < rules.grade_rank(before):
			developed[id] = true
	training.clear()
	return out


# --- Scouting ---


## Raises the scouting level for points: better candidates (ClubRules.scout_level_bonus) and
## a truer read of the room they have to grow. (Club points had one use, traits, and piled up.)
func upgrade_scout(rules: ClubRules) -> bool:
	if scout_level >= rules.scout_max_level or rules.scout_upgrade.is_empty():
		return false
	var price := rules.scout_upgrade[mini(scout_level - 1, rules.scout_upgrade.size() - 1)]
	if points < price:
		return false
	points -= price
	scout_level += 1
	return true


## The price of raising the scouting level now (0 at the top).
func scout_upgrade_price(rules: ClubRules) -> int:
	if scout_level >= rules.scout_max_level or rules.scout_upgrade.is_empty():
		return 0
	return rules.scout_upgrade[mini(scout_level - 1, rules.scout_upgrade.size() - 1)]


## Pays for another scouting report today (a new set of candidates; once a day). The season
## draws them (Season.refresh_candidates).
func buy_report(rules: ClubRules) -> bool:
	var price := int(rules.points.get("scout_report", 60))
	if reported_today or points < price:
		return false
	points -= price
	reported_today = true
	return true


## Signs one of today's candidates to the second team. One a day; the second team has room
## for rules.second_team_size.
func sign(index: int, team: Team, rules: ClubRules) -> Player:
	if signed_today or index < 0 or index >= candidates.size():
		return null
	if team.second_team().size() >= rules.second_team_size:
		return null
	var p := candidates[index]
	candidates.remove_at(index)
	if team.registered.is_empty():
		for q: Player in team.players:
			team.registered.append(q.id)
	team.players.append(p)
	homegrown[p.id] = true
	signed_today = true
	return p


## Lets a second-team player go, for a few points.
func release(player_id: String, team: Team, rules: ClubRules) -> bool:
	if team.is_registered(player_id):
		return false
	for i: int in team.players.size():
		if team.players[i].id == player_id:
			team.players.remove_at(i)
			traits.erase(player_id)
			points += int(rules.points.get("release", 0))
			return true
	return false


func earn(result: int, postseason: bool, rules: ClubRules, share: float = 1.0) -> void:
	var key := "tie"
	if postseason and result > 0:
		key = "postseason_win"
	elif result > 0:
		key = "win"
	elif result < 0:
		key = "loss"
	points += roundi(int(rules.points.get(key, 0)) * share)
