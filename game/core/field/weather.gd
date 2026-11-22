class_name Weather
extends RefCounted
## The weather of a game (docs/08 R3): the sky, how warm and damp it is, and the wind — its
## speed and where it blows from. Warm, damp air is thinner and carries a ball farther (Air);
## the wind carries it with it (BallSim, PhysicsConfig.wind). Under a dome there is no wind
## and the air is the dome's.
##
## A game's weather is drawn from the month and the hour, the same for the same park and day.
## The numbers follow Seoul's climate over the season (KMA normals, 1991-2020): mean daily
## highs of 18 °C in April, 23 in May, 27 in June, 29 in July and August, 26 in September and
## 20 in October; humidity 55-80 % (wettest in the rainy season, late June to July); winds at
## ground level mostly 1-4 m/s. In a ballpark the wind over the field is a little less.
##
## The wind comes from any quarter, as likely in as out. The parks all face north-east (the
## sun behind the batter), so the season's westerlies would blow out almost every game; the
## league's targets are real seasons, wind and all, and a wind that mostly blew out counted
## it twice (1,600 games: home runs +42 %). Drawn evenly, it leaves the league as it was and
## any one game as windy as the day.

enum Cover { CLEAR, CLOUDY, OVERCAST }

var cover: Cover = Cover.CLEAR
var temp_c := 22.0
var humidity := 60.0
## Wind speed (m/s) and the compass bearing it blows FROM (degrees, 0 north, 90 east).
var wind_speed := 0.0
var wind_from_deg := 270.0
var indoor := false

## Mean daily high (°C) and humidity (%) by month, April to October.
const MONTH_HIGH := {4: 18.0, 5: 23.5, 6: 27.5, 7: 29.0, 8: 29.5, 9: 26.0, 10: 20.0}
const MONTH_HUMIDITY := {4: 56.0, 5: 62.0, 6: 70.0, 7: 80.0, 8: 77.0, 9: 70.0, 10: 64.0}

## A dome's air.
const DOME_TEMP := 22.0
const DOME_HUMIDITY := 50.0
## Strongest wind drawn (m/s).
const WIND_MAX := 8.0


## The month (4-10) a game day of the season falls in: day 0 is the first of April.
static func month_of(game_day: int) -> int:
	return clampi(4 + game_day / 30, 4, 10)


## The weather for a game at `park` on `game_day` at `time` (&"day", &"dusk", &"night").
static func for_game(park: StadiumDef, game_day: int, time: StringName, rng: Rng) -> Weather:
	var w := Weather.new()
	if park != null and park.roof == &"dome":
		w.indoor = true
		w.temp_c = DOME_TEMP
		w.humidity = DOME_HUMIDITY
		w.cover = Cover.CLEAR
		return w
	var month := month_of(game_day)
	var high: float = MONTH_HIGH[month]
	# A night game is played some 4-6 degrees below the day's high.
	var drop: float = {&"day": 0.5, &"dusk": 2.5, &"night": 5.0}.get(time, 0.5)
	w.temp_c = high - drop + rng.next_normal() * 2.5
	w.humidity = clampf(float(MONTH_HUMIDITY[month]) + rng.next_normal() * 8.0, 30.0, 95.0)
	var roll := rng.next_float()
	var wet := 0.25 if (month == 7 or month == 6) else 0.12
	if roll < wet:
		w.cover = Cover.OVERCAST
		w.humidity = minf(w.humidity + 10.0, 95.0)
		w.temp_c -= 1.5
	elif roll < wet + 0.3:
		w.cover = Cover.CLOUDY
	# Wind: mostly light, now and then a real breeze.
	w.wind_speed = clampf(absf(rng.next_normal()) * 2.2 + rng.next_float() * 0.6, 0.0, WIND_MAX)
	w.wind_from_deg = rng.next_range(0.0, 360.0)
	return w


## The wind as a velocity in field coordinates (x toward first base, y toward centre field),
## for a park facing `orientation_deg` (the compass bearing from home plate to centre field).
func wind_field(orientation_deg: float) -> Vector3:
	if indoor or wind_speed <= 0.0:
		return Vector3.ZERO
	var toward := deg_to_rad(wind_from_deg + 180.0 - orientation_deg)
	return Vector3(sin(toward), cos(toward), 0.0) * wind_speed


## How much of the wind blows out toward centre field (m/s; negative: in from it).
func wind_out(orientation_deg: float) -> float:
	return wind_field(orientation_deg).y


## The air of this day at a park `elevation_m` up.
func physics(base: PhysicsConfig, orientation_deg: float, elevation_m: float = 0.0) -> PhysicsConfig:
	var cfg := Air.config_for(base, temp_c, elevation_m, humidity)
	cfg.wind = wind_field(orientation_deg)
	return cfg


## One line for the screen: "맑음 24° · 바람 3m/s 외야 쪽으로".
func describe(orientation_deg: float) -> String:
	var sky_text: String = {Cover.CLEAR: "맑음", Cover.CLOUDY: "구름", Cover.OVERCAST: "흐림"}[cover]
	if indoor:
		return "돔 %d°" % roundi(temp_c)
	var line := "%s %d°" % [sky_text, roundi(temp_c)]
	if wind_speed < 0.8:
		return line + " · 바람 거의 없음"
	return line + " · 바람 %dm/s %s" % [roundi(wind_speed), wind_words(orientation_deg)]


## Which way the wind blows, as the field sees it.
func wind_words(orientation_deg: float) -> String:
	var v := wind_field(orientation_deg)
	var az := rad_to_deg(atan2(v.x, v.y))
	if absf(az) <= 30.0:
		return "외야 쪽으로"
	if absf(az) >= 150.0:
		return "홈 쪽으로"
	if az > 0.0:
		return "1루 쪽으로" if az > 60.0 else "우익수 쪽으로"
	return "3루 쪽으로" if az < -60.0 else "좌익수 쪽으로"
