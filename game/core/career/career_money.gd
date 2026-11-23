class_name CareerMoney
extends RefCounted
## What a pro's money buys (the user, 2026-11-23: "make the salary worth earning"). As in other
## career modes — NBA 2K's MyCAREER pays in the currency that buys a player's upgrades, EA FC's
## Player Career sells boosts in its shop — the salary here buys what makes him better, each in
## three grades priced so that a rookie can afford the first, a regular the second and a star the
## third: the next raise or the free agent's bonus is the way to the next grade.
##
## - Training (TRAINING, for the season): more growth points from every game.
## - Conditioning (CONDITIONING, for the season): fewer days out when hurt; from his thirties, a
##   gentler decline in the winter.
## - Giving (DONATIONS, once a season): popularity, which brings all-star votes, a better market
##   in free agency and his own club's loyalty.
## - Gear: the shop's gear for the career's player, paid in won at SHOP_RATE (ShopScreen).
## Each grade bought pays the difference from the one he has this season. Money in 10,000 won.

## [name, price, what it does (growth points × 1 + it)].
const TRAINING: Array = [
	["개인 트레이너", 2000, 0.1],
	["전담 코치진", 10000, 0.2],
	["해외 퍼포먼스 센터", 50000, 0.35],
]
## [name, price, injury days × (1 − it), the winter's decline × (1 − it)].
const CONDITIONING: Array = [
	["체력 관리 프로그램", 3000, 0.2, 0.25],
	["전담 트레이닝 팀", 15000, 0.35, 0.5],
	["프리미엄 메디컬 팀", 60000, 0.5, 0.75],
]
## [name, price, popularity].
const DONATIONS: Array = [
	["유소년 야구 후원", 5000, 5.0],
	["지역 사회 기부", 30000, 20.0],
	["야구 꿈나무 재단", 100000, 60.0],
]
## Won for one shop point: gear of 400 points costs 4,000만 원.
const SHOP_RATE := 10


static func catalog(kind: String) -> Array:
	match kind:
		"training":
			return TRAINING
		"conditioning":
			return CONDITIONING
	return DONATIONS


## The grade he has this season of `kind` (0 none).
static func grade(cs: CareerSeason, kind: String) -> int:
	match kind:
		"training":
			return cs.trainer
		"conditioning":
			return cs.conditioning
	return cs.donation


## What the grade costs him now: its price less what he paid this season for a lower one.
static func price_now(cs: CareerSeason, kind: String, level: int) -> int:
	var list := catalog(kind)
	var price: int = list[level - 1][1]
	if kind == "donations":
		return price
	return maxi(price - int(cs.invest_paid.get(kind, 0)), 0)


## Why it cannot be bought ("" when it can).
static func problem(cs: CareerSeason, kind: String, level: int) -> String:
	if cs.season.school:
		return "프로 입단 후에 이용할 수 있습니다"
	if level < 1 or level > catalog(kind).size():
		return "없는 상품입니다"
	if kind == "donations" and cs.donation > 0:
		return "이번 시즌에는 이미 기부했습니다"
	if kind != "donations" and grade(cs, kind) >= level:
		return "이용 중입니다" if grade(cs, kind) == level else "더 좋은 등급을 이용 중입니다"
	var short := price_now(cs, kind, level) - cs.career.money
	if short > 0:
		return "%s 원 부족" % FreeAgency.money(short)
	return ""


## Pays for it and puts it to work. What to say.
static func buy(cs: CareerSeason, kind: String, level: int) -> String:
	var why := problem(cs, kind, level)
	if why != "":
		return why
	var item: Array = catalog(kind)[level - 1]
	var cost := price_now(cs, kind, level)
	var c := cs.career
	c.money -= cost
	match kind:
		"training":
			cs.trainer = level
			cs.invest_paid["training"] = int(item[1])
		"conditioning":
			cs.conditioning = level
			cs.invest_paid["conditioning"] = int(item[1])
		_:
			cs.donation = level
			c.donated += cost
			c.popularity += float(item[2])
	apply(cs)
	cs.log.append("%d일: %s (%s 원)" % [cs.season.day + 1, str(item[0]), FreeAgency.money(cost)])
	if kind == "donations":
		return "%s에 기부했습니다. (인기도 +%d)" % [str(item[0]), int(item[2])]
	return "%s 이용을 시작했습니다. (이번 시즌)" % str(item[0])


## Growth points of a game, by his trainer.
static func growth_share(cs: CareerSeason) -> float:
	return 1.0 + (float(TRAINING[cs.trainer - 1][2]) if cs.trainer > 0 else 0.0)


## The season's effects where the league keeps them (injury days; the winter's decline is set as
## the winter begins: CareerSession).
static func apply(cs: CareerSeason) -> void:
	if cs.career == null or cs.career.player == null or cs.season.injuries == null:
		return
	var id := cs.career.player.id
	if cs.conditioning > 0:
		cs.season.injuries.scales[id] = 1.0 - float(CONDITIONING[cs.conditioning - 1][2])
	else:
		cs.season.injuries.scales.erase(id)


static func decline_share(cs: CareerSeason) -> float:
	return 1.0 - (float(CONDITIONING[cs.conditioning - 1][3]) if cs.conditioning > 0 else 0.0)


## The next grade he cannot afford yet and how far he is from it (for the screen: "연봉이 오르면").
static func next_goal(cs: CareerSeason) -> String:
	for kind: String in ["training", "conditioning"]:
		var have := grade(cs, kind)
		var list := catalog(kind)
		if have < list.size():
			var short := price_now(cs, kind, have + 1) - cs.career.money
			if short > 0:
				return "%s까지 %s 원 더 필요" % [str(list[have][0]), FreeAgency.money(short)]
	return ""
