#!/bin/bash

# A modern music progress visualizer for hyprlock with shimmer and scroll animations
# Uses Unicode characters and playerctl

# Configuration
BAR_LEN=25
MAX_TRACK_LENGTH=30

# Symbols
SYMBOL_FILLED="━"
SYMBOL_EMPTY="─"
SYMBOL_GLINT="═"     # Traveling shimmer
SYMBOL_HEAD_A="󰊠"    # Pulsing head state A
SYMBOL_HEAD_B="󰐊"    # Pulsing head state B
SYMBOL_PLAYING="󰐊"
SYMBOL_PAUSED="󰏤"

# Check for playerctl
if ! command -v playerctl >/dev/null 2>&1; then
    exit 0
fi

# Get player status
playerctl_cmd=(playerctl --player=playerctld,spotify,mpd,vlc,firefox,chromium)
status=$("${playerctl_cmd[@]}" status 2>/dev/null)

if [[ -z "$status" || "$status" == "Stopped" ]]; then
    exit 0
fi

# Get metadata
title=$("${playerctl_cmd[@]}" metadata --format '{{title}}' 2>/dev/null)
artist=$("${playerctl_cmd[@]}" metadata --format '{{artist}}' 2>/dev/null)
length_us=$("${playerctl_cmd[@]}" metadata mpris:length 2>/dev/null)
position_us=$("${playerctl_cmd[@]}" metadata --format '{{position}}' 2>/dev/null)

# Fallback for position
if [[ -z "$position_us" ]]; then
    position_us=$(playerctl position 2>/dev/null | awk '{print int($1 * 1000000)}')
fi

# Format track string
if [[ -n "$artist" && -n "$title" ]]; then
    track="$artist - $title"
elif [[ -n "$title" ]]; then
    track="$title"
else
    track="Unknown"
fi

# --- Scrolling Animation ---
if [ ${#track} -gt $MAX_TRACK_LENGTH ]; then
    extended_track="$track   |   "
    total_len=${#extended_track}
    offset=$(( $(date +%s) % total_len ))
    double_track="$extended_track$extended_track"
    track="${double_track:$offset:$MAX_TRACK_LENGTH}"
fi

# Format time (seconds to M:SS)
format_time() {
    local total=$1
    printf "%d:%02d" $((total / 60)) $((total % 60))
}

# Icon based on status
if [[ "$status" == "Playing" ]]; then
    icon="$SYMBOL_PLAYING"
else
    icon="$SYMBOL_PAUSED"
fi

# --- Progress Bar Animation (Shimmer Wave) ---
current_time=$(date +%s)
# The shimmer "glint" moves across the bar every few seconds
# We use a longer cycle for the shimmer to make it feel like a wave
shimmer_pos=$(( (current_time * 2) % (BAR_LEN * 2) )) 

# Head indicator pulse
if (( current_time % 2 == 0 )); then
    indicator="$SYMBOL_HEAD_A"
else
    indicator="$SYMBOL_HEAD_B"
fi

if [[ "$length_us" =~ ^[0-9]+$ ]] && [[ "$length_us" -gt 0 ]]; then
    length_s=$((length_us / 1000000))
    position_s=$((position_us / 1000000))
    
    if ((position_s > length_s)); then position_s=$length_s; fi
    
    progress=$((position_s * BAR_LEN / length_s))
    
    bar=""
    for ((i=0; i<BAR_LEN; i++)); do
        if ((i < progress)); then
            # Filled part: Check if shimmer is here
            if ((i == shimmer_pos)); then
                bar+="$SYMBOL_GLINT"
            else
                bar+="$SYMBOL_FILLED"
            fi
        elif ((i == progress)); then
            # Current position
            bar+="$indicator"
        else
            # Empty part: Subtle shimmer even here, but lighter
            if ((i == shimmer_pos)); then
                bar+="─" # Use a slightly different dash if you want, but keep it clean
            else
                bar+="$SYMBOL_EMPTY"
            fi
        fi
    done
    
    pos_fmt=$(format_time "$position_s")
    len_fmt=$(format_time "$length_s")
    
    echo "$icon $track  [$bar]  $pos_fmt / $len_fmt"
else
    echo "$icon $track"
fi
