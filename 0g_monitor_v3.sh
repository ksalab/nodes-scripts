#!/bin/bash

# Set the version variable
NAME="0g (ZeroGravity) node Block Scanner"
BIN_VER="1.0.0"
OG_PORT=47657

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "❌ Failed to load utility script!"
    exit 1
fi

# Default settings
BLOCK_THRESHOLD=10
SERVICE_NAME="0gchaind"

# List of external nodes
EXTERNAL_NODES=(
    "https://evmrpc-testnet.0g.ai"
    # Add other nodes as needed
)
CURRENT_NODE_INDEX=0

# Processing command line arguments
while getopts "t:b:u:" opt; do
    case $opt in
        t) BLOCK_THRESHOLD="$OPTARG";;
        b) SERVICE_NAME="$OPTARG";;
        ?) text_box "NOTE" "Usage: $0 [-t threshold] [-b binary_name]"
           exit 1;;
    esac
done

# Initialize variables
prev_block=""
prev_time=""
bps="N/A"
eta_display="N/A"

while true; do
    # Get the height of the local node
    local_height=$(curl -s localhost:${OG_PORT}657/status | jq -r .result.sync_info.latest_block_height)
    connectedPeers=$(curl -s localhost:${OG_PORT}657/status -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.node_info.other.num_peers // "N/A"')

    # Get the height of the current external node
    current_node="${EXTERNAL_NODES[$CURRENT_NODE_INDEX]}"
    response=$(curl -s -X POST "$current_node" -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}')
    if [ -z "$response" ]; then
        text_box "ERROR" "Failed to fetch data from $current_node. Retrying..."
        sleep 5
        continue
    fi

    hex_height=$(echo "$response" | jq -r '.result')
    # Проверка, что hex_height является валидным шестнадцатеричным числом
    if ! [[ "$hex_height" =~ ^0x[0-9A-Fa-f]+$ ]] || [ "$hex_height" = "0x" ]; then
        text_box "ERROR" "Invalid hex height from $current_node: '$hex_height'. Retrying..."
        echo "DEBUG: response=$response, hex_height=$hex_height" >> /tmp/node_scanner.log
        sleep 5
        continue
    fi
    # Преобразование hex_height в верхний регистр и удаление префикса 0x
    hex_value=$(echo "${hex_height#0x}" | tr 'a-f' 'A-F')
    # Проверка, что hex_value не пустое и содержит только валидные символы
    if [ -z "$hex_value" ] || ! [[ "$hex_value" =~ ^[0-9A-F]+$ ]]; then
        text_box "ERROR" "Invalid hex value after processing '$hex_height'. Retrying..."
        echo "DEBUG: hex_height=$hex_height, hex_value=$hex_value" >> /tmp/node_scanner.log
        sleep 5
        continue
    fi
    # Преобразование с использованием bc, используя printf для надежной передачи данных
    network_height=$(printf "ibase=16; %s\n" "$hex_value" | bc)
    # Проверка результата преобразования
    if [ -z "$network_height" ] || ! [[ "$network_height" =~ ^[0-9]+$ ]]; then
        text_box "ERROR" "Failed to convert hex height '$hex_height' to decimal. Retrying..."
        echo "DEBUG: hex_height=$hex_height, hex_value=$hex_value, network_height=$network_height" >> /tmp/node_scanner.log
        sleep 5
        continue
    fi

    # Data validity check
    if ! [[ "$local_height" =~ ^[0-9]+$ ]] || [ -z "$network_height" ] || ! [[ "$network_height" =~ ^[0-9]+$ ]]; then
        text_box "ERROR" "Invalid block height data from $current_node. Retrying..."
        sleep 5
        continue
    fi

    # Data validity check
    if ! [[ "$local_height" =~ ^[0-9]+$ ]] || [ -z "$network_height" ] || ! [[ "$network_height" =~ ^[0-9]+$ ]]; then
        text_box "ERROR" "Invalid block height data from $current_node. Retrying..."
        sleep 5
        continue
    fi

    # Calculate the difference in blocks
    blocks_diff=$((local_height - network_height))
    blocks_left=$((network_height - local_height))
    if [ "$blocks_left" -lt 0 ]; then
        blocks_left=0
    fi

    # Calculate blocks per second and ETA
    current_time=$(date +%s)
    bps="N/A"
    eta_display="N/A"
    if [[ "$prev_block" =~ ^[0-9]+$ && "$prev_time" =~ ^[0-9]+$ && "$local_height" -gt "$prev_block" ]]; then
        delta_block=$((local_height - prev_block))
        delta_time=$((current_time - prev_time))
        if (( delta_time > 0 )); then
            bps=$(echo "scale=2; $delta_block / $delta_time" | bc)
            if [[ "$bps" =~ ^[0-9]+(\.[0-9]+)?$ && $(echo "$bps > 0" | bc -l) -eq 1 ]]; then
                eta_sec=$(echo "$blocks_left / $bps" | bc)
                if [[ "$eta_sec" =~ ^[0-9]+$ && "$eta_sec" -ge 0 ]]; then
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
            else
                bps="N/A"
            fi
        fi
    fi
    prev_block=$local_height
    prev_time=$current_time

    # Output the information
    if [ "$blocks_diff" -gt 0 ]; then
        diff="(Ahead by: ${ORANGE}${blocks_diff}${RESET})"
    elif [ "$blocks_diff" -lt 0 ]; then
        diff="(Behind by: ${RED}${blocks_left}${RESET})"
    else
        diff="(${LIGHT_GREEN}In Sync${RESET})"
    fi

    printf "Local Block: ${GREEN}%-7s${RESET} | Network Block: ${YELLOW}%-7s${RESET} %-20s | Peers: ${PURPLE}%-3s${RESET} | Speed: ${LIGHT_BLUE}%-5s blocks/s${RESET} | ETA: ${LIGHT_PURPLE}%s${RESET}\n" \
        "$local_height" "$network_height" "$diff" "$connectedPeers" "$bps" "$eta_display"

    # Check if the external node is lagging behind the local node
    # if [ "$blocks_diff" -gt 0 ]; then
    #     echo -e "${ORANGE}Warning: External node $current_node is behind local node by $blocks_diff blocks!${RESET}"
    #     # Switching to the next node
    #     CURRENT_NODE_INDEX=$(( (CURRENT_NODE_INDEX + 1) % ${#EXTERNAL_NODES[@]} ))
    #     new_node="${EXTERNAL_NODES[$CURRENT_NODE_INDEX]}"
    #     echo -e "${GRAY}Switching to next external node: $new_node${RESET}"
    #     sleep 5
    #     continue
    # fi

    # Check local node backlog and restart if necessary
    # if [ "$blocks_left" -gt "$BLOCK_THRESHOLD" ]; then
    #     echo -e "${GRAY}Node is behind by $blocks_left blocks (threshold: $BLOCK_THRESHOLD). Restarting...${RESET}"

        # Service stop
    #     systemctl stop $SERVICE_NAME

        # Updating the list of peers
    #     PEERS=$(curl -sS https://og-testnet-rpc.itrocket.net/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)
    #     sed -i "s|^persistent_peers *=.*|persistent_peers = \"${PEERS}\"|" "$CONFIG_DIR/config.toml"

        # Service startup
    #     systemctl start $SERVICE_NAME

    #     echo -e "${LIGHT_GREEN}Node restarted with updated peers${RESET}"
    #     sleep 30  # Give the node time to start up
    # fi

    sleep 5
done
