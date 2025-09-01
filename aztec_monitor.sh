#!/bin/bash

# Set the version variable
NAME="Aztec Sync Monitor"
BIN_VER="1.0.0"

REMOTE_RPC="https://aztec-rpc.cerberusnode.com"
LOCAL_RPC="http://localhost:8084"
EXTERNAL_RPC="http://$(hostname -I | awk '{print $1}'):8084"

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "❌ Failed to load utility script!"
    exit 1
fi

#

# Check if 'ext' parameter is provided
if [[ "$1" == "ext" ]]; then
    LOCAL_RPC=$EXTERNAL_RPC
    text_box "INFO" "External mode enabled. LOCAL_RPC set to $LOCAL_RPC"
fi

while true; do
    LOCAL=$(curl -s -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":1}' $LOCAL_RPC | jq -r ".result.proven.number")

    REMOTE=$(curl -s -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":1}' $REMOTE_RPC | jq -r ".result.proven.number")

    if [ "$LOCAL" = "$REMOTE" ]; then
        STATUS="✅ Your node is fully synced!"
    else
        STATUS="⏳ Still syncing... ($LOCAL / $REMOTE)"
    fi

    printf "Local Block: ${GREEN}%-7s${RESET} | Network Block: ${YELLOW}%-7s${RESET} | %s \n" \
        "$LOCAL" "$REMOTE" "$STATUS"
    sleep 30
done