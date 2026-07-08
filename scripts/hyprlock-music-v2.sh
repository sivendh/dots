#!/usr/bin/env bash
# hyprlock-music-v2.sh — Modern music widget for Hyprlock
# A premium, minimal music player display with Pango-colored progress bars,
# scrolling track names, and rich player integration.
#
# Dependencies: playerctl (required), curl (for remote art), ImageMagick (optional, for art cropping)

set -Eeuo pipefail

# ============================================================================
# Configuration
# ============================================================================
PREFERRED_PLAYERS="spotify,mpv,vlc,firefox,chromium,brave,chrome"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hyprlock-art"
SQUARE_SIZE=512
mkdir -p "$CACHE_DIR"

# Progress bar style
BAR_LENGTH=20
BAR_FILLED="━"
BAR_EMPTY="─"
BAR_HANDLE="●"

# Colors (hex without #)
COLOR_ACCENT="c4a7e7"       # Soft lavender
COLOR_ACCENT_DIM="c4a7e780" # Lavender dimmed
COLOR_TEXT="e0def4"          # Soft white
COLOR_SUBTEXT="908caa"      # Muted gray-purple
COLOR_DIM="6e6a86"          # Very muted
COLOR_PLAYING="9ccfd8"      # Teal/cyan for playing
COLOR_PAUSED="f6c177"       # Warm amber for paused

# Scrolling
MAX_TITLE_LEN=32
MAX_ARTIST_LEN=28
SCROLL_SPEED=1  # chars per second

# ============================================================================
# Helpers
# ============================================================================
have() { command -v "$1" >/dev/null 2>&1; }

select_player() {
  if have playerctl && playerctl -p "$PREFERRED_PLAYERS" status >/dev/null 2>&1; then
    echo "$PREFERRED_PLAYERS"
  else
    echo ""
  fi
}

pctl() {
  local player
  player="$(select_player)"
  if [[ -n "$player" ]]; then
    playerctl -p "$player" "$@" 2>/dev/null || true
  else
    playerctl "$@" 2>/dev/null || true
  fi
}

get_metadata() {
  pctl metadata --format "{{ $1 }}"
}

get_status() {
  pctl status
}

