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

echo "$movie"

# === Get full MPV stream listing from stdout ===
output=$(./mpv.AppImage --frames=0 --vo=null --ao=null --no-config "$movie" 2>&1)

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

# echo "Using: aid=$aid, sid=$sid (ita), secondary-sid=$secondary_sid (eng)"


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

#datestr="$(date '+%-d %b (%a) %I:%M%p')"
datestr="$(date '+%I:%M%p')"


starttime="${2:-}"
full_movie="$(realpath "$movie")"
movie_only="$(basename "$full_movie")"


# If it's in /New/, always start at 0
if [[ "$full_movie" == *"/New/"* ]]; then
  starttime=15
fi

# If $2 not provided (and not forced to 0 above), pick a random start time
if [[ -z "${starttime}" ]]; then
  dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$movie" | cut -d. -f1)"
  if [[ -z "$dur" || "$dur" -le 0 ]]; then
    starttime=0
  else
    starttime=$(( RANDOM % dur ))
  fi
fi

s=$starttime; h=$((s/3600)); m=$(((s%3600)/60)); ((h)) && duration="${h}h${m}min" || duration="${m}min"

    #--osd-playing-msg="$datestr [$duration] $movie_only" \





# === Launch MPV
./mpv.AppImage "$movie" \
    --really-quiet \
    --no-terminal \
    --msg-level=all=no \
    --display-tags-clr \
    --vo=gpu-next \
    --video-sync=display-resample \
    --input-conf="input.conf" \
    --config-dir="." \
    --profile=norm \
    --start=$starttime \
    --osd-playing-msg="$movie_only [Began $duration ago]\nPress (q) to quit, ← and → to change channels, (i) for more instructions" \
    --osd-playing-msg-duration=5000 \
    --osd-font="Nimbus Sans" \
    --osd-font-size=24 \
    --osd-color='#eb9605' \
    --osd-border-size=1 \
    --osd-shadow-offset=3 \
    --osd-shadow-color='#000000' \
    --aid="$aid" \
    --sid="$sid" \
    --secondary-sid="$secondary_sid" \
    --sub-delay=0 \
    --speed=1 \
    --sub-scale=1 \
    --sub-align-x=center \
    --sub-pos=99 \
    --sub-margin-y=0 \
    --sub-border-color='#000000' \
    --sub-color='#eb9605' \
    --sub-font="Nimbus Sans" \
    --sub-border-size=1 \
    --sub-shadow-offset=3 \
    --sub-shadow-color='#000000' \
    --sub-ass-override=force \
    --embeddedfonts=no \
    --scripts=nextfile_and_rewind.lua \
    --scripts=nextfile.lua \
    --script=auto-nextfile.lua \
    --fullscreen #\

    #--secondary-sub-delay=0 \
    #--auto-window-resize=no \
    #--save-position-on-quit
    #--window-maximized=yes \
    #--script=navigator.lua \
    #--script=delete_file.lua \
    #--scripts=previousfile.lua
    #--script=nextfile_and_rewind.lua \
    #--gpu-api=vulkan \
    ###--keep-open=yes
    #--scripts=nextfile_and_rewind.lua \
    #--scripts=auto-nextfile.lua \
#    --glsl-shader=$shader \
#    --force-window=yes \

#    --idle="yes" \
#
#
## progress-bar-always.lua:nextfile.lua:navigator.lua \
