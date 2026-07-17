#!/bin/bash

movie="$1"
starttime="${2:-0}"
IPC=/tmp/charlietv3-ipc

    #--no-input-default-bindings \
./mpv.AppImage "$movie" \
    --really-quiet \
    --no-terminal \
    --msg-level=all=no \
    --display-tags-clr \
    --vo=gpu-next \
    --video-sync=display-resample \
    --input-conf="input3.conf" \
    --config-dir="." \
    --profile=norm \
    --start="$starttime" \
    --input-ipc-server="$IPC" \
    --alang=en \
    --slang=it,en \
    --osd-playing-msg="" \
    --osd-playing-msg-duration=5000 \
    --osd-font="Nimbus Sans" \
    --osd-font-size=24 \
    --osd-color='#eb9605' \
    --osd-border-size=1 \
    --osd-shadow-offset=3 \
    --osd-shadow-color='#000000' \
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
    --idle=yes \
    --script=nextfile_and_rewind.lua \
    --script=nextfile.lua \
    --script=channel_osd3.lua \
    --script=auto-nextfile.lua \
    --script=eofnotify3.lua \
    --script=charlietv3_keys.lua \
    --script=double_press.lua \
    --fullscreen
