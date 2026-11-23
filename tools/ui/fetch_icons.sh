#!/usr/bin/env bash
# Fetches the menu icons: Phosphor Icons (MIT licence, phosphoricons.com), the "fill" weight,
# recoloured white so the game tints them. Run from the project root:
#   tools/ui/fetch_icons.sh
# The list below is every icon the menus use; add a name and run again for another.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/game/ui/icons"
TMP="$(mktemp -d)"
ICONS="house baseball baseball-helmet trophy user user-circle users-three target storefront gear-six
floppy-disk arrow-left caret-left caret-right x check play fast-forward calendar-blank
chart-bar chart-line-up list-numbers lightning star coins coin shopping-cart sun moon cloud
wind sliders-horizontal monitor speaker-high eye keyboard mouse info warning lock
arrows-clockwise binoculars barbell shield sneaker-move crosshair medal crown flag-pennant
clock handshake student graduation-cap ranking table plus minus trash timer
person-simple-throw person-simple-run hand-fist strategy identification-card article swap
arrow-right stack fire drop sparkle tag gift chart-polar arrow-u-up-left door-open power
skip-forward list-bullets funnel"
(cd "$TMP" && npm pack @phosphor-icons/core@2.1.1 >/dev/null 2>&1 && tar -xzf phosphor-icons-core-2.1.1.tgz)
mkdir -p "$OUT"
for name in $ICONS; do
  src="$TMP/package/assets/fill/$name-fill.svg"
  if [ ! -f "$src" ]; then echo "fetch_icons: no icon named $name" >&2; continue; fi
  sed 's/fill="currentColor"/fill="#ffffff"/g' "$src" > "$OUT/$name.svg"
done
cp "$TMP/package/LICENSE" "$OUT/LICENSE-phosphor.txt"
rm -rf "$TMP"
echo "fetch_icons: $(ls "$OUT"/*.svg | wc -l) icons in game/ui/icons (Phosphor, MIT)"
