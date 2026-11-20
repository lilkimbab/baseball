class_name Position
extends RefCounted
## Fielding positions and the labels used for them on the scorecard and on screen.

enum Kind { P, C, B1, B2, B3, SS, LF, CF, RF, DH, PH, PR }

## The nine places on the field, in scorecard order (1 = pitcher ... 9 = right field).
const FIELD: Array[Kind] = [Kind.P, Kind.C, Kind.B1, Kind.B2, Kind.B3, Kind.SS, Kind.LF, Kind.CF, Kind.RF]
const INFIELD: Array[Kind] = [Kind.B1, Kind.B2, Kind.B3, Kind.SS]
const OUTFIELD: Array[Kind] = [Kind.LF, Kind.CF, Kind.RF]

const _CODES: Array[String] = ["P", "C", "1B", "2B", "3B", "SS", "LF", "CF", "RF", "DH", "PH", "PR"]
const _LABELS: Array[String] = ["투", "포", "1", "2", "3", "유", "좌", "중", "우", "지", "타", "주"]
const _NAMES: Array[String] = ["투수", "포수", "1루수", "2루수", "3루수", "유격수", "좌익수", "중견수", "우익수", "지명타자", "대타", "대주자"]


static func code(kind: Kind) -> String:
	return _CODES[kind]


## One-character label used in lineups ("유" for shortstop).
static func label(kind: Kind) -> String:
	return _LABELS[kind]


static func name_of(kind: Kind) -> String:
	return _NAMES[kind]


## Scorecard number: 1 pitcher, 2 catcher, 3 first base ... 9 right field. 0 for the rest.
static func scoring_number(kind: Kind) -> int:
	return kind + 1 if kind <= Kind.RF else 0


## Reads a position code. "SP" and "RP" (starting and relief pitcher) are pitchers.
static func from_code(text: String) -> Kind:
	if text == "SP" or text == "RP":
		return Kind.P
	var at := _CODES.find(text)
	return Kind.DH if at < 0 else at as Kind


## Catchers and middle and third basemen throw right-handed: a left-hander's throw to first
## or second has to turn against the play.
static func needs_right_hand(kind: Kind) -> bool:
	return kind == Kind.C or kind == Kind.B2 or kind == Kind.B3 or kind == Kind.SS


static func is_field(kind: Kind) -> bool:
	return kind <= Kind.RF
