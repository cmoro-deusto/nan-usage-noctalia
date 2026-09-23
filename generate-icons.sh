#!/usr/bin/env bash
# Regenerate the plugin's icon rasters from the SVG beside them.
#
# The plugin draws PNGs, not the SVG: whether the shell's Qt build can render an
# SVG depends on its image plugins being installed, and an icon that silently
# does not appear is worse than a slightly larger file. Three variants come out
# of one source:
#
#   nan.png              the logo as NaN draws it (icon_style = "color")
#   nan-ghost-white.png  the same silhouette in white, for a dark theme
#   nan-ghost-black.png  and in black, for a light one
#
# The ghost pair exists because a coloured mark in the middle of a row of theme
# glyphs looks pasted on; "ghost" picks the one that matches the theme, which is
# what `noctalia.isDarkMode()` tells the plugin.
#
#   ./generate-icons.sh        # from anywhere; it works next to this script
#
# Needs rsvg-convert (librsvg). Run it again if nan.svg changes.
set -euo pipefail

# The plugin directory is next to this script; it holds the SVG and receives the
# rasters, since that is what the plugin ships.
HERE="$(cd "$(dirname "$0")" && pwd)/nan-usage"
SVG="$HERE/nan.svg"
SIZE=96

for tool in rsvg-convert; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf '%s is not installed (librsvg); nothing was written\n' "$tool" >&2
        exit 1
    }
done

[ -f "$SVG" ] || { printf 'no %s to read\n' "$SVG" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Every fill in the source is replaced, so this keeps working if the mark ever
# gains or loses a path.
recolour() {
    local colour="$1" out="$2"
    sed -E "s/fill=\"#[0-9a-fA-F]{3,8}\"/fill=\"$colour\"/g" "$SVG" > "$work/$colour.svg"
    rsvg-convert -w "$SIZE" -h "$SIZE" -o "$HERE/$out" "$work/$colour.svg"
    printf 'wrote %s\n' "$out"
}

recolour "#a97bff" "nan.png"
recolour "#ffffff" "nan-ghost-white.png"
recolour "#000000" "nan-ghost-black.png"

printf '\nAll three are drawn from nan.svg at %sx%s px.\n' "$SIZE" "$SIZE"
