class_name PaResult
extends RefCounted
## How a plate appearance ended, and the scoring rules that follow from it.

enum Kind {
	NONE, STRIKEOUT, WALK, INTENTIONAL_WALK, HIT_BY_PITCH,
	SINGLE, DOUBLE, TRIPLE, HOME_RUN,
	GROUND_OUT, FLY_OUT, LINE_OUT, POP_OUT,
	SAC_BUNT, SAC_FLY, FIELDERS_CHOICE, REACHED_ON_ERROR, DOUBLE_PLAY, TRIPLE_PLAY,
	DROPPED_THIRD_STRIKE,
}

const _TEXT := {
	Kind.STRIKEOUT: "삼진", Kind.WALK: "볼넷", Kind.INTENTIONAL_WALK: "고의사구", Kind.HIT_BY_PITCH: "몸에 맞는 공",
	Kind.SINGLE: "안타", Kind.DOUBLE: "2루타", Kind.TRIPLE: "3루타", Kind.HOME_RUN: "홈런",
	Kind.GROUND_OUT: "땅볼", Kind.FLY_OUT: "뜬공", Kind.LINE_OUT: "직선타", Kind.POP_OUT: "내야 뜬공",
	Kind.SAC_BUNT: "희생 번트", Kind.SAC_FLY: "희생 플라이", Kind.FIELDERS_CHOICE: "야수 선택",
	Kind.REACHED_ON_ERROR: "실책 출루", Kind.DOUBLE_PLAY: "병살타", Kind.TRIPLE_PLAY: "삼중살",
	Kind.DROPPED_THIRD_STRIKE: "낫아웃",
}


static func text(kind: Kind) -> String:
	return _TEXT.get(kind, "")


static func is_hit(kind: Kind) -> bool:
	return kind == Kind.SINGLE or kind == Kind.DOUBLE or kind == Kind.TRIPLE or kind == Kind.HOME_RUN


## Bases a hit is worth: 1 to 4. Zero for anything else.
static func hit_bases(kind: Kind) -> int:
	match kind:
		Kind.SINGLE:
			return 1
		Kind.DOUBLE:
			return 2
		Kind.TRIPLE:
			return 3
		Kind.HOME_RUN:
			return 4
	return 0


static func hit_of_bases(bases: int) -> Kind:
	return [Kind.SINGLE, Kind.DOUBLE, Kind.TRIPLE, Kind.HOME_RUN][clampi(bases, 1, 4) - 1]


static func is_walk(kind: Kind) -> bool:
	return kind == Kind.WALK or kind == Kind.INTENTIONAL_WALK


## Counts as an at-bat: everything except walks, hit batsmen and sacrifices.
static func is_at_bat(kind: Kind) -> bool:
	return not (is_walk(kind) or kind == Kind.HIT_BY_PITCH or kind == Kind.SAC_BUNT or kind == Kind.SAC_FLY or kind == Kind.NONE)


static func is_strikeout(kind: Kind) -> bool:
	return kind == Kind.STRIKEOUT or kind == Kind.DROPPED_THIRD_STRIKE
