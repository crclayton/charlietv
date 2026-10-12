#!/usr/bin/env bash

FIFO=/tmp/charlietv3-cmd
IPC=/tmp/charlietv3-ipc

total=25

ANCHOR_HOUR="${ANCHOR_HOUR:-10}"
ANCHOR_MIN="${ANCHOR_MIN:-0}"

CHARLIETV_LAYOUT="qwerty"
args=()
for arg in "$@"; do
  if [[ "$arg" == "--dvorak" ]]; then
    CHARLIETV_LAYOUT="dvorak"
  else
    args+=("$arg")
  fi
done
set -- "${args[@]}"
export CHARLIETV_LAYOUT

if [ $# -eq 0 ]; then
  TVROOT="./TV"; MOVIEROOT="./Movies"; NEWROOT="./New"
  w_tv=55
  w_movies=30
  w_new=15
else
  TVROOT="$1"; MOVIEROOT="$1"; NEWROOT="$1"
  w_tv=100
  w_movies=0
  w_new=0
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

# Lineup is saved here (off the drive) so a crash/rerun resumes the same channels.
# Deleted on a clean quit; ignored if it's from another day or other arguments.
STATE=/tmp/charlietv3-state
ROOT="$(pwd -P)"
STATE_KEY="$*"
idx=0
LINEUP=()

if [[ -r "$STATE" ]]; then
  mapfile -d '' saved < "$STATE"
  if [[ "${saved[0]}" == "$days_since_epoch" && "${saved[1]}" == "$STATE_KEY" && "${#saved[@]}" -gt 3 ]]; then
    idx="${saved[2]}"
    LINEUP=("${saved[@]:3}")
    echo "Resuming previous CharlieTV lineup (run with no state: rm $STATE)"
  fi
fi

save_state() {
  printf '%s\0' "$days_since_epoch" "$STATE_KEY" "$idx" "${LINEUP[@]}" > "$STATE" 2>/dev/null
}

if [ "${#LINEUP[@]}" -eq 0 ]; then

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

fi

if [ "${#LINEUP[@]}" -eq 0 ]; then echo "No playable files found."; exit 1; fi
(( idx < ${#LINEUP[@]} )) || idx=0
save_state
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
# Seconds since the most recent ANCHOR_HOUR:ANCHOR_MIN. Measuring from one
# fixed point (rather than the latest half/whole hour) means a channel's
# position keeps advancing with the clock instead of snapping back each block.
offset_since_anchor() {
  local now anchor
  now=$(date +%s)
  anchor=$(date -d "today $ANCHOR_HOUR:$ANCHOR_MIN" +%s)
  (( anchor > now )) && anchor=$(( anchor - 86400 ))
  echo $(( now - anchor ))
}

choose_start_offset() {
  local f="$1" dur="${2:-}"
  [[ -z "$dur" ]] && dur="$(duration_seconds "$f")"
  [[ -z "$dur" || "$dur" -le 0 ]] && { offset_since_even_hour; return; }
  echo $(( $(offset_since_anchor) % dur ))
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

# Query mpv properties; prints one JSON value per line (null if unavailable).
# Fails if mpv doesn't answer within 3s — i.e. it's hung.
mpv_get() {
  python3 -c "
import socket, json, sys
sock = socket.socket(socket.AF_UNIX)
sock.settimeout(3)
props = sys.argv[2:]
try:
    sock.connect(sys.argv[1])
    for i, p in enumerate(props):
        sock.sendall(json.dumps({'command': ['get_property', p], 'request_id': i + 1}).encode() + b'\n')
    got, buf = {}, b''
    while len(got) < len(props):
        chunk = sock.recv(4096)
        if not chunk: sys.exit(1)
        buf += chunk
        while b'\n' in buf:
            line, buf = buf.split(b'\n', 1)
            m = json.loads(line)
            if m.get('request_id'): got[m['request_id']] = m.get('data')
    for i in range(len(props)): print(json.dumps(got[i + 1]))
except Exception:
    sys.exit(1)
finally:
    sock.close()
" "$IPC" "$@" 2>/dev/null
}

# Load a new file into the running mpv instance.
# Seek position is written to a file before loadfile is sent, so Lua can
# read it in file-loaded with no IPC ordering dependency.
play_channel() {
  local f="$1" channel="$2" forced_start="${3:-}"
  local dur start s h m r rh rm duration_str remaining_str osd

  echo "-> [$channel] $(basename "$f")"
  dur="$(duration_seconds "$f")"
  if [[ -n "$forced_start" ]]; then
    start="$forced_start"
  else
    start="$(choose_start_offset "$f" "$dur")"
  fi

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

# === Drive recovery ===
# If the drive drops out, our working directory goes stale (I/O errors on every
# relative path) and mpv, which runs from the drive, can crash. These helpers
# re-find the drive when it comes back and restart mpv on the current channel.
NEED_RESTART=0

# Rewrite absolute paths if the drive came back under a different mount point.
remap_root() {
  local new="$1" i
  for i in "${!LINEUP[@]}"; do
    [[ "${LINEUP[$i]}" == "$ROOT/"* ]] && LINEUP[$i]="$new/${LINEUP[$i]#"$ROOT/"}"
  done
  for v in TVROOT MOVIEROOT NEWROOT; do
    [[ "${!v}" == "$ROOT/"* ]] && printf -v "$v" '%s' "$new/${!v#"$ROOT/"}"
  done
  ROOT="$new"
}

# Succeeds (and cd's there) if the drive is mounted and readable.
find_root() {
  local d src
  for d in "$ROOT" "${ROOT%/*}"/*; do
    [[ -f "$d/master3.sh" && -f "$d/charlietv3.sh" ]] || continue
    src="$(findmnt -n -o SOURCE --target "$d" 2>/dev/null)"
    [[ "$src" != /dev/* || -b "$src" ]] || continue
    cd "$d" 2>/dev/null && head -c1 master3.sh >/dev/null 2>&1 || continue
    [[ "$d" != "$ROOT" ]] && remap_root "$d"
    return 0
  done
  return 1
}

drive_ok() { find_root && head -c1 -- "${LINEUP[$idx]}" >/dev/null 2>&1; }

kill_tree() {
  local c
  for c in $(pgrep -P "$1"); do kill_tree "$c"; done
  kill -9 "$1" 2>/dev/null
}

# (Re)launch mpv on the current channel.
start_player() {
  local f="${LINEUP[$idx]}" start="${1:-}"
  [[ -n "$PLAYER_PID" ]] && { kill_tree "$PLAYER_PID"; PLAYER_PID=""; }
  rm -f "$IPC" /tmp/charlietv3-seek
  [[ -z "$start" ]] && start="$(choose_start_offset "$f")"
  echo "-> [$((idx+1))/${#LINEUP[@]}] $(basename "$f")"
  bash master3.sh "$f" "$start" &
  PLAYER_PID=$!
  for i in $(seq 1 100); do
    [[ -S "$IPC" ]] && break
    sleep 0.1
  done
  if [[ ! -S "$IPC" ]]; then NEED_RESTART=1; return 1; fi
  NEED_RESTART=0
  HUNG=0; STALLED=0; LAST_POS=""
  mpv_send script-message charlietv-channel "$((idx+1))/${#LINEUP[@]}"
}

# Switch to LINEUP[idx]; recovers the drive/player first if needed.
tune() {
  save_state
  if ! drive_ok; then
    echo "!! Drive unavailable — waiting for it to reconnect"
    NEED_RESTART=1
    mpv_send show-text "NO SIGNAL — reconnect the drive" 4000
    return
  fi
  if (( NEED_RESTART )); then
    echo "Drive is back — restarting player"
    start_player "$@"
  else
    play_channel "${LINEUP[$idx]}" "$((idx+1))/${#LINEUP[@]}" "$@"
  fi
}

# === Setup ===
rm -f "$FIFO" "$IPC"
mkfifo "$FIFO"
exec 3<>"$FIFO"   # keep fifo open for both ends so reads never get EOF

PLAYER_PID=""
HUNG=0; STALLED=0; LAST_POS=""

# Watchdog: mpv sometimes freezes switching files at the end of an episode
# (picture stuck, "mpv stopped responding"). Succeeds if it looks frozen —
# not answering IPC, or playing (not paused/buffering) with time-pos stuck.
player_frozen() {
  local out pos idle
  if ! out="$(mpv_get time-pos core-idle)"; then
    (( ++HUNG >= 3 )); return
  fi
  HUNG=0
  { read -r pos; read -r idle; } <<< "$out"
  if [[ "$idle" == false && "$pos" != null && "$pos" == "$LAST_POS" ]]; then
    (( ++STALLED >= 5 )) && return 0
  else
    STALLED=0
  fi
  LAST_POS="$pos"
  return 1
}

cleanup() {
  mpv_send quit
  [[ -n "$PLAYER_PID" ]] && { pkill -TERM -P "$PLAYER_PID" 2>/dev/null; kill "$PLAYER_PID" 2>/dev/null; wait "$PLAYER_PID" 2>/dev/null || true; }
  rm -f "$FIFO"
  stty sane 2>/dev/null || true
}
trap cleanup EXIT INT TERM

start_player || { echo "mpv failed to start"; exit 1; }

# === Main loop ===
while true; do
  if IFS= read -r -t 2 cmd <&3; then
    case "$cmd" in
      next|prev)
        # While recovering from a dropped drive, stay on the same channel —
        # the keypress (or mpv's EOF on the failed read) just triggers the retry.
        if (( ! NEED_RESTART )) && drive_ok; then
          [[ "$cmd" == next ]] && step=1 || step=-1
          idx=$(( (idx + step + ${#LINEUP[@]}) % ${#LINEUP[@]} ))
        fi
        tune
        ;;
      quit)
        rm -f "$STATE"
        exit 0
        ;;
      delete)
        f="${LINEUP[$idx]}"
        rm -f -- "$f" && echo "Deleted: $(basename "$f")" || echo "Delete failed: $f" >&2
        LINEUP=("${LINEUP[@]:0:$idx}" "${LINEUP[@]:$((idx+1))}")
        [[ "${#LINEUP[@]}" -eq 0 ]] && { rm -f "$STATE"; exit 0; }
        idx=$(( idx % ${#LINEUP[@]} ))
        tune
        ;;
      save)
        f="${LINEUP[$idx]}"
        [[ "$(realpath "$f" 2>/dev/null)" == *"/New/"* ]] || continue
        echo "Saving $(basename "$f")"; mv -- "$f" "$MOVIEROOT/"
        LINEUP=("${LINEUP[@]:0:$idx}" "${LINEUP[@]:$((idx+1))}")
        [[ "${#LINEUP[@]}" -eq 0 ]] && { rm -f "$STATE"; exit 0; }
        idx=$(( idx % ${#LINEUP[@]} ))
        tune
        ;;
      random)
        f="${LINEUP[$idx]}"
        dir="$(dirname -- "$f")"
        mapfile -d '' candidates < <(
          find "$dir" -maxdepth 1 -type f -regextype posix-extended -iregex "$re" -print0 2>/dev/null
        )
        if [[ "${#candidates[@]}" -gt 1 ]]; then
          others=()
          for c in "${candidates[@]}"; do
            [[ "$c" == "$f" ]] || others+=("$c")
          done
          candidates=("${others[@]}")
        fi
        if [[ "${#candidates[@]}" -gt 0 ]]; then
          LINEUP[$idx]="${candidates[$RANDOM % ${#candidates[@]}]}"
          tune 0
        fi
        ;;
    esac
  else
    # Timeout — check mpv is still alive and the drive is still there.
    if [[ -n "$PLAYER_PID" ]] && ! kill -0 "$PLAYER_PID" 2>/dev/null; then
      wait "$PLAYER_PID" 2>/dev/null; status=$?
      PLAYER_PID=""
      # Window closed normally with the drive fine → treat as quit.
      if (( status == 0 && ! NEED_RESTART )) && drive_ok; then rm -f "$STATE"; exit 0; fi
      echo "!! Player stopped (status $status) — will restart when the drive is readable"
      NEED_RESTART=1
    elif (( ! NEED_RESTART )) && ! find_root; then
      echo "!! Drive disconnected — waiting for it to reconnect"
      NEED_RESTART=1
    elif (( ! NEED_RESTART )) && [[ -n "$PLAYER_PID" ]] && player_frozen; then
      echo "!! mpv froze — restarting player"
      NEED_RESTART=1
    fi
    # Auto-recover as soon as the drive is back (a channel change also triggers this).
    if (( NEED_RESTART )) && drive_ok; then
      echo "Drive is back — restarting player"
      start_player
    fi
  fi
done
