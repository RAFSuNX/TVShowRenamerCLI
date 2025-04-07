#!/usr/bin/env bash

# --- Configuration ---
CONFIG_FILE="$HOME/.tvrenamerrc"
LOG_FILE="tv_rename_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=0
AUTO_YES=0
declare -A RENAME_MAP
declare -A EPISODE_TRACKER
SEASON_PATTERN="season([0-9]+)"

# --- Dependency Check ---
verify_dependencies() {
    local missing=()
    
    if ! command -v ffprobe &>/dev/null; then
        missing+=("ffmpeg")
    fi
    
    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing required dependencies:"
        for dep in "${missing[@]}"; do
            case $dep in
                "ffmpeg")
                    echo "- ffmpeg (required for media analysis)"
                    echo "  Install with:"
                    echo "  Ubuntu/Debian: sudo apt install ffmpeg"
                    echo "  macOS:         brew install ffmpeg"
                    ;;
                "jq")
                    echo "- jq (required for JSON parsing)"
                    echo "  Install with:"
                    echo "  Ubuntu/Debian: sudo apt install jq"
                    echo "  macOS:         brew install jq"
                    ;;
            esac
        done
        exit 1
    fi
}

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
    max_length=$(( max_length + 10 ))
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
    local original_file="$4"  # Now optional

    while true; do
        read -p "$prompt ${default:+[default: $default]} : " input
        
        # Clean input: remove all non-digits and leading zeros
        cleaned=$(echo "$input" | sed 's/^0*//' | tr -cd '0-9')

        # Handle empty input
        [ -z "$cleaned" ] && cleaned="$default"

        # Validate numeric value
        if [[ "$cleaned" =~ ^[0-9]+$ ]]; then
            # Only track episodes, not seasons
            if [[ -n "$original_file" && "$original_file" != "season_select" ]]; then
                if [[ -n "${EPISODE_TRACKER[$cleaned]}" && "${EPISODE_TRACKER[$cleaned]}" != "$original_file" ]]; then
                    echo "⚠️  Episode $cleaned already used for:"
                    echo "    ${EPISODE_TRACKER[$cleaned]}"
                    read -p "❓ Use this number anyway? (y/n) [n]: " confirm
                    [[ "$confirm" =~ [yY] ]] || continue
                fi
                EPISODE_TRACKER[$cleaned]="$original_file"
            fi
            
            eval "$var_name=$cleaned"
            return 0
        else
            echo "❌ Invalid number! Please try again"
        fi
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
    
    # Check episode patterns
    ep_pattern=$(echo "$filename" | grep -oEi '(episode[ ._-]?|e[ ._-]?)([0-9]+)' | grep -oE '[0-9]+' | tail -1)
    
    [ -z "$ep_pattern" ] && {
        numbers=($(echo "$filename" | grep -oE '\b[0-9]{2,}\b' | grep -vE '^0+'))
    }

    [ -n "$ep_pattern" ] && {
        # Clean detected episode number
        echo $(echo "$ep_pattern" | sed 's/^0*//')
        return
    }

    case ${#numbers[@]} in
        0) echo "0" ;;
        1) echo $(echo "${numbers[0]}" | sed 's/^0*//') ;;
        *) echo "0" ;;
    esac
}

get_media_info() {
    local file="$1"
    local json_data=$(ffprobe -v quiet -print_format json -show_streams "$file" 2>/dev/null)
    
    # Get video stream info
    local width=$(echo "$json_data" | jq -r '[.streams[] | select(.codec_type=="video")][0] | .width')
    local height=$(echo "$json_data" | jq -r '[.streams[] | select(.codec_type=="video")][0] | .height')
    width=${width:-0}
    height=${height:-0}

    # Determine resolution
    if [[ $width -eq 7680 && $height -eq 4320 ]]; then
        resolution="8K"
    elif [[ $width -eq 3840 && $height -eq 2160 ]]; then
        resolution="4K"
    elif [[ $width -eq 1920 && $height -eq 1080 ]]; then
        resolution="1080p"
    elif [[ $width -eq 1280 && $height -eq 720 ]]; then
        resolution="720p"
    else
        resolution="${height}p"
    fi

    # Detect codec
    local codec=$(echo "$json_data" | jq -r '[.streams[] | select(.codec_type=="video")][0] | .codec_name')
    case "$codec" in
        "hevc") codec="H.265" ;;
        "h264") codec="H.264" ;;
        "av1")  codec="AV1" ;;
        *)      codec=$(echo "$codec" | tr '[:lower:]' '[:upper:]') ;;
    esac
    codec=${codec:-UNKNOWN}

    echo "${resolution}:${codec}"
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
verify_dependencies
echo "TV Series Organizer (Professional Edition)"
echo "─────────────────────────────────────────"

