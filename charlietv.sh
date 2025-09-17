#!/usr/bin/env bash

#TODO
# nextfile/previous file use the same starting position, these should start at the beginning
# screen shouldn't log out due to inactivity
# set sleep timer by hour

#
#detox . -r -v

#pulseaudio &

total=20
w_movies=50 w_tv=49 w_sports=1


#mpv --idle=yes --force-window=yes --keep-open=yes \
#    --player-operation-mode=pseudo-gui \
#    --input-ipc-server=/tmp/mpvsocket \
#    --no-terminal >/dev/null 2>&1 &

if [ $# -eq 0 ]
  then
    echo "No argument"
    TVROOT="/media/crclayton/TOSHIBA EXT/TV"
    MOVIEROOT="/media/crclayton/TOSHIBA EXT/Movies"
    SPORTROOT="/media/crclayton/TOSHIBA EXT/Sports"
  else
    TVROOT=$1
    MOVIEROOT=$1
    SPORTROOT=$1

fi

# compute integer quotas from weights (fair rounding)
read n_movies n_tv n_sports < <(
  awk -v total="$total" -v m="$w_movies" -v t="$w_tv" -v s="$w_sports" '
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

{
  # Movies (skip if quota is 0)
  (( n_movies > 0 )) && \
  find "$MOVIEROOT" -type f \
    -regextype posix-extended -iregex "$re" -print0 \
    | shuf -z -n "$n_movies" 2>/dev/null || true


# TV — normalize by show: pick n_tv shows uniformly, then one ep per show
(( n_tv > 0 )) && {

  # Pick shows uniformly from those that actually have video files
  mapfile -d '' shows < <(
    find "$TVROOT" -type f \
      -regextype posix-extended -iregex "$re" -printf '%P\0' \
    | awk -v RS='\0' -v ORS='\0' -F/ '{print $1}' \
    | sort -zu \
    | shuf -z -n "$n_tv"
  )

  # For each chosen show, emit one random episode (NUL-separated)
  for show in "${shows[@]}"; do
    find "$TVROOT/$show" -type f \
      -regextype posix-extended -iregex "$re" -print0 \
    | shuf -z -n 1
  done
} || true

  # Sports
  (( n_sports > 0 )) && \
  find $SPORTROOT -type f \
    -regextype posix-extended -iregex "$re" -print0 \
    | shuf -z -n "$n_sports" 2>/dev/null || true
} | shuf -z 2>/dev/null | xargs -0 -r -n1 bash master.sh

