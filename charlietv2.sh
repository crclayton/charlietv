#!/usr/bin/env bash
#set -euo pipefail

# charlietv_v2.sh
# Keys while running:
#   right arrow = next channel
#   left arrow  = previous channel
#   q           = quit

# apr 28, louie season 2 episode 2

total=25

w_movies=33 #33
w_tv=34
w_new=33 #33


# Anchor for "broadcast day" sync (10:00 AM local by default)
ANCHOR_HOUR="${ANCHOR_HOUR:-10}"
ANCHOR_MIN="${ANCHOR_MIN:-0}"

if [ $# -eq 0 ]; then
  TVROOT="./TV"
  MOVIEROOT="./Movies"
  NEWROOT="./New"
else
  TVROOT="$1"
  MOVIEROOT="$1"
  NEWROOT="$1"
fi

re='.*\.(mp4|mkv|avi|mov|wmv|flv|webm|mpg|mpeg|m4v|3gp|ts|vob|ogv)$'

read n_movies n_tv n_sports < <(
  awk -v total="$total" -v m="$w_movies" -v t="$w_tv" -v s="$w_new" '
    BEGIN{
      sum=m+t+s
      t1=total*m/sum; n1=int(t1); f1=t1-n1
      t2=total*t/sum; n2=int(t2); f2=t2-n2
      t3=total*s/sum; n3=int(t3); f3=t3-n3
      rem=total-(n1+n2+n3)
      while(rem-->0){
        if(f1>=f2 && f1>=f3){ n1++; f1=-1 }
        else if(f2>=f1 && f2>=f3){ n2++; f2=-1 }
        else { n3++; f3=-1 }
      }
      printf "%d %d %d", n1, n2, n3
    }')

re='.*\.(mp4|mkv|avi|mov|wmv|flv|webm|mpg|mpeg|m4v|3gp|ts|vob|ogv)$'

# Compute integer quotas from weights (same approach as your v1)
read -r n_movies n_tv n_sports < <(
  awk -v total="$total" -v m="$w_movies" -v t="$w_tv" -v s="$w_new" '
    BEGIN{
      sum=m+t+s
      t1=total*m/sum; n1=int(t1); f1=t1-n1
      t2=total*t/sum; n2=int(t2); f2=t2-n2
      t3=total*s/sum; n3=int(t3); f3=t3-n3
      rem=total-(n1+n2+n3)
      while(rem-->0){
        if(f1>=f2 && f1>=f3){ n1++; f1=-1 }
        else if(f2>=f1 && f2>=f3){ n2++; f2=-1 }
        else { n3++; f3=-1 }
      }
      printf "%d %d %d", n1, n2, n3
    }'
)

# Compute day index once — used for both episode selection and seeding all shuffles
days_since_epoch=$(( $(date +%s) / 86400 ))
# Generates a deterministic stream of pseudo-random bytes seeded by the day,
# so the entire lineup is stable for the whole calendar day.
_day_seed() { awk -v seed="$days_since_epoch" 'BEGIN{srand(seed); for(i=0;i<4096;i++) printf "%c", int(rand()*256)}'; }

# Build lineup (NUL-delimited) then shuffle and load into a bash array
mapfile -d '' LINEUP < <(
  {
    # Movies
    (( n_movies > 0 )) && \
      find "$MOVIEROOT" -type f -regextype posix-extended -iregex "$re" -print0 \
      | shuf -z -n "$n_movies"  2>/dev/null || true

# TV — normalize by show: pick n_tv shows uniformly, then one deterministic ep per show
    (( n_tv > 0 )) && {

      mapfile -d '' shows < <(
        find "$TVROOT" -type f -regextype posix-extended -iregex "$re" -printf '%P\0' \
        | awk -v RS='\0' -v ORS='\0' -F/ '{print $1}' \
        | sort -zu \
        | shuf -z -n "$n_tv" #--random-source=<(_day_seed)
      )

      for show in "${shows[@]}"; do
        # 2. Get all episodes for THIS show into an array, sorted alphabetically
        mapfile -d '' episodes < <(find "$TVROOT/$show" -type f -regextype posix-extended -iregex "$re" -print0 | sort -z)

        num_episodes=${#episodes[@]}

        if (( num_episodes > 0 )); then
          index=$(( days_since_epoch % num_episodes ))
          printf '%s\0' "${episodes[$index]}"
        fi
      done
    } || true


    # Sports
    (( n_sports > 0 )) && \
      find "$NEWROOT" -type f -regextype posix-extended -iregex "$re" -print0 \
      | shuf -z -n "$n_sports" 2>/dev/null || true
  } | shuf -z 2>/dev/null
)

if [ "${#LINEUP[@]}" -eq 0 ]; then
  echo "No playable files found."
  exit 1
fi

# --- time sync helpers ---

now_epoch() { date +%s; }

# seconds since last (or current) anchor time (10:00 by default)
anchor_offset_seconds() {
  local now anchor today_anchor

  now="$(now_epoch)"

  # today at ANCHOR_HOUR:ANCHOR_MIN:00
  today_anchor="$(date -d "today ${ANCHOR_HOUR}:${ANCHOR_MIN}:00" +%s)"

  if (( now >= today_anchor )); then
    anchor="$today_anchor"
  else
    anchor="$(date -d "yesterday ${ANCHOR_HOUR}:${ANCHOR_MIN}:00" +%s)"
  fi

  echo $(( now - anchor ))
}

# seconds since top of the current hour (minute+second)
minutes_past_hour_seconds() {
  local mm ss
  mm="$(date +%M)"
  ss="$(date +%S)"
  echo $((10#$mm * 60 + 10#$ss))
}


# --- duration in seconds (best-effort). Requires ffprobe (ffmpeg).
duration_seconds() {
  local f="$1"
  if command -v ffprobe >/dev/null 2>&1; then
    ffprobe -v error -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null \
      | awk '{printf("%d\n",$1+0.5)}'
  else
    echo ""
  fi
}

# --- rolling offsets ---
offset_since_even_hour() {
  local h m s anchor_h
  h=$(date +%H); m=$(date +%M); s=$(date +%S)
  anchor_h=$((10#$h / 2 * 2))  # previous even hour
  echo $(( (10#$h - anchor_h)*3600 + 10#$m*60 + 10#$s ))
}

offset_since_hour() {
  local m s
  m=$(date +%M); s=$(date +%S)
  echo $((10#$m*60 + 10#$s))
}

offset_since_half_hour() {
  local m s
  m=$(date +%M); s=$(date +%S)
  # minutes since last :00 or :30
  echo $(((10#$m % 30)*60 + 10#$s))
}

# --- your rules ---
# default: 2-hr rolling window (even hours)
# if dur < 1h: use minutes past the hour
# if dur < 30m: use minutes past the half-hour
# catch-all: if chosen offset >= duration, start at 0
choose_start_offset() {
  local f="$1"
  local dur off

  dur="$(duration_seconds "$f")"

  # If we can't determine duration, fall back to 2-hour rolling offset
  if [[ -z "$dur" ]] || (( dur <= 0 )); then
    offset_since_even_hour
    return
  fi

  # Select clock-based offset window
  if (( dur < 1800 )); then
    off="$(offset_since_half_hour)"
  elif (( dur < 3600 )); then
    off="$(offset_since_hour)"
  else
    off="$(offset_since_even_hour)"
  fi

  # Wrap instead of clamp
  echo $(( off % dur ))
}


### # Choose start offset:
### # - Prefer seconds since anchor (10:00)
### # - If duration is known and offset exceeds duration, use minutes-past-hour instead
### choose_start_offset() {
###   local f="$1"
###   local off dur mph
###
###   off="$(anchor_offset_seconds)"
###   dur="$(duration_seconds "$f")"
###
###   if [[ -n "$dur" ]] && (( dur > 0 )) && (( off >= dur )); then
###     mph="$(minutes_past_hour_seconds)"
###     echo "$mph"
###   else
###     echo "$off"
###   fi
### }

# --- interactive channel loop ---

PLAYER_PID=""

cleanup() {
  if [[ -n "${PLAYER_PID}" ]] && kill -0 "${PLAYER_PID}" 2>/dev/null; then
    kill -TERM "${PLAYER_PID}" 2>/dev/null || true
    wait "${PLAYER_PID}" 2>/dev/null || true
  fi
  stty sane 2>/dev/null || true
}
trap cleanup EXIT INT TERM

stty -echo -icanon time 0 min 0

idx=0

start_current() {
  local f="$1"
  local start
  start="$(choose_start_offset "$f")"

  #echo
  #echo "Channel $((idx+1))/${#LINEUP[@]}"
  #echo "File: $f"
  #echo "Start offset: ${start}s"
  #echo "(q=quit)"

  CHARLIETV_START_SECONDS="$start" bash master.sh "$f" "$start" &
  PLAYER_PID=$!
}

start_current "${LINEUP[$idx]}"

while true; do
  # Allow quitting from terminal when mpv doesn't have focus
  IFS= read -r -s -t 0.1 -N 1 key 2>/dev/null || true
  if [[ "$key" == "q" ]] || [[ "$key" == $'\'' ]]; then
    exit 0
  fi

  # When player exits, check exit code for direction (set by input.conf bindings)
  # 3=prev, 4=next, 5=quit, anything else=natural end→next
  if [[ -n "${PLAYER_PID}" ]] && ! kill -0 "${PLAYER_PID}" 2>/dev/null; then
    wait "${PLAYER_PID}" 2>/dev/null; player_exit=$?

    case $player_exit in
      3) idx=$(( (idx - 1 + ${#LINEUP[@]}) % ${#LINEUP[@]} )) ;;
      5) exit 0 ;;
      *) idx=$(( (idx + 1) % ${#LINEUP[@]} )) ;;
    esac
    start_current "${LINEUP[$idx]}"
  fi
done

