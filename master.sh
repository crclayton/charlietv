#!/bin/bash

input="$1"

movie="$input"
# === Batch mode: shuffle directory ===
if [[ -z "$input" || -d "$input" ]]; then
    echo "No movie file specified or input is a directory."
    echo "Searching in: ${input:-.}"
    movie=$(find "${input:-.}" -type f | shuf -n 1)
    echo $movie
fi

echo "Movie: $movie"

# === Get full MPV stream listing from stdout ===
output=$(mpv --frames=0 --vo=null --ao=null --no-config "$movie" 2>&1)

# === Extract Italian audio
aid=$(echo "$output" | grep -E -- '--aid=[0-9]+' | grep -- '--alang=en' | sed -n 's/.*--aid=\([0-9]\+\).*/\1/p' | head -n1)

# === Extract Italian subtitle, skipping anything with 'forced' (case-insensitive)
sid=$(echo "$output" | grep -i -- '--sid=[0-9].*--slang=it' | grep -vi 'forced' | sed -n 's/.*--sid=\([0-9]\+\).*/\1/p' | head -n1)

# === Extract English subtitle, skipping anything with 'forced' (case-insensitive)
secondary_sid=$(echo "$output" | grep -i -- '--sid=[0-9].*--slang=en' | grep -vi 'forced' | sed -n 's/.*--sid=\([0-9]\+\).*/\1/p' | head -n1)

# Fallbacks
aid="${aid:-1}"
sid="${sid:-1}"
secondary_sid="${secondary_sid:-0}"

echo "Using: aid=$aid, sid=$sid (ita), secondary-sid=$secondary_sid (eng)"

starttime=$((RANDOM % $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$movie" | cut -d. -f1)))

shaders=(
  "Default"
  "NoChroma.hook"
  "crt-aperture.glsl"
  "crt-gdv-mini-ultra-trinitron.glsl"
  "crt-guest-advanced-ntsc.glsl"
  "crt-guest-advanced-ntsc-textures.glsl"
  "crt-hyllian.glsl"
  "crt-lottes.glsl"
 # "crt-royale-fb-intel.glsl"
 # "crt-royale-kurozumi.glsl"
 # "crt-royale-kurozumi-intel.glsl"
#  "crt-royale-ntsc-composite-intel.glsl"
)

# Pick one shader at random
shader=${shaders[RANDOM % ${#shaders[@]}]}


# === Launch MPV
mpv "$movie" \
    --input-conf="input.conf" \
    --config-dir="." \
    --profile=norm \
    --vo=gpu-next \
    --start=$starttime \
    --osd-playing-msg="$movie" \
    --osd-playing-msg-duration="5000" \
    --aid="$aid" \
    --sid="$sid" \
    --secondary-sid="$secondary_sid" \
    --sub-delay=0 \
    --secondary-sub-delay=0 \
    --speed=1 \
    --sub-scale=1.3 \
    --sub-align-x=center \
    --sub-pos=99 \
    --sub-margin-y=0 \
    --sub-border-color='#000000' \
    --sub-color='#eb9605' \
    --sub-font="Nimbus Sans" \
    --sub-ass-override=force \
    --embeddedfonts=no \
    --scripts=nextfile_and_rewind.lua \
    --scripts=nextfile.lua \
    --sub-border-size=1 \
    --sub-shadow-offset=3 \
    --sub-shadow-color='#000000' \
    --window-maximized=yes \
    --fullscreen \
    --glsl-shader=$shader #\
#    --idle="yes" \
#    --force-window=yes \
#    --keep-open=yes \

