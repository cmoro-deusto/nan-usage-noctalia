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

# The gauges drawn as rasters: the ring, and the two segmented bars. Noctalia has no
# circular control, and a row of separate cells is laid out cell by cell, so the
# gaps round differently from one cell to the next at most scale factors. A raster
# is scaled as one piece, so its spacing stays even at any scale. A raster cannot be
# recoloured at runtime, so each colour a gauge takes (the theme's ink, amber, red)
# is a set of its own, on a dark theme and on a light one, where the track differs.
#
#   gauges/ring-<theme>-<level>-<step>.png    step: 0, 10, 20 … 100 (percent)
#   gauges/seg10-<theme>-<level>-<lit>.png    lit:  0 … 10 cells
#   gauges/seg5-<theme>-<level>-<lit>.png     lit:  0 … 5 cells
#
#   theme: dark | light       level: ok | warn | crit
GAUGES="$HERE/gauges"
rm -rf "$GAUGES"
mkdir -p "$GAUGES"

ring() {
    local theme="$1" level="$2" colour="$3" track="$4" step dash
    # 10% steps, not finer: the community repository caps a plugin at 200 files, and
    # every step is six rasters.
    for step in $(seq 0 10 100); do
        # The circumference of r = 11, and the share of it this step fills.
        dash=$(awk -v s="$step" 'BEGIN { printf "%.3f", 2 * 3.14159265 * 11 * s / 100 }')
        {
            printf '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 28 28">'
            printf '<circle cx="14" cy="14" r="11" fill="none" stroke="%s" stroke-width="4"/>' "$track"
            if [ "$step" -gt 0 ]; then
                printf '<circle cx="14" cy="14" r="11" fill="none" stroke="%s" stroke-width="4" stroke-linecap="round" stroke-dasharray="%s 100" transform="rotate(-90 14 14)"/>' "$colour" "$dash"
            fi
            printf '</svg>'
        } > "$work/gauge.svg"
        rsvg-convert -w 56 -h 56 -o "$GAUGES/ring-$theme-$level-$step.png" "$work/gauge.svg"
    done
}

# A bar of `count` cells in a 34 x 8 box, the size of the plain bar gauge, drawn at
# four times that so a scaled-down raster stays sharp.
segments() {
    local count="$1" gap="$2" theme="$3" level="$4" colour="$5" track="$6" lit cell
    cell=$(awk -v n="$count" -v g="$gap" 'BEGIN { printf "%.4f", (34 - (n - 1) * g) / n }')
    for lit in $(seq 0 "$count"); do
        {
            printf '<svg xmlns="http://www.w3.org/2000/svg" width="34" height="8" viewBox="0 0 34 8">'
            for index in $(seq 0 $((count - 1))); do
                local fill="$track"
                [ "$index" -lt "$lit" ] && fill="$colour"
                awk -v i="$index" -v c="$cell" -v g="$gap" -v f="$fill" \
                    'BEGIN { printf "<rect x=\"%.4f\" y=\"0\" width=\"%.4f\" height=\"8\" rx=\"1\" fill=\"%s\"/>", i * (c + g), c, f }'
            done
            printf '</svg>'
        } > "$work/gauge.svg"
        rsvg-convert -w 136 -h 32 -o "$GAUGES/seg$count-$theme-$level-$lit.png" "$work/gauge.svg"
    done
}

for level in ok warn crit; do
    case "$level" in
        ok) dark="#ffffff"; light="#000000" ;;
        warn) dark="#ff7800"; light="#ff7800" ;;
        crit) dark="#e01b24"; light="#e01b24" ;;
    esac
    for pair in "dark $dark #ffffff2e" "light $light #0000002e"; do
        set -- $pair
        ring "$1" "$level" "$2" "$3"
        segments 10 1 "$1" "$level" "$2" "$3"
        segments 5 2 "$1" "$level" "$2" "$3"
    done
done

printf 'wrote %s gauge rasters into gauges/\n' "$(ls "$GAUGES" | wc -l)"