# Scrolling text — creates a smooth marquee effect
scroll_text() {
  local str="$1"
  local max_len="$2"
  local len=${#str}

  if ((len <= max_len)); then
    printf '%s' "$str"
    return
  fi

  local padded="$str    ·    "
  local padded_len=${#padded}
  local epoch
  epoch=$(date +%s)
  local offset=$(( (epoch * SCROLL_SPEED) % padded_len ))
  local doubled="$padded$padded"
  printf '%s' "${doubled:$offset:$max_len}"
}

# Static truncation with ellipsis
trim_text() {
  local str="${1:-}"
  local max_len="${2:-30}"
  if ((${#str} <= max_len)); then
    printf '%s' "$str"
  else
    printf '%s…' "${str:0:$((max_len - 1))}"
  fi
}

# ============================================================================
# Time helpers
# ============================================================================
us_to_mmss() {
  local us="$1"
  [[ "$us" =~ ^[0-9]+$ ]] || { printf "0:00"; return; }
  local s=$((us / 1000000))
  printf '%d:%02d' $((s / 60)) $((s % 60))
}

get_position_us() {
  local raw
  raw="$(pctl position)" || true
  if [[ -n "$raw" ]]; then
    awk "BEGIN {printf \"%d\", $raw * 1000000}" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# ============================================================================
# Progress bar (Pango markup)
# ============================================================================
generate_progress_bar() {
  local pos_us="$1"
  local len_us="$2"
  local status="$3"

  local handle_color="$COLOR_ACCENT"
  local filled_color="$COLOR_ACCENT"
  local empty_color="$COLOR_DIM"

  if [[ "$status" == "Paused" ]]; then
    handle_color="$COLOR_PAUSED"
    filled_color="$COLOR_PAUSED"
  fi

  if [[ ! "$len_us" =~ ^[0-9]+$ ]] || [[ "$len_us" -le 0 ]]; then
    # No length info — show empty bar
    local empty_bar=""
    for ((i = 0; i < BAR_LENGTH; i++)); do
      empty_bar+="$BAR_EMPTY"
    done
    printf '<span foreground="#%s">%s</span>' "$empty_color" "$empty_bar"
    return
  fi

  local percent=$((pos_us * 100 / len_us))
  ((percent > 100)) && percent=100
  ((percent < 0)) && percent=0

  local progress=$((percent * BAR_LENGTH / 100))
  ((progress > BAR_LENGTH)) && progress=$BAR_LENGTH
  ((progress < 0)) && progress=0

  local bar_played="" bar_remaining=""
  for ((i = 0; i < progress; i++)); do bar_played+="$BAR_FILLED"; done
  for ((i = progress; i < BAR_LENGTH; i++)); do bar_remaining+="$BAR_EMPTY"; done

  if ((progress == BAR_LENGTH)); then
    printf '<span foreground="#%s">%s%s</span>' \
      "$filled_color" "$bar_played" "$BAR_HANDLE"
  elif ((progress == 0)); then
    printf '<span foreground="#%s">%s</span><span foreground="#%s">%s</span>' \
      "$handle_color" "$BAR_HANDLE" "$empty_color" "$bar_remaining"
  else
    printf '<span foreground="#%s">%s</span><span foreground="#%s">%s</span><span foreground="#%s">%s</span>' \
      "$filled_color" "$bar_played" "$handle_color" "$BAR_HANDLE" "$empty_color" "$bar_remaining"
  fi
}

# ============================================================================
# Album art
# ============================================================================
download_to_cache() {
  local url="$1"
  local filename
  filename="$(printf '%s' "$url" | sha256sum | awk '{print $1}').img"
  local output="$CACHE_DIR/$filename"
  if [[ ! -s "$output" ]]; then
    have curl && curl -fsSL --max-time 5 "$url" -o "$output" 2>/dev/null || true
  fi
  printf '%s' "$output"
}

create_square_cover() {
  local input="$1"
  local basename
  basename="$(basename "$input")"
  local output="$CACHE_DIR/${basename%.*}_sq_${SQUARE_SIZE}.jpg"
  if [[ -s "$output" && "$output" -nt "$input" ]]; then
    printf '%s' "$output"
    return
  fi
  if have convert; then
    convert "$input" -auto-orient -gravity center \
      -thumbnail "${SQUARE_SIZE}x${SQUARE_SIZE}^" \
      -extent "${SQUARE_SIZE}x${SQUARE_SIZE}" \
      -quality 90 "$output" 2>/dev/null && printf '%s' "$output" && return
  fi
  printf '%s' "$input"
}

get_album_art_path() {
  local url
  url="$(get_metadata 'mpris:artUrl')"
  [[ -n "$url" ]] || { printf ''; return; }
  local local_path=""
  case "$url" in
    file://*) local_path="${url#file://}" ;;
    http://*|https://*) local_path="$(download_to_cache "$url")" ;;
    *) printf ''; return ;;
  esac
  [[ -n "$local_path" && -s "$local_path" ]] || { printf ''; return; }
  create_square_cover "$local_path"
}

# ============================================================================
# Player icons & display
# ============================================================================
get_player_icon() {
  local active
  active="$(pctl -l 2>/dev/null | head -n1 || true)"
  case "${active,,}" in
    spotify*)  printf '󰓇' ;;
    firefox*)  printf '󰈹' ;;
    chromium*) printf '󰊯' ;;
    brave*)    printf '󰞀' ;;
    chrome*)   printf '󰊯' ;;
    mpv*)      printf '󰕼' ;;
    vlc*)      printf '󰕼' ;;
    *)         printf '󰎆' ;;
  esac
}

get_status_icon() {
  case "$(get_status | tr '[:upper:]' '[:lower:]')" in
    playing) printf '󰏤' ;;
    paused)  printf '󰐊' ;;
    *)       printf '󰓛' ;;
  esac
}

