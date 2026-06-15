#!/bin/bash

# ~/.config/hypr/scripts/music_info.sh

# Get current player info
get_player() {
    playerctl -l 2>/dev/null | head -n 1
}

get_status() {
    playerctl status 2>/dev/null
}

case "$1" in
    --title)
        title=$(playerctl metadata title 2>/dev/null)
        if [[ -z "$title" ]]; then
            echo "No Media"
        else
            # Truncate if too long
            if [[ ${#title} -gt 35 ]]; then
                echo "${title:0:32}..."
            else
                echo "$title"
            fi
        fi
        ;;
    --artist)
        artist=$(playerctl metadata artist 2>/dev/null)
        if [[ -z "$artist" ]]; then
            echo "Unknown Artist"
        else
            # Truncate if too long
            if [[ ${#artist} -gt 35 ]]; then
                echo "${artist:0:32}..."
            else
                echo "$artist"
            fi
        fi
        ;;
    --player-icon)
        player=$(get_player)
        case "$player" in
            *spotify*) echo "" ;;
            *firefox*) echo "" ;;
            *chrome*) echo "" ;;
            *brave*) echo "" ;;
            *mpv*) echo "" ;;
            *vlc*) echo "󰕼" ;;
            *) echo "󰎆" ;;
        esac
        ;;
    --status-icon)
        status=$(get_status)
        if [[ "$status" == "Playing" ]]; then
            echo "󰏤" # Pause icon
        else
            echo "󰐊" # Play icon
        fi
        ;;
    --progress)
        status=$(get_status)
        if [[ -z "$status" ]]; then
            echo ""
            exit 0
        fi
        pos=$(playerctl position 2>/dev/null | cut -d'.' -f1)
        len=$(playerctl metadata mpris:length 2>/dev/null)
        if [[ -n "$len" && "$len" -gt 0 ]]; then
            len_sec=$((len / 1000000))
            if [[ "$len_sec" -gt 0 ]]; then
                percent=$((pos * 100 / len_sec))
            else
                percent=0
            fi
        else
            percent=0
        fi
        bar_len=25
        filled=$((percent * bar_len / 100))
        [[ $filled -lt 0 ]] && filled=0
        [[ $filled -gt $bar_len ]] && filled=$bar_len
        empty=$((bar_len - filled))
        
        res=""
        for ((i=0; i<filled; i++)); do res+="─"; done
        res+="●"
        for ((i=0; i<empty; i++)); do res+="─"; done
        echo "$res"
        ;;
    --progress-alt)
        status=$(get_status)
        if [[ -z "$status" ]]; then
            echo ""
            exit 0
        fi
        pos=$(playerctl position 2>/dev/null | cut -d'.' -f1)
        len=$(playerctl metadata mpris:length 2>/dev/null)
        if [[ -n "$len" && "$len" -gt 0 ]]; then
            len_sec=$((len / 1000000))
            if [[ "$len_sec" -gt 0 ]]; then
                percent=$((pos * 100 / len_sec))
            else
                percent=0
            fi
        else
            percent=0
        fi
        bar_len=15
        filled=$((percent * bar_len / 100))
        [[ $filled -lt 0 ]] && filled=0
        [[ $filled -gt $bar_len ]] && filled=$bar_len
        empty=$((bar_len - filled))
        res=""
        for ((i=0; i<filled; i++)); do res+="█"; done
        for ((i=0; i<empty; i++)); do res+="░"; done
        echo "$res"
        ;;
    --time)
        pos=$(playerctl position 2>/dev/null | cut -d'.' -f1)
        len=$(playerctl metadata mpris:length 2>/dev/null)
        if [[ -n "$len" && "$len" -gt 0 ]]; then
            len_sec=$((len / 1000000))
            # Format as MM:SS / MM:SS
            printf "%02d:%02d / %02d:%02d" $((pos/60)) $((pos%60)) $((len_sec/60)) $((len_sec%60))
        else
            echo "00:00 / 00:00"
        fi
        ;;
    --update-art)
        # This part fetches the art and saves it to a temp file
        art_url=$(playerctl metadata mpris:artUrl 2>/dev/null)
        dest="/tmp/hyprlock_art.png"
        if [[ -z "$art_url" ]]; then
            # Default icon if no art
            # You might want to provide a fallback image path
            exit 0
        fi
        
        if [[ "$art_url" == file://* ]]; then
            cp "${art_url#file://}" "$dest"
        elif [[ "$art_url" == http* ]]; then
            curl -s "$art_url" -o "$dest"
        fi
        ;;
esac
