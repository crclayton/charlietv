#!/usr/bin/env bash
#set -euo pipefail

# charlietv_v2.sh
# Keys while running:
#   n = next channel
#   p = previous channel
#   q = quit

total=25

w_movies=45
w_tv=45
w_new=10


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

# Build lineup (NUL-delimited) then shuffle and load into a bash array
mapfile -d '' LINEUP < <(
  {
    # Movies
    (( n_movies > 0 )) && \
      find "$MOVIEROOT" -type f -regextype posix-extended -iregex "$re" -print0 \
      | shuf -z -n "$n_movies" 2>/dev/null || true

    # TV — normalize by show: pick n_tv shows uniformly, then one ep per show
    (( n_tv > 0 )) && {
      mapfile -d '' shows < <(
        find "$TVROOT" -type f -regextype posix-extended -iregex "$re" -printf '%P\0' \
        | awk -v RS='\0' -v ORS='\0' -F/ '{print $1}' \
        | sort -zu \
        | shuf -z -n "$n_tv"
      )

      for show in "${shows[@]}"; do
        find "$TVROOT/$show" -type f -regextype posix-extended -iregex "$re" -print0 \
          | shuf -z -n 1
      done
    } || true

    # Sports
    (( n_sports > 0 )) && \
      find "$NEWROOT" -type f -regextype posix-extended -iregex "$re" -print0 \
      | shuf -z -n "$n_sports" 2>/dev/null || true
  } | shuf -z 2>/dev/null
)

echo "playable"
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

  # If we can't get duration, fall back to the default 2-hour rolling offset.
  if [[ -z "$dur" ]] || (( dur <= 0 )); then
    offset_since_even_hour
    return
  fi

  if (( dur < 1800 )); then
    off="$(offset_since_half_hour)"
  elif (( dur < 3600 )); then
    off="$(offset_since_hour)"
  else
    off="$(offset_since_even_hour)"
  fi

  if (( off >= dur )); then
    echo 0
  else
    echo "$off"
  fi
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

   full_movie=$(realpath "$movie")

        if [[ "$full_movie" == *"/New/"* ]]; then
            $start=0
        fi


  echo
  echo "Channel $((idx+1))/${#LINEUP[@]}"
  echo "File: $f"
  echo "Start offset: ${start}s"
  echo "(<=next, >=prev, q=quit)"

  # Provide start offset both ways:
  #  - as env var (easy for master.sh to use)
  #  - as $2 argument (in case master.sh already supports it)
  CHARLIETV_START_SECONDS="$start" bash master.sh "$f" "$start" &
  PLAYER_PID=$!
}

start_current "${LINEUP[$idx]}"

while true; do

    echo "true"
  # If player exits naturally, advance to next
  if [[ -n "${PLAYER_PID}" ]] && ! kill -0 "${PLAYER_PID}" 2>/dev/null; then
    wait "${PLAYER_PID}" 2>/dev/null || true
    idx=$(( (idx + 1) % ${#LINEUP[@]} ))
    start_current "${LINEUP[$idx]}"
  fi

  # Non-blocking key read
  key="$(dd bs=1 count=1 2>/dev/null || true)"

  case "$key" in
    # . and , map to the same as v and w in dvorak
    .)
      kill -TERM "${PLAYER_PID}" 2>/dev/null || true
      wait "${PLAYER_PID}" 2>/dev/null || true
      idx=$(( (idx + 1) % ${#LINEUP[@]} ))
      start_current "${LINEUP[$idx]}"
      ;;
    ,)
      kill -TERM "${PLAYER_PID}" 2>/dev/null || true
      wait "${PLAYER_PID}" 2>/dev/null || true
      idx=$(( (idx - 1 + ${#LINEUP[@]}) % ${#LINEUP[@]} ))
      start_current "${LINEUP[$idx]}"
      ;;
    # . and , map to the same as v and w in dvorak
    v)
      kill -TERM "${PLAYER_PID}" 2>/dev/null || true
      wait "${PLAYER_PID}" 2>/dev/null || true
      idx=$(( (idx + 1) % ${#LINEUP[@]} ))
      start_current "${LINEUP[$idx]}"
      ;;
    w)
      kill -TERM "${PLAYER_PID}" 2>/dev/null || true
      wait "${PLAYER_PID}" 2>/dev/null || true
      idx=$(( (idx - 1 + ${#LINEUP[@]}) % ${#LINEUP[@]} ))
      start_current "${LINEUP[$idx]}"
      ;;
    q)
      exit 0
      ;;
    \')
      exit 0
      ;;
    *)
      # no key pressed / unhandled key
      ;;
  esac

  # tiny sleep to avoid busy looping
  sleep 0.05
done

