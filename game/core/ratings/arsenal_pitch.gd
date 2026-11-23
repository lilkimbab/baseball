class_name ArsenalPitch
extends RefCounted
## One pitch a pitcher throws.

## Pitch type id from data/pitch_types.json.
var type: StringName = &"four_seam"
var velo_avg := 144.0
var velo_max := 149.0
## How much it moves compared with an average pitch of its type, 1..99.
var movement := 50.0
## Control of this pitch on top of the pitcher's control, 1..99.
var command := 50.0
## Share of all pitches thrown, 0..1.
var usage := 0.5
## His share of it by the count (from the pitch table: tools/kbo/pitch_mix.py):
## [even, ahead (more strikes than balls), behind (more balls)]. Empty: the game's usual lean
## by the count (AiPitcher).
var by_count := PackedFloat32Array()
