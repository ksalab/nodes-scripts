#!/bin/bash

# Set the version variable
NAME="0g (ZeroGravity) node Block Scanner"
BIN_VER="1.0.0"

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
USER_MODE="user"  # или "root"

# List of external nodes
EXTERNAL_NODES=(
    "https://og-testnet-rpc.itrocket.net"
    "http://95.216.54.249:26657"
    "http://65.109.78.118:26657"
    # Add other nodes as needed
)
CURRENT_NODE_INDEX=0

# Processing command line arguments
while getopts "t:b:u:" opt; do
    case $opt in
        t) BLOCK_THRESHOLD="$OPTARG";;
        b) SERVICE_NAME="$OPTARG";;
        u) USER_MODE="$OPTARG";;
        ?) text_box "NOTE" "Usage: $0 [-t threshold] [-b binary_name] [-u user_mode(root/user)]"
           exit 1;;
    esac
done

# Define the path to the configuration depending on the user mode
if [ "$USER_MODE" = "user" ]; then
    CONFIG_DIR="/home/ritual/.0gchain/config"
else
    CONFIG_DIR="$HOME/.0gchain/config"
fi

# Receive RPC port
rpc_port=$(grep -m 1 -oP '^laddr = "\K[^"]+' "$CONFIG_DIR/config.toml" | cut -d ':' -f 3)

while true; do
    # Get the height of the local node
    local_height=$(curl -s localhost:$rpc_port/status | jq -r '.result.sync_info.latest_block_height')

    # Get the height of the current external node
    current_node="${EXTERNAL_NODES[$CURRENT_NODE_INDEX]}"
    network_height=$(curl -s "$current_node/status" | jq -r '.result.sync_info.latest_block_height')

    # Data validity check
    if ! [[ "$local_height" =~ ^[0-9]+$ ]] || ! [[ "$network_height" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid block height data from $current_node. Retrying...${RESET}"
        sleep 5
        continue
    fi

    # Calculate the difference in blocks (can be positive or negative)
    blocks_diff=$((local_height - network_height))

    # Define the lag for the restart logic (only if the local node is lagging)
    blocks_left=$((network_height - local_height))
    if [ "$blocks_left" -lt 0 ]; then
        blocks_left=0
    fi

    # Output the information taking into account the direction of the difference
    if [ "$blocks_diff" -gt 0 ]; then
        echo -e "Node Height: ${PURPLE}${local_height}${RESET} | Network Height ($current_node): ${LIGHT_PURPLE}${network_height}${RESET} | Local Ahead by: ${ORANGE}${blocks_diff}${RESET}"
    elif [ "$blocks_diff" -lt 0 ]; then
        echo -e "Node Height: ${PURPLE}${local_height}${RESET} | Network Height ($current_node): ${LIGHT_PURPLE}${network_height}${RESET} | Local Behind by: ${RED}${blocks_left}${RESET}"
    else
        echo -e "Node Height: ${PURPLE}${local_height}${RESET} | Network Height ($current_node): ${LIGHT_PURPLE}${network_height}${RESET} | ${LIGHT_GREEN}In Sync${RESET}"
    fi

    # Check if the external node is lagging behind the local node
    if [ "$blocks_diff" -gt 0 ]; then
        echo -e "${ORANGE}Warning: External node $current_node is behind local node by $blocks_diff blocks!${RESET}"
        # Switching to the next node
        CURRENT_NODE_INDEX=$(( (CURRENT_NODE_INDEX + 1) % ${#EXTERNAL_NODES[@]} ))
        new_node="${EXTERNAL_NODES[$CURRENT_NODE_INDEX]}"
        echo -e "${GRAY}Switching to next external node: $new_node${RESET}"
        sleep 5
        continue
    fi

    # Check local node backlog and restart if necessary
    if [ "$blocks_left" -gt "$BLOCK_THRESHOLD" ]; then
        echo -e "${GRAY}Node is behind by $blocks_left blocks (threshold: $BLOCK_THRESHOLD). Restarting...${RESET}"

        # Service stop
        systemctl stop $SERVICE_NAME

        # Updating the list of peers
        PEERS=$(curl -sS https://og-testnet-rpc.itrocket.net/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)
        sed -i "s|^persistent_peers *=.*|persistent_peers = \"${PEERS}\"|" "$CONFIG_DIR/config.toml"

        # Service startup
        systemctl start $SERVICE_NAME

        echo -e "${LIGHT_GREEN}Node restarted with updated peers${RESET}"
        sleep 30  # Give the node time to start up
    fi

    sleep 5
done