# ============================================================================
# Composited single-line output (for inline label in hyprlock.conf)
# ============================================================================
compose_inline() {
  local status
  status="$(get_status)"
  [[ -n "$status" && "$status" != "Stopped" ]] || exit 0

  local title artist
  title="$(get_metadata 'xesam:title')"
  artist="$(get_metadata 'xesam:artist')"
  [[ -n "$title" ]] || title="Nothing Playing"

  local len_us pos_us
  len_us="$(get_metadata 'mpris:length')"
  pos_us="$(get_position_us)"

  local pos_fmt len_fmt
  pos_fmt="$(us_to_mmss "$pos_us")"
  len_fmt="$(us_to_mmss "${len_us:-0}")"

  local bar
  bar="$(generate_progress_bar "$pos_us" "${len_us:-0}" "$status")"

  local icon player_icon
  icon="$(get_status_icon)"
  player_icon="$(get_player_icon)"

  local display_title
  display_title="$(scroll_text "$title" "$MAX_TITLE_LEN")"

  local time_color="$COLOR_SUBTEXT"
  local icon_color="$COLOR_ACCENT"
  if [[ "$status" == "Paused" ]]; then
    icon_color="$COLOR_PAUSED"
  fi

  # Compact inline: icon · title · bar · time
  printf '<span foreground="#%s">%s</span>  %s  %s  <span foreground="#%s">%s / %s</span>' \
    "$icon_color" "$icon" \
    "$display_title" \
    "$bar" \
    "$time_color" "$pos_fmt" "$len_fmt"
}

# ============================================================================
# CLI
# ============================================================================
case "${1:-}" in
  --title)
    title="$(get_metadata 'xesam:title')"
    status="$(get_status)"
    [[ -n "$status" && "$status" != "Stopped" ]] || exit 0
    printf '%s\n' "$(scroll_text "${title:-Nothing Playing}" "$MAX_TITLE_LEN")"
    ;;
  --artist)
    artist="$(get_metadata 'xesam:artist')"
    status="$(get_status)"
    [[ -n "$status" && "$status" != "Stopped" ]] || exit 0
    printf '%s\n' "$(trim_text "${artist:-}" "$MAX_ARTIST_LEN")"
    ;;
  --status)
    status="$(get_status)"
    [[ -n "$status" && "$status" != "Stopped" ]] || exit 0
    printf '%s\n' "$(get_status_icon)"
    ;;
  --player-icon)
    status="$(get_status)"
    [[ -n "$status" && "$status" != "Stopped" ]] || exit 0
    printf '%s\n' "$(get_player_icon)"
    ;;
  --player)
    active="$(pctl -l 2>/dev/null | head -n1 || true)"
    status="$(get_status)"
    [[ -n "$status" && "$status" != "Stopped" ]] || exit 0
    case "${active,,}" in
      spotify*)  printf '󰓇  Spotify\n' ;;
      firefox*)  printf '󰈹  Firefox\n' ;;
      chromium*) printf '󰊯  Chromium\n' ;;
      brave*)    printf '󰞀  Brave\n' ;;
      chrome*)   printf '󰊯  Chrome\n' ;;
      mpv*)      printf '󰕼  mpv\n' ;;
      vlc*)      printf '󰕼  VLC\n' ;;
      *)         printf '%s\n' "${active:-Unknown}" ;;
    esac
    ;;
  --progress-bar)
    status="$(get_status)"
    [[ -n "$status" && "$status" != "Stopped" ]] || exit 0
    len_us="$(get_metadata 'mpris:length')"
    pos_us="$(get_position_us)"
    printf '%s\n' "$(generate_progress_bar "$pos_us" "${len_us:-0}" "$status")"
    ;;
  --time)
    status="$(get_status)"
    [[ -n "$status" && "$status" != "Stopped" ]] || exit 0
    len_us="$(get_metadata 'mpris:length')"
    pos_us="$(get_position_us)"
    printf '%s / %s\n' "$(us_to_mmss "$pos_us")" "$(us_to_mmss "${len_us:-0}")"
    ;;
  --art)
    status="$(get_status)"
    [[ -n "$status" && "$status" != "Stopped" ]] || exit 0
    printf '%s\n' "$(get_album_art_path)"
    ;;
  --inline)
    compose_inline
    ;;
  --help|*)
    cat <<EOF
Usage: $(basename "$0") [OPTION]

Modern music widget for Hyprlock v2.

Options:
  --title         Scrolling song title
  --artist        Artist name (trimmed)
  --status        Play/pause/stop icon
  --player-icon   Player source icon (Spotify, Firefox, etc.)
  --player        Player name with icon
  --progress-bar  Pango-colored progress bar
  --time          Position / Duration (mm:ss)
  --art           Path to cached square album art
  --inline        Full composited single-line output
  --help          Show this help

EOF
    ;;
esac
