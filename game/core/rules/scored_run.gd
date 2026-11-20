class_name ScoredRun
extends RefCounted
## A run that counted, with what the scorer needs to know about it.

var runner: BaseRunner
## Counts against the pitcher's earned run average.
var earned := true
## The batter is credited with a run batted in.
var rbi := false
## Base the runner scored from (0 = the batter himself).
var from := 0
