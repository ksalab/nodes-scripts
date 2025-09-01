#!/bin/bash

# Set the version variable
NAME="0g (ZeroGravity) storage Log Scanner"
BIN_VER="1.0.0"
CURRENT_DATE=$(TZ=UTC date +%Y-%m-%d)

# Export the version variable to make it available in the sourced script
VER="${NAME} ${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "❌ Failed to load utility script!"
    exit 1
fi

# Processing a command line parameter
case "$1" in
    user) BASE_PATH="/home/ritual" ;;
    root | "") BASE_PATH="/root" ;;
    *)
        text_box "ERROR" "Invalid parameter. Use 'user' or 'root'."
        exit 1
        ;;
esac

# Checking the existence of a directory
if [[ ! -d "${BASE_PATH}/0g-storage-node" ]]; then
    text_box "ERROR" "Directory ${BASE_PATH}/0g-storage-node does not exist."
    exit 1
fi

# Trap signals for graceful exit
trap 'echo "Exiting..."; exit 0' SIGINT SIGTERM

# Monitor logs
while true; do
    log_file="${BASE_PATH}/0g-storage-node/run/log/zgs.log.$CURRENT_DATE"
    if [[ -f "$log_file" ]]; then
        tail -F "$log_file" &
        tail_pid=$!
        while [[ "$(TZ=UTC date +%Y-%m-%d)" == "$CURRENT_DATE" ]]; do
            sleep 300
        done
        kill $tail_pid
    else
        text_box "WARNING" "Log file $log_file not found. Retrying in 60 seconds..."
        sleep 300
    fi
    current_date=$(TZ=UTC date +%Y-%m-%d)
done
