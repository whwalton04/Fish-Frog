#!/usr/bin/env bash
# Exports the "Web" preset and force-pushes it to the gh-pages branch for GitHub Pages.
# Needs the standard (non-.NET) Godot editor, since .NET builds can't export to web.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$HOME/.local/opt/godot-4.7.2/godot}"
OUT=build/web
REMOTE=$(git remote get-url origin)

rm -rf "$OUT"
mkdir -p "$OUT"
"$GODOT" --headless --import
"$GODOT" --headless --export-release "Web" "$OUT/index.html"
touch "$OUT/.nojekyll"

cd "$OUT"
git init -q -b gh-pages
git add -A
git commit -q -m "Web build $(date -u +%F)"
git push -f "$REMOTE" gh-pages
rm -rf .git
