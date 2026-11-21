#!/usr/bin/env bash
# Makes the pictures on the menus' mode cards from the game's own captures (docs/05 section 5):
# run the capture tools first (they write under build/), then this crops them to cards.
#   ./dev tool-win closeup_shot build/look2/body.png
#   ./dev tool-win closeup_shot build/look2/catcher2.png --subject catcher
#   ./dev tool-win stadium_shots build/crowd2/park --park grand_park
#   ./dev tool-win motion_shots build/forms2/pitch --who pitch --view side --eye 4.2,1.1,-0.9 --centre 0,1.0,-0.9 --fov 34
#   ./dev tool-win motion_shots build/forms2/swing --who swing --view side --eye 3.2,1.1,-0.3 --centre 0,1.0,-0.1 --fov 34
#   tools/ui/make_art.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FFMPEG="$ROOT/.tools/ffmpeg/node_modules/ffmpeg-static/ffmpeg"
OUT="$ROOT/game/ui/art"
mkdir -p "$OUT"
card() { # name, source, crop filter
  if [ -f "$ROOT/$2" ]; then
    "$FFMPEG" -loglevel error -y -i "$ROOT/$2" -vf "$3,scale=960:540:force_original_aspect_ratio=increase,crop=960:540,eq=contrast=1.08:saturation=1.12" -q:v 3 "$OUT/$1.jpg"
    echo "make_art: $1.jpg"
  else
    echo "make_art: missing $2" >&2
  fi
}
card exhibition build/look2/body.png "crop=1000:562:200:100"
card league build/crowd2/park_grand_park_day_high.png "crop=iw:ih*0.8:0:ih*0.1"
card career build/forms2/pitch_side_09.png "crop=1000:562:140:60"
card practice build/forms2/swing_side_10.png "crop=1000:562:160:20"
card shop build/look2/catcher2.png "crop=1000:562:180:60"
card park build/crowd2/park_grand_park_day_outfield.png "crop=iw:ih*0.8:0:ih*0.1"
