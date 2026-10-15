#!/usr/bin/env bash
# Regenerates textures and exports the 3D models as scenes.
# Usage: GODOT=/path/to/godot tools/build_assets.sh   (run from the game folder)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
python3 tools/gen_textures.py
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script res://tools/export_models.gd
