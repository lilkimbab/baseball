class_name CareerPlayer
extends RefCounted
## The player of the career mode: the Player himself and what the career
## keeps about him — his position and type, his club and whether he is on its first team,
## growth points per field, popularity, how he looks, and how often he has thrown each pitch.

## The fields growth points are earned and spent in, each only on its own ratings.
const FIELDS: Array[String] = ["batting", "fielding", "running", "pitching"]

var player: Player
## "SP", "RP", "CL", "C", "1B", ... ("CL" is a reliever who closes).
var position := ""
var type_id := ""
var team_id := ""
var first_team := false
var appearance: Dictionary[String, String] = {}
var gp: Dictionary[String, float] = {"batting": 0.0, "fielding": 0.0, "running": 0.0, "pitching": 0.0}
var popularity := 0.0
## Points from reward boxes, and gear he has (name → rating it adds to).
var points := 0
## How he came into the pros ("2027 KBO 신인 드래프트 2라운드 3순위", "육성선수 계약"; "" for a
## career begun in the pros) and the bonus he signed for (10,000 won).
var drafted := ""
var signing_bonus := 0
## His pro career across seasons (CareerContract): seasons played, his money and this year's
## salary (10,000 won), the first-team days of each season (the KBO's FA clock), the seasons
## he needs for free agency (eight from high school, seven from college), and a line for each
## season gone ([year, club, first-team days, line]).
var pro_years := 0
var money := 0
var salary := 3000
var first_days: Array[int] = []
var fa_years := 8
var free_agent_done := false
## His deal (CareerFA): the years left of a deal of several years (0: signed year by year; the
## salary is fixed while it runs), its signing bonus and total, its option ([money a year, what
## he has to do]: CareerFA.OPTIONS), and what kind it was ("FA", "비FA 다년", "").
var contract_years := 0
var contract_length := 0
var contract_bonus := 0
var contract_total := 0
var contract_option: Array = []
var contract_kind := ""
## Free agency: how many times he has been one, and from which of his seasons (first_days) the
## clock runs again (NEXT_FA seasons after a deal).
var fa_count := 0
var fa_since := 0
## His money's story: all he has earned (salary, bonuses, prizes, options) and given away.
var earned := 0
var donated := 0
## Not kept by his club this winter (CareerContract): another club signs him.
var released := false
var seasons: Array = []
## His commemorative balls (Milestones): [id, year, day, the opponent], in the order reached.
var milestones: Array = []
## His games of the seasons gone, each [year, day, opponent, home, result, kind, numbers,
## where] (GameLog with the year in front); this season's are on the season.
var game_log: Array = []
## Retired (CareerSession.retire): the career is over.
var retired := false
## His story (CareerLegacy): the moments the flashback at his farewell shows ([year, kind,
## title, line, club id]), his honours (titles [year, name], all-star selections, championships'
## years, deals [year, line]), his best salary; the farewell tour (his last season announced, the
## gifts the clubs gave [club id, gift]); and what his retirement settled (his grade, the reward
## paid, his number retired).
var moments: Array = []
var titles_won: Array = []
var all_stars := 0
var championships: Array = []
var deals: Array = []
var best_salary := 0
var final_season := false
var tour_gifts: Array = []
var legacy_grade := ""
var legacy_reward := 0
var number_retired := false
var gear: Dictionary[String, String] = {}
## Game ratings this season.
var ratings := PackedFloat64Array()
var pitch_uses: Dictionary[StringName, int] = {}


func is_pitcher() -> bool:
	return CareerRules.is_pitching_position(position)


## Joins a club's second team (a rookie starts there).
func join(team: Team) -> void:
	team_id = team.id
	if team.registered.is_empty():
		for p: Player in team.players:
			team.registered.append(p.id)
	team.players.append(player)
	first_team = false
