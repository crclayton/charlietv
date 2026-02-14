check_videos_integrity() {
  local root="${1:-.}"
  local mode="${2:-full}"   # "fast" or "full"
  local log="${3:-video_integrity_$(date +%Y%m%d_%H%M%S).log}"

  command -v ffprobe >/dev/null 2>&1 || { echo "ffprobe not found (install ffmpeg)"; return 2; }
  if [[ "$mode" == "full" ]]; then
    command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg not found (install ffmpeg)"; return 2; }
  fi

  # Adjust extensions as needed
  local re='.*\.(mp4|mkv|avi|mov|wmv|flv|webm|mpg|mpeg|m4v|3gp|ts|vob|ogv)$'

  : > "$log"
  echo "Checking: $root (mode=$mode)" | tee -a "$log"

  local -i total=0 bad=0
  while IFS= read -r -d '' f; do
    total+=1
    printf '[%d] %s' "$total" "$f" | tee -a "$log"

    # 1) Fast container/stream check
    if ! ffprobe -v error -hide_banner \
      -show_entries format=duration:stream=codec_type,codec_name \
      -of default=noprint_wrappers=1:nokey=1 \
      "$f" >/dev/null 2>>"$log"; then
      echo "  BAD (ffprobe)" | tee -a "$log"
      #rm $f
      bad+=1
      continue
    fi

    # 2) Full decode check (catches partial/truncated frames)
    if [[ "$mode" == "full" ]]; then
      if ! ffmpeg -v error -hide_banner -nostdin -i "$f" -map 0 -f null - \
        >/dev/null 2>>"$log"; then
        echo "  BAD (decode)" | tee -a "$log"
        bad+=1
        continue
      fi
    fi

    echo "  OK" | tee -a "$log"
  done < <(find "$root" -type f -regextype posix-extended -iregex "$re" -print0)

  echo "Done. Total: $total  Bad: $bad  Log: $log" | tee -a "$log"
  (( bad == 0 ))
}

#check_videos_integrity "TV/" fast | tee check_tv.log
check_videos_integrity "New/" fast | tee check_new.log
