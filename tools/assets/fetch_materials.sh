#!/usr/bin/env bash
# Fetches the surface textures and skies the parks and the equipment use (all CC0):
#   materials from ambientCG (ambientcg.com), 1K JPG: colour, normal (OpenGL), roughness;
#   skies from Poly Haven (polyhaven.com), 2K HDR, the "pure sky" kind (no ground).
# Downloads are kept under .tools/assets-dl; what the game reads is copied to
# game/assets/materials and game/assets/sky. Run from the project root:
#   tools/assets/fetch_materials.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DL="$ROOT/.tools/assets-dl"
OUT="$ROOT/game/assets/materials"
SKY="$ROOT/game/assets/sky"
mkdir -p "$DL/acg" "$DL/hdri" "$OUT" "$SKY"
# name in the game : ambientCG id : maps wanted
MATERIALS="grass:Grass001:Color,NormalGL,Roughness
dirt:Ground103:Color,NormalGL,Roughness
gravel:Gravel041:Color,NormalGL
concrete:Concrete034:Color,NormalGL,Roughness
leather:Leather037:NormalGL,Roughness
plastic:Plastic010:NormalGL,Roughness
metal:PaintedMetal004:NormalGL,Roughness
fence:Fence007A:Color,Opacity,NormalGL
facade_a:Facade018A:Color
facade_b:Facade006:Color
facade_c:Facade019A:Color
facade_d:Facade013:Color
facade_e:Facade005:Color
facade_night:Facade011:Color
container:CorrugatedSteel007A:Color,NormalGL
forest:Ground068:Color,NormalGL
bricks:Bricks105:Color,NormalGL
tiles:RoofingTiles013A:Color,NormalGL
rock:Rock064:Color,NormalGL
sand:Ground054:Color,NormalGL
asphalt:Asphalt033:Color,NormalGL"
while IFS=: read -r name id maps; do
  [ -f "$DL/acg/$id.zip" ] || curl -sL --max-time 180 -A "asset-fetch/1.0" -o "$DL/acg/$id.zip" "https://ambientcg.com/get?file=${id}_1K-JPG.zip"
  mkdir -p "$DL/acg/$id" && unzip -qo "$DL/acg/$id.zip" -d "$DL/acg/$id"
  for map in ${maps//,/ }; do
    src="$(ls "$DL/acg/$id"/*_"$map".jpg 2>/dev/null | head -1 || true)"
    if [ -z "$src" ]; then echo "fetch_materials: $id has no $map" >&2; continue; fi
    short="$(echo "$map" | sed 's/NormalGL/normal/; s/Color/color/; s/Roughness/rough/; s/Opacity/opacity/')"
    cp "$src" "$OUT/${name}_${short}.jpg"
  done
done <<< "$MATERIALS"
# time of day : Poly Haven id
SKIES="day:kloofendal_48d_partly_cloudy_puresky
dusk:kloppenheim_06_puresky
night:kloppenheim_02_puresky"
while IFS=: read -r time id; do
  [ -f "$DL/hdri/${id}_2k.hdr" ] || curl -sL --max-time 300 -A "asset-fetch/1.0" -o "$DL/hdri/${id}_2k.hdr" "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/${id}_2k.hdr"
  cp "$DL/hdri/${id}_2k.hdr" "$SKY/sky_$time.hdr"
done <<< "$SKIES"
cat > "$OUT/LICENSE.txt" <<'TXT'
Surface textures: ambientCG (ambientcg.com), Creative Commons CC0 1.0.
  grass Grass001, dirt Ground103, gravel Gravel041, concrete Concrete034, leather Leather037,
  plastic Plastic010, metal PaintedMetal004, fence Fence007A; building fronts Facade018A,
  Facade006, Facade019A, Facade013, Facade005 and (lit windows at night) Facade011; containers
  CorrugatedSteel007A; forested hills Ground068; Bricks105, RoofingTiles013A, Rock064,
  sand Ground054, Asphalt033.
Skies (../sky): Poly Haven (polyhaven.com), CC0: kloofendal_48d_partly_cloudy_puresky (day),
  kloppenheim_06_puresky (dusk), kloppenheim_02_puresky (night).
TXT
echo "fetch_materials: $(ls "$OUT"/*.jpg | wc -l) maps in game/assets/materials, $(ls "$SKY"/*.hdr | wc -l) skies in game/assets/sky"
