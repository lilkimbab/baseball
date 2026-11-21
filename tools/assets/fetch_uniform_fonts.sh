#!/usr/bin/env bash
# Fetches the lettering of real baseball uniforms into the local content pack
# (content-local/fonts/uniform/, not in git): free recreations of the faces teams sew onto
# their jerseys, which may be used privately but not passed on. The game uses them when they
# are there and falls back to the open-licence faces in game/assets/fonts/uniform/ when not
# (match/uniform_fonts.gd).
#
#   jersey_m54.ttf        full block: the numbers and names of most MLB and KBO clubs
#   mlb_tuscan.ttf        Tuscan block (split serifs): Boston's and Detroit's kind
#   ballpark_weiner.ttf   baseball script
#
# Sources and terms are written to content-local/SOURCES.md by hand (see there).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/content-local/fonts/uniform"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

fetch() {  # fetch <dafont id> <file inside the archive> <name to keep>
  local dir="$TMP/$1"
  mkdir -p "$dir"
  curl -sL -m 60 -A "Mozilla/5.0" -o "$dir/font.zip" "https://dl.dafont.com/dl/?f=$1"
  (cd "$dir" && unzip -o -q font.zip)
  cp "$dir/$2" "$OUT/$3"
  echo "fetch_uniform_fonts: $3"
}

fetch jersey_m54 "Jersey M54.ttf" jersey_m54.ttf
fetch mlb_tuscan "MLBTUSCA.TTF" mlb_tuscan.ttf
fetch ballpark_weiner "BALLW___.TTF" ballpark_weiner.ttf