# User inputs
read -p "📂 Enter series folder path: " SERIES_FOLDER
SERIES_FOLDER=$(realpath "${SERIES_FOLDER%/}")
[ ! -d "$SERIES_FOLDER" ] && { log "❌ Directory does not exist!"; exit 1; }

# Existing seasons detection
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

# Season part configuration
read -p "➤ Enter season part/subfolder (optional): " SEASON_PART
SEASON_PART=$(sanitize_dir "$SEASON_PART")

# Target directory setup
TARGET_DIR="${SERIES_FOLDER}/season${season_padded}"
[ -n "$SEASON_PART" ] && TARGET_DIR="${TARGET_DIR}/${SEASON_PART}"

# Handle existing directory
if [ -d "$TARGET_DIR" ]; then
    LAST_EP=$(get_last_episode "$TARGET_DIR")
    if [ -n "$LAST_EP" ]; then
        echo "⚠️  Directory contains ${LAST_EP} episodes!"
        read -p "Continue? (y/n): " confirm
        [[ "$confirm" != "y" ]] && exit
    fi
else
    echo "Creating directory: $TARGET_DIR"
    if ! mkdir -p "$TARGET_DIR"; then
        log "❌ Failed to create directory: $TARGET_DIR"
        exit 1
    fi
    log "Created directory: $TARGET_DIR"
    sleep 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    log "❌ Target directory verification failed: $TARGET_DIR"
    exit 1
fi

# Episode counter initialization
EPISODE_COUNTER=$((10#${LAST_EP:-0} + 1))

# File processing
mapfile -d $'\0' files < <(find "$SERIES_FOLDER" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.m4v" \) -print0)

for file in "${files[@]}"; do
    clear
    filename=$(basename "$file")
    highlight_file "$filename"

    # Episode detection
    detected_ep=$(detect_episode_number "$filename")
    default_ep=$EPISODE_COUNTER
    [ "$detected_ep" -gt 0 ] && default_ep=$detected_ep

    # Episode validation
    validate_number episode "➤ Enter episode number (detected: ${detected_ep})" "$default_ep" "$filename"
    EPISODE_COUNTER=$((10#$episode + 1))
    
    # Smart episode formatting
    decimal_episode=$((10#$episode))
    if [[ $decimal_episode -lt 100 ]]; then
        episode_padded=$(printf "%02d" "$decimal_episode")
    else
        episode_padded=$(printf "%03d" "$decimal_episode")
    fi

    # Media analysis
    IFS=":" read media_resolution media_codec <<< "$(get_media_info "$file")"

    # Filename construction
    new_name="${SERIES_TITLE}_S${season_padded}E${episode_padded}"
    [ "$dual_audio" == "y" ] && new_name+="_Dual"
    new_name+="_${media_resolution}_${media_codec}"

    # Conflict resolution
    version=1
    while true; do
        target_file="${TARGET_DIR}/${new_name}"
        [ $version -gt 1 ] && target_file+="_v${version}"
        target_file+=".${file##*.}"

        [ -e "$target_file" ] && ((version++)) || break
    done

    RENAME_MAP["$file"]="$target_file"
done

# Final confirmation
show_summary

[ $AUTO_YES -eq 0 ] && {
    read -p "Proceed with renaming? (y/n): " confirm
    [[ ! "$confirm" =~ [yY] ]] && exit
}

# Execution phase
for key in "${!RENAME_MAP[@]}"; do
    target="${RENAME_MAP[$key]}"
    
    if [ -e "$target" ]; then
        log "⚠️  Conflict detected: Skipping $(basename "$target")"
        continue
    fi

    if [ $DRY_RUN -eq 1 ]; then
        log "Dry run: $(basename "$key") ➔ $(basename "$target")"
    else
        mv -v "$key" "$target" 2>&1 | tee -a "$LOG_FILE"
    fi
done

# Cleanup
[ $DRY_RUN -eq 0 ] && find "$SERIES_FOLDER" -type d -empty -delete 2>/dev/null

log "✅ Operation completed successfully"
echo -e "\nLog saved to: $LOG_FILE"
