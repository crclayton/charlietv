#!/usr/bin/env bash

FIFO=/tmp/charlietv3-cmd
IPC=/tmp/charlietv3-ipc

total=25

w_movies=30
w_tv=55
w_new=15

ANCHOR_HOUR="${ANCHOR_HOUR:-10}"
ANCHOR_MIN="${ANCHOR_MIN:-0}"

if [ $# -eq 0 ]; then
  TVROOT="./TV"; MOVIEROOT="./Movies"; NEWROOT="./New"
else
  TVROOT="$1"; MOVIEROOT="$1"; NEWROOT="$1"
fi

re='.*\.(mp4|mkv|avi|mov|wmv|flv|webm|mpg|mpeg|m4v|3gp|ts|vob|ogv)$'

read -r n_movies n_tv n_new < <(
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

days_since_epoch=$(( $(date +%s) / 86400 ))

_spinner() {
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0
  while true; do
    printf "\r  %s  Booting up CharlieTV!!!!! Checking what's on..." "${frames[$((i % 10))]}"
    sleep 0.1; (( i++ )) || true
  done
}
_spinner & SPINNER_PID=$!

mapfile -d '' LINEUP < <(
  {
    (( n_movies > 0 )) && \
      find "$MOVIEROOT" -type f -regextype posix-extended -iregex "$re" -print0 \
      | shuf -z -n "$n_movies" 2>/dev/null || true

    (( n_tv > 0 )) && {
      mapfile -d '' shows < <(
        find "$TVROOT" -type f -regextype posix-extended -iregex "$re" -printf '%P\0' \
        | awk -v RS='\0' -v ORS='\0' -F/ '{print $1}' \
        | sort -zu | shuf -z -n "$n_tv"
      )
      for show in "${shows[@]}"; do
        mapfile -d '' episodes < <(
          find "$TVROOT/$show" -type f -regextype posix-extended -iregex "$re" -print0 | sort -z
        )
        num_episodes=${#episodes[@]}
        (( num_episodes > 0 )) && printf '%s\0' "${episodes[$(( days_since_epoch % num_episodes ))]}"
      done
    } || true

    (( n_new > 0 )) && \
      find "$NEWROOT" -type f -regextype posix-extended -iregex "$re" -print0 \
      | shuf -z -n "$n_new" 2>/dev/null || true
  } | shuf -z 2>/dev/null
)

kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null || true
printf "\r\033[K"

if [ "${#LINEUP[@]}" -eq 0 ]; then echo "No playable files found."; exit 1; fi
echo "CharlieTV initiated — ${#LINEUP[@]} channels"

# === Time offset helpers ===
duration_seconds() {
  timeout 4 ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null \
    | awk '{printf("%d\n",$1+0.5)}'
}
offset_since_even_hour() {
  local h m s anchor_h
  h=$(date +%H); m=$(date +%M); s=$(date +%S)
  anchor_h=$((10#$h / 2 * 2))
  echo $(( (10#$h - anchor_h)*3600 + 10#$m*60 + 10#$s ))
}
offset_since_hour()      { local m s; m=$(date +%M); s=$(date +%S); echo $((10#$m*60 + 10#$s)); }
offset_since_half_hour() { local m s; m=$(date +%M); s=$(date +%S); echo $(((10#$m % 30)*60 + 10#$s)); }

choose_start_offset() {
  local f="$1" dur="${2:-}" off
  [[ "$(realpath "$f")" == *"/New/"* ]] && { echo 15; return; }
  [[ -z "$dur" ]] && dur="$(duration_seconds "$f")"
  [[ -z "$dur" || "$dur" -le 0 ]] && { offset_since_even_hour; return; }
  if   (( dur < 1800 )); then off="$(offset_since_half_hour)"
  elif (( dur < 3600 )); then off="$(offset_since_hour)"
  else                        off="$(offset_since_even_hour)"
  fi
  echo $(( off % dur ))
}

# === IPC: send a JSON command to mpv ===
mpv_send() {
  python3 -c "
import socket, json, sys
sock = socket.socket(socket.AF_UNIX)
sock.settimeout(2)
try:
    sock.connect(sys.argv[1])
    cmd = []
    for a in sys.argv[2:]:
        try: cmd.append(int(a))
        except ValueError: cmd.append(a)
    sock.sendall(json.dumps({'command': cmd}).encode() + b'\n')
finally:
    sock.close()
" "$IPC" "$@" 2>/dev/null
}

# Load a new file into the running mpv instance.
# Seek position is written to a file before loadfile is sent, so Lua can
# read it in file-loaded with no IPC ordering dependency.
play_channel() {
  local f="$1" channel="$2"
  local dur start s h m r rh rm duration_str remaining_str osd

  echo "-> [$channel] $(basename "$f")"
  dur="$(duration_seconds "$f")"
  start="$(choose_start_offset "$f" "$dur")"

  s=$start; h=$((s/3600)); m=$(((s%3600)/60))
  (( h )) && duration_str="${h}h${m}min" || duration_str="${m}min"
  if [[ -n "$dur" && "$dur" -gt "$start" ]]; then
    r=$(( dur - start )); rh=$((r/3600)); rm=$(((r%3600)/60))
    (( rh )) && remaining_str="${rh}h${rm}min" || remaining_str="${rm}min"
  else
    remaining_str="unknown"
  fi
  began_epoch=$(( $(date +%s) - start ))
  began_min=$(date -d "@$began_epoch" +"%M")
  if [[ "$began_min" == "00" ]]; then
    began_time=$(date -d "@$began_epoch" +"%-I%p")
  else
    began_time=$(date -d "@$began_epoch" +"%-I:%M%p")
  fi
  osd="Began ${duration_str} ago (${began_time}), ${remaining_str} remaining"

  echo "$start" > /tmp/charlietv3-seek
  mpv_send set_property osd-playing-msg "$osd"
  mpv_send set_property brightness -100
  mpv_send script-message charlietv-channel "$channel"
  mpv_send loadfile "$f" replace
}

# === Setup ===
rm -f "$FIFO" "$IPC"
mkfifo "$FIFO"
exec 3<>"$FIFO"   # keep fifo open for both ends so reads never get EOF

PLAYER_PID=""
cleanup() {
  mpv_send quit
  [[ -n "$PLAYER_PID" ]] && { pkill -TERM -P "$PLAYER_PID" 2>/dev/null; kill "$PLAYER_PID" 2>/dev/null; wait "$PLAYER_PID" 2>/dev/null || true; }
  rm -f "$FIFO"
  stty sane 2>/dev/null || true
}
trap cleanup EXIT INT TERM

idx=0
first_start="$(choose_start_offset "${LINEUP[$idx]}")"
bash master3.sh "${LINEUP[$idx]}" "$first_start" &
PLAYER_PID=$!

# Wait for IPC socket to appear (up to 3s)
for i in $(seq 1 30); do
  [[ -S "$IPC" ]] && break
  sleep 0.1
done
if [[ ! -S "$IPC" ]]; then echo "mpv failed to start"; exit 1; fi

mpv_send script-message charlietv-channel "$((idx+1))/${#LINEUP[@]}"

# === Main loop ===
while true; do
  if IFS= read -r -t 2 cmd <&3; then
    case "$cmd" in
      next)
        idx=$(( (idx + 1) % ${#LINEUP[@]} ))
        play_channel "${LINEUP[$idx]}" "$((idx+1))/${#LINEUP[@]}"
        ;;
      prev)
        idx=$(( (idx - 1 + ${#LINEUP[@]}) % ${#LINEUP[@]} ))
        play_channel "${LINEUP[$idx]}" "$((idx+1))/${#LINEUP[@]}"
        ;;
      quit)
        exit 0
        ;;
      delete)
        f="${LINEUP[$idx]}"
        rm -f -- "$f" && echo "Deleted: $(basename "$f")" || echo "Delete failed: $f" >&2
        LINEUP=("${LINEUP[@]:0:$idx}" "${LINEUP[@]:$((idx+1))}")
        [[ "${#LINEUP[@]}" -eq 0 ]] && exit 0
        idx=$(( idx % ${#LINEUP[@]} ))
        play_channel "${LINEUP[$idx]}" "$((idx+1))/${#LINEUP[@]}"
        ;;
      save)
        f="${LINEUP[$idx]}"
        [[ "$(realpath "$f")" == *"/New/"* ]] && { echo "Saving $(basename "$f")"; mv -- "$f" "$MOVIEROOT/"; }
        LINEUP=("${LINEUP[@]:0:$idx}" "${LINEUP[@]:$((idx+1))}")
        [[ "${#LINEUP[@]}" -eq 0 ]] && exit 0
        idx=$(( idx % ${#LINEUP[@]} ))
        play_channel "${LINEUP[$idx]}" "$((idx+1))/${#LINEUP[@]}"
        ;;
    esac
  else
    # Timeout — check mpv is still alive
    kill -0 "$PLAYER_PID" 2>/dev/null || exit 0
  fi
done
