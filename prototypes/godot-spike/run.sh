#!/usr/bin/env bash
# Godot feasibility checks. Usage: ./run.sh  (expects the Godot binary in ../../.tools)
set -e
cd "$(dirname "$0")"
G="${GODOT:-../../.tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64}"
"$G" --headless --path . --import >/dev/null 2>&1 || true
echo "## (a) script ball physics";      "$G" --headless --path . --script res://spike_core.gd
echo "## (b) engine collision queries"; "$G" --headless --path . --script res://spike_scene.gd
echo "## (c) render to PNG";            SPIKE_OUT="$PWD/render-check.png" "$G" --path . --rendering-method mobile --rendering-driver vulkan --resolution 1280x720 --script res://spike_render.gd
