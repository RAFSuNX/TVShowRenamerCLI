#!/usr/bin/env bash

# --- Configuration ---
CONFIG_FILE="$HOME/.tvrenamerrc"
LOG_FILE="tv_rename_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=0
AUTO_YES=0
declare -A RENAME_MAP
SEASON_PATTERN="season([0-9]+)"

# --- Load Configuration ---
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# --- Functions ---
highlight_file() {
    local filename="$1"
    local length=$((${#filename} + 2))
    local separator=$(printf '%*s' "$length" | tr ' ' '-')

    echo
    echo "┌$separator┐"
    echo "│ $filename │"
    echo "└$separator┘"
}

highlight_summary_entry() {
    local original="$1"
    local new="$2"
    local line1="Original: $(tput setaf 1)${original}$(tput sgr0)"
    local line2="Renamed:  $(tput setaf 2)${new}$(tput sgr0)"
    local length1=${#original}
    local length2=${#new}
    local max_length=$(( length1 > length2 ? length1 : length2 ))
    max_length=$(( max_length + 10 ))  # Account for prefix text
    local separator=$(printf '%*s' "$max_length" | tr ' ' '-')

    echo
    echo "┌─$separator─┐"
    printf "│ %-${max_length}s │\n" "$line1"
    printf "│ %-${max_length}s │\n" "$line2"
    echo "└─$separator─┘"
}

log() {
    local message="$(date +'%Y-%m-%d %H:%M:%S') - $*"
    echo "$message" >> "$LOG_FILE"
    echo "$message"
}

validate_number() {
    local var_name="$1"
    local prompt="$2"
    local default="$3"

    while true; do
        read -p "$prompt ${default:+[default: $default]} : " input
        cleaned=$(echo "$input" | tr -cd '0-9')
        
        # Fix for leading zeros
        if [[ "$cleaned" =~ ^0+([1-9]+) ]]; then
            cleaned="${BASH_REMATCH[1]}"
        elif [[ "$cleaned" == "0" ]]; then
            cleaned="0"
        fi

        if [[ -z "$cleaned" && -n "$default" ]]; then
            eval "$var_name=$default"
            return 0
        elif [[ -n "$cleaned" && "$cleaned" =~ ^[0-9]+$ ]]; then
            eval "$var_name=$cleaned"
            return 0
        fi
        echo "❌ Invalid number! Please try again"
    done
}

sanitize_dir() {
    echo "$1" | tr ' ' '_' | sed -E 's/[^a-zA-Z0-9_/-]//g'
}

detect_existing_seasons() {
    find "$SERIES_FOLDER" -maxdepth 1 -type d -iname 'season*' -exec basename {} \; |
    while read -r dir; do
        if [[ "$dir" =~ $SEASON_PATTERN ]]; then
            echo "${BASH_REMATCH[1]#0}"
        fi
    done | sort -n | uniq
}

detect_episode_number() {
    local filename="$1"
    local numbers=()

    # Extract all standalone numbers from filename
    while IFS= read -r line; do
        numbers+=("$line")
    done < <(echo "$filename" | grep -oE '\b[0-9]+\b' | grep -vE '^0+$')

    case ${#numbers[@]} in
        0)
            echo "0"
            ;;
        1)
            echo "${numbers[0]}"
            ;;
        *)
            echo "0"
            ;;
    esac
}

get_last_episode() {
    local target_dir="$1"
    find "$target_dir" -maxdepth 1 -type f -iname "*_S??E??*" -printf "%f\n" |
    grep -oE 'E([0-9]+)' |
    cut -d'E' -f2 |
    sort -n |
    tail -1
}

show_summary() {
    echo -e "\n$(tput bold)📝 Renaming Summary:$(tput sgr0)"
    echo "────────────────────"
    for key in "${!RENAME_MAP[@]}"; do
        original=$(basename "$key")
        new=$(basename "${RENAME_MAP[$key]}")
        highlight_summary_entry "$original" "$new"
    done
    echo -e "$(tput bold)Total files to process: ${#RENAME_MAP[@]}$(tput sgr0)\n"
}

# --- Main Script ---
echo "📺 TV Show Renamer CLI"
echo "──────────────────────────────────────────"

# Get inputs
read -p "📂 Enter series folder path: " SERIES_FOLDER
SERIES_FOLDER="${SERIES_FOLDER%/}"
[ ! -d "$SERIES_FOLDER" ] && { log "❌ Directory does not exist!"; exit 1; }

# Detect existing seasons
EXISTING_SEASONS=($(detect_existing_seasons))
[ ${#EXISTING_SEASONS[@]} -gt 0 ] &&
    echo "🔍 Found existing seasons: ${EXISTING_SEASONS[*]}"

read -p "🎞️ Enter series title: " SERIES_TITLE
SERIES_TITLE=$(echo "$SERIES_TITLE" | tr ' ' '_' | sed -E 's/[^a-zA-Z0-9_-]//g')

dual_audio="n"
read -p "🔊 Dual Audio? (y/n): " dual_audio
dual_audio=${dual_audio,,}

# Season selection
validate_number season "➤ Enter main season number" "${EXISTING_SEASONS[0]}"
season_padded=$(printf "%02d" "$season")

# Custom season part selection
read -p "➤ Enter season part/subfolder (e.g., part01, finals, leave empty if none): " SEASON_PART
SEASON_PART=$(sanitize_dir "$SEASON_PART")

# Build target directory
TARGET_DIR="${SERIES_FOLDER}/season${season_padded}"
[ -n "$SEASON_PART" ] && TARGET_DIR="${TARGET_DIR}/${SEASON_PART}"

# Handle existing directory
if [ -d "$TARGET_DIR" ]; then
    LAST_EP=$(get_last_episode "$TARGET_DIR")
    if [ -n "$LAST_EP" ]; then
        echo "⚠️  Directory already contains ${LAST_EP} episodes!"
        read -p "Continue with existing directory? (y/n): " confirm
        [[ "$confirm" != "y" ]] && exit
    fi
else
    mkdir -p "$TARGET_DIR"
    log "Created directory: $TARGET_DIR"
fi

# Set initial episode counter
EPISODE_COUNTER=$((10#${LAST_EP:-0} + 1))

# Process only files in main directory
mapfile -d $'\0' files < <(find "$SERIES_FOLDER" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.m4v" \) -print0)

for file in "${files[@]}"; do
    clear
    filename=$(basename "$file")
    highlight_file "$filename"

    # Auto-detect possible episode number
    detected_ep=$(detect_episode_number "$filename")
    default_ep=$EPISODE_COUNTER
    [ "$detected_ep" -gt 0 ] && default_ep=$detected_ep

    # Episode input with auto-increment and detection
    validate_number episode "➤ Enter episode number (detected: ${detected_ep})" "$default_ep"
    EPISODE_COUNTER=$((10#$episode + 1))
    episode_padded=$(printf "%02d" "$((10#$episode))")

    # Build new filename
    new_name="${SERIES_TITLE}_S${season_padded}E${episode_padded}"
    [ "$dual_audio" == "y" ] && new_name+="_Dual"
    new_name+="_1080p_H.265.${file##*.}"

    # Store in rename map
    RENAME_MAP["$file"]="${TARGET_DIR}/${new_name}"
done

# Show summary and confirm
show_summary

[ $AUTO_YES -eq 0 ] && {
    read -p "Proceed with renaming? (y/n): " confirm
    [[ ! "$confirm" =~ [yY] ]] && exit
}

# Execute renames
for key in "${!RENAME_MAP[@]}"; do
    target="${RENAME_MAP[$key]}"

    [ -e "$target" ] && {
        log "⚠️  Skipping existing file: $(basename "$target")"
        continue
    }

    if [ $DRY_RUN -eq 1 ]; then
        log "Dry run: mv \"$(basename "$key")\" ➔ \"$(basename "$target")\""
    else
        mv -v "$key" "$target" 2>&1 | tee -a "$LOG_FILE"
    fi
done

# Cleanup empty directories
[ $DRY_RUN -eq 0 ] && find "$SERIES_FOLDER" -type d -empty -delete 2>/dev/null

log "✅ Operation completed successfully"
echo -e "\nLog saved to: $LOG_FILE"
