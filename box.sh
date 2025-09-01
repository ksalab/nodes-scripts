#!/bin/bash

# Define colors
RESET=$'\e[0m'               # Reset to default
GRAY=$'\e[38;5;244m'         # Gray
LIGHT_GRAY=$'\e[38;5;250m'   # Light gray
GREEN=$'\e[38;5;34m'         # Green
LIGHT_GREEN=$'\e[38;5;46m'   # Light green
RED=$'\e[38;5;196m'          # Red
LIGHT_RED=$'\e[38;5;203m'    # Light red
BLUE=$'\e[38;5;39m'          # Blue
LIGHT_BLUE=$'\e[38;5;51m'    # Light blue
PURPLE=$'\e[38;5;141m'       # Purple
LIGHT_PURPLE=$'\e[38;5;183m' # Light purple
ORANGE=$'\e[38;5;214m'       # Orange
YELLOW=$'\e[38;5;226m'       # Yellow
CYAN=$'\e[38;5;44m'          # Cyan
LIGHT_CYAN=$'\e[38;5;87m'    # Light cyan
PINK=$'\e[38;5;213m'         # Pink
BROWN=$'\e[38;5;94m'         # Brown
WHITE=$'\e[38;5;231m'        # White
BLACK=$'\e[38;5;16m'         # Black

NAME="0g (ZeroGravity) storage Block Scanner"
VER="1.0.0"

function text_box() {
    local header_text="${1^^}"
    local message=$(echo "$2" | fold -sw $((`tput cols` - 4))) # Maximum text size, determined by terminal size - 4
    local color="$3"

    # Check input parameters
    if [[ -z "$header_text" || -z "$message" ]]; then
        echo "Error: Missing required parameters (header_text or message)."
        return 1
    fi

    # Set the frame color
    local reset=$'\e[0m'
    local frame_color=$(get_frame_color "$header_text")

    # If no text color is specified, use the frame color
    local text_color
    if [[ -n $color ]]; then
        text_color=$"\e[38;5;"$color"m"
    else
        text_color=$frame_color
    fi

    # Получаем эмоджи для заголовка
    local emoji=$(get_emoji "$header_text")

    # Split the message into lines
    local IFS=$'\n'
    local lines=($message)
    local max_length=0

    # Find the maximum length of the string
    for line in "${lines[@]}"; do
        local len=${#line}
        if (( len > max_length )); then
        max_length=$len
        fi
    done

    (( max_length++ ))

    if [[ "$header_text" == "MAINTITLE" ]]; then
        local border=$(printf "%${max_length}s" "")
        echo -e "${frame_color}╔═${border//?/═}═╗"
        for line in "${lines[@]}"; do
            local padding=$(( max_length - ${#line} ))
            local padded_line="${text_color}${line}${text_color}$(printf "%${padding}s" " ")$frame_color"
            echo -e "║ ${padded_line} ║"
        done
        echo -e "${frame_color}╚═${border//?/═}═╝${reset}"
    else
        # Form the upper boundary
        local header_padding=$(( max_length - ${#header_text} - 4 ))
        local header=${message:0:header_padding}
        echo -e "${frame_color}╭─ ${emoji} ${text_color}${header_text}${frame_color} ${header//?/─}╮"
        # Form the message lines
        for line in "${lines[@]}"; do
            local padding=$(( max_length - ${#line} ))
            local padded_line="${text_color}${line}${text_color}$(printf "%${padding}s" " ")$frame_color"
            echo -e "│ ${padded_line} │"
        done
        # Form the lower boundary
        local border=$(printf "%$((max_length + ${#emoji}))s" "")
        echo -e "╰─${border//?/─}╯${reset}"
    fi

    unset border line padding padded_line
}

function get_emoji() {
    case "$1" in
        DEBUG) echo "🐛" ;;      # Bug emoji
        DONE) echo "✅" ;;       # Checkmark emoji
        ERROR) echo "❌" ;;      # Cross emoji
        INFO) echo "📝" ;;       # Info emoji
        NOTE) echo "💬" ;;       # Note emoji
        TASK) echo "📂" ;;       # Tools emoji
        TITLE) echo "📌" ;;      # Pin emoji
        WARNING) echo "❗️" ;;    # Warning emoji
        MAINTITLE) echo "" ;;  # Star emoji
        *) echo "🔹" ;;          # Default emoji
    esac
}

function get_frame_color() {
    case "$1" in
        DEBUG) echo "$GRAY" ;;            # Gray
        DONE) echo "$GREEN" ;;            # Green
        ERROR) echo "$RED" ;;             # Red
        INFO) echo "$BLUE" ;;             # Blue
        MAINTITLE) echo "$LIGHT_GREEN" ;; # Light green
        NOTE) echo "$LIGHT_BLUE" ;;       # Light blue
        TASK) echo "$PURPLE" ;;           # Purple
        TITLE) echo "$LIGHT_GREEN" ;;     # Light green
        WARNING) echo "$ORANGE" ;;        # Orange
        ANY) echo "$YELLOW" ;;            # Yellow
        *) echo "$GRAY" ;;                # Default: Gray
    esac
}

text_box "INFO" "${NAME} v${VER}"
text_box "DONE" "${NAME} v${VER} ${NAME} v${VER}"
text_box "MAINTITLE" "${NAME} v${VER}"

echo -e "${GRAY}This is a success message.${RESET}"
echo -e "${LIGHT_GRAY}This is a success message.${RESET}"
echo -e "${GREEN}This is a success message.${RESET}"
echo -e "${LIGHT_GREEN}This is a success message.${RESET}"
echo -e "${RED}This is an error message.${RESET}"
echo -e "${LIGHT_RED}This is an error message.${RESET}"
echo -e "${BLUE}This is an informational message.${RESET}"
echo -e "${LIGHT_BLUE}This is an informational message.${RESET}"
echo -e "${PURPLE}This is an informational message.${RESET}"
echo -e "${LIGHT_PURPLE}This is an informational message.${RESET}"
echo -e "${ORANGE}This is a warning message.${RESET}"
echo -e "${YELLOW}This is a warning message.${RESET}"
echo -e "${CYAN}This is a debug message.${RESET}"
echo -e "${LIGHT_CYAN}This is a debug message.${RESET}"
echo -e "${PINK}This is a debug message.${RESET}"
echo -e "${BROWN}This is a debug message.${RESET}"
echo -e "${WHITE}This is a debug message.${RESET}"
echo -e "${BLACK}This is a debug message.${RESET}"