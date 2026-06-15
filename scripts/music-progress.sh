#!/bin/bash
set -u

if ! command -v playerctl >/dev/null 2>&1; then
  exit 0
fi

playerctl_cmd=(playerctl --player=playerctld,spotify,mpd,vlc,firefox,chromium)

status="$("${playerctl_cmd[@]}" status 2>/dev/null || true)"
if [[ -z "$status" || "$status" == "Stopped" ]]; then
  exit 0
fi

title="$("${playerctl_cmd[@]}" metadata --format '{{title}}' 2>/dev/null || true)"
artist="$("${playerctl_cmd[@]}" metadata --format '{{artist}}' 2>/dev/null || true)"
length_us="$("${playerctl_cmd[@]}" metadata mpris:length 2>/dev/null || true)"
position_s="$("${playerctl_cmd[@]}" position 2>/dev/null || true)"

track="$title"
if [[ -n "$artist" && -n "$title" ]]; then
  track="$artist - $title"
elif [[ -n "$artist" ]]; then
  track="$artist"
fi
if [[ -z "$track" ]]; then
  track="Unknown track"
fi

format_time() {
  local total=$1
  printf "%d:%02d" $((total / 60)) $((total % 60))
}

is_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

spinner_char() {
  case $(( $(date +%s) % 4 )) in
    0) printf '|';;
    1) printf '/';;
    2) printf '-';;
    3) printf '\\';;
  esac
}

spinner="$(spinner_char)"

if [[ "$length_us" =~ ^[0-9]+$ ]] && is_number "$position_s" && [[ "$length_us" -gt 0 ]]; then
  length_s=$(awk "BEGIN {printf \"%d\", $length_us / 1000000}")
  position_int=$(awk "BEGIN {printf \"%d\", $position_s}")

  if ((length_s > 0)); then
    bar_len=20
    filled=$((position_int * bar_len / length_s))
    if ((filled < 0)); then filled=0; fi
    if ((filled > bar_len)); then filled=$bar_len; fi
    empty=$((bar_len - filled))

    bar=$(printf "%${filled}s" "" | tr ' ' '#')
    pad=$(printf "%${empty}s" "" | tr ' ' '-')

    pos_fmt=$(format_time "$position_int")
    len_fmt=$(format_time "$length_s")

    if [[ "$status" == "Paused" ]]; then
      printf "Paused: %s [%s%s] %s/%s\n" "$track" "$bar" "$pad" "$pos_fmt" "$len_fmt"
    else
      printf "%s %s [%s%s] %s/%s\n" "$spinner" "$track" "$bar" "$pad" "$pos_fmt" "$len_fmt"
    fi
    exit 0
  fi
fi

position_int=""
if is_number "$position_s"; then
  position_int=$(awk "BEGIN {printf \"%d\", $position_s}")
fi

if [[ "$status" == "Paused" ]]; then
  if [[ -n "$position_int" ]]; then
    pos_fmt=$(format_time "$position_int")
    printf "Paused: %s %s\n" "$track" "$pos_fmt"
  else
    printf "Paused: %s\n" "$track"
  fi
else
  if [[ -n "$position_int" ]]; then
    pos_fmt=$(format_time "$position_int")
    printf "%s %s %s\n" "$spinner" "$track" "$pos_fmt"
  else
    printf "%s %s\n" "$spinner" "$track"
  fi
fi
