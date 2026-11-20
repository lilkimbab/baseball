class_name FlowOutcome
extends RefCounted
## What GameFlow did with one event, for the scorer and the play-by-play. Fields named
## *_before describe the moment before the event.

var batting_before := 0
var inning_before := 1
var top_before := true
var outs_before := 0
var batter_id := ""
var pitcher_id := ""
var score_before := PackedInt32Array([0, 0])
## Player on each moving base, aligned with the event's moves ("" if nobody was there).
var runner_ids := PackedStringArray()
## 1 where the move was carried out, 0 where it was not (it came after the third out or after
## the winning run), aligned with the event's moves.
var applied := PackedByteArray()
var scored: Array[ScoredRun] = []
var outs_made := 0
## Bases credited to the batter for a hit. Less than the hit's own worth on a game-ending hit
## that is not a home run: the batter gets as many bases as the winning run advanced.
var credited_bases := 0
## Runners left on base when the half-inning ended.
var left_on_base := 0
var half_over := false
var game_over := false
var walk_off := false
## Who the scorer charges for this plate appearance. Usually the batter and pitcher in the
## game, but a strikeout completed by a pinch hitter who came in with two strikes is the first
## batter's, and a walk issued by a reliever who came in with the count in the batter's favour
## (2-0, 2-1, 3-0, 3-1, 3-2) is the first pitcher's.
var charged_batter_id := ""
var charged_pitcher_id := ""
## For a pitch: the plate appearance it completed, if any (a walk or a strikeout).
var completes: PaResult.Kind = PaResult.Kind.NONE
