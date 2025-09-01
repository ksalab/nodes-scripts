#!/bin/bash

# Set the version variable
NAME="0g (ZeroGravity) storage Block Scanner"
BIN_VER="1.0.0"

# Initialize variables
ENABLE_RESTART=false
# Extract RPC URL from config-testnet-turbo.toml
FALLBACK_RPCS=("https://evmrpc-testnet.0g.ai")
FALLBACK_INDEX=0

# Export the version variable to make it available in the sourced script
VER="${NAME} ${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "❌ Failed to load utility script!"
    exit 1
fi

# Check for required utilities
check_dependencies() {
    for util in awk jq curl bc; do
        command -v "$util" &>/dev/null || { text_box "ERROR" "The '$util' utility is required but not installed."; exit 1; }
    done
}

# Processing a command line parameter
parse_arguments() {
    case "$1" in
        user) BASE_PATH="/home/ritual" ;;
        root | "") BASE_PATH="/root" ;;
        *) text_box "ERROR" "Invalid parameter. Use 'user' or 'root'."; exit 1 ;;
    esac
    [[ "$2" == "restart" ]] && ENABLE_RESTART=true
}

extract_config() {
    CONFIG_FILE="${BASE_PATH}/0g-storage-node/run/config-testnet-turbo.toml"
    [[ ! -d "${BASE_PATH}/0g-storage-node" ]] && { text_box "ERROR" "Directory ${BASE_PATH}/0g-storage-node does not exist."; exit 1; }
    [[ ! -f "$CONFIG_FILE" ]] && { text_box "ERROR" "Config file $CONFIG_FILE not found."; exit 1; }
    CONFIG_RPC=$(awk -F'"' '/blockchain_rpc_endpoint/ {print $2}' "$CONFIG_FILE")
    [[ -z "$CONFIG_RPC" ]] && { text_box "ERROR" "Could not extract blockchain_rpc_endpoint from $CONFIG_FILE."; exit 1; }
    ACTIVE_RPC="$CONFIG_RPC"
}

get_node_version() {
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null)
    if [[ -n "$VERSION" ]]; then
        text_box "INFO" "Node Version: ${VERSION}"
    else
        text_box "INFO" "Node Version: Not a git repository or no tags found."
    fi
}

query_local_node() {
    LOCAL_RESPONSE=$(curl -s -X POST http://localhost:5678 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}')
    if ! echo "$LOCAL_RESPONSE" | jq . >/dev/null 2>&1; then
        text_box "ERROR" "Invalid JSON response from local node."
        return 1
    fi
    logSyncHeight=$(echo "$LOCAL_RESPONSE" | jq '.result.logSyncHeight' 2>/dev/null)
    connectedPeers=$(echo "$LOCAL_RESPONSE" | jq '.result.connectedPeers' 2>/dev/null)
    return 0
}

query_network() {
    NETWORK_RESPONSE=$(curl -s -m 3 -X POST "$ACTIVE_RPC" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}')
    latestBlockHex=$(echo "$NETWORK_RESPONSE" | jq -r '.result' 2>/dev/null)
    if [[ -z "$latestBlockHex" || "$latestBlockHex" == "null" ]]; then
        text_box "ERROR" "Failed to retrieve the latest block from external RPC."
        switch_to_next_fallback_rpc
        return 1
    fi
    if [[ ! "$latestBlockHex" =~ ^0x[0-9a-fA-F]+$ ]]; then
        text_box "ERROR" "Invalid block number format: $latestBlockHex"
        switch_to_next_fallback_rpc
        return 1
    fi
    latestBlock=$((16#${latestBlockHex:2}))
    return 0
}

# Function to switch to the next fallback RPC
switch_to_next_fallback_rpc() {
    if (( ${#FALLBACK_RPCS[@]} <= 1 )); then
        text_box "ERROR" "Only one RPC available in FALLBACK_RPCS. Cannot switch."
        return 0
    fi
    if (( FALLBACK_INDEX < ${#FALLBACK_RPCS[@]} - 1 )); then
        ((FALLBACK_INDEX++))
    else
        FALLBACK_INDEX=0
    fi
    ACTIVE_RPC="${FALLBACK_RPCS[$FALLBACK_INDEX]}"
    text_box "INFO" "Switching to fallback RPC: ${BLUE}${ACTIVE_RPC}${RESET}"
    return 0
}

setup_traps() {
    trap "echo -e '\nExiting...'; exit 0" SIGINT SIGTERM
}

restart_service_if_needed() {
    if (( block_diff < 10 )) || [[ "$ENABLE_RESTART" != true ]]; then
        return 0
    fi
    SERVICE_NAME=""
    text_box "WARNING" "Local node is behind by ${block_diff} blocks. Restarting service..."
    if systemctl list-unit-files | grep -E "zgs.service" >/dev/null 2>&1; then
        SERVICE_NAME="zgs"
    elif systemctl list-unit-files | grep -E "zgstorage.service" >/dev/null 2>&1; then
        SERVICE_NAME="zgstorage"
    else
        text_box "ERROR" "Neither zgs nor zgstorage service found."
        exit 1
    fi
    systemctl restart "$SERVICE_NAME"
    sleep 10
    return 1
}

display_status() {
    if (( block_diff <= 5 )); then
        diff_color="${GREEN}"
    elif (( block_diff <= 20 )); then
        diff_color="${YELLOW}"
    else
        diff_color="${RED}"
    fi

    printf "Local Block: ${GREEN}%-7s${RESET} | Network Block: ${YELLOW}%-7s${RESET} (Behind ${diff_color}%-5s${RESET}) | Peers: ${PURPLE}%-3s${RESET} | Speed: ${LIGHT_BLUE}%-5s blocks/s${RESET} | ETA: ${LIGHT_PURPLE}%s${RESET}\n" \
        "$logSyncHeight" "$latestBlock" "$block_diff" "$connectedPeers" "$bps" "$eta_display"
}

calculate_metrics() {
    block_diff=$((latestBlock - logSyncHeight))
    current_time=$(date +%s)
    bps="N/A"
    eta_display="N/A"
    if [[ "$prev_block" =~ ^[0-9]+$ && "$prev_time" =~ ^[0-9]+$ && "$logSyncHeight" -gt "$prev_block" ]]; then
        delta_block=$((logSyncHeight - prev_block))
        delta_time=$((current_time - prev_time))
        if (( delta_time > 0 )); then
            bps=$(echo "scale=2; $delta_block / $delta_time" | bc)
            if (( $(echo "$bps > 0" | bc -l) )); then
                eta_sec=$(echo "$block_diff / $bps" | bc)
                if (( eta_sec < 60 )); then
                    eta_display="$eta_sec sec"
                elif (( eta_sec < 3600 )); then
                    eta_display="$((eta_sec / 60)) min"
                elif (( eta_sec < 86400 )); then
                    eta_display="$((eta_sec / 3600)) hr"
                else
                    eta_display="$((eta_sec / 86400)) day(s)"
                fi
            fi
        fi
    fi
    prev_block=$logSyncHeight
    prev_time=$current_time
}

main_loop() {
    while true; do
        query_local_node || { sleep 5; continue; }
        query_network || { sleep 5; continue; }
        calculate_metrics
        display_status
        restart_service_if_needed && continue
        sleep 10
    done
}

#

check_dependencies
parse_arguments "$@"
extract_config
cd "${BASE_PATH}/0g-storage-node" || exit 1
get_node_version
text_box "INFO" "Your RPC in config-testnet-turbo.toml: ${CONFIG_RPC}"
setup_traps
main_loop

# end of script
