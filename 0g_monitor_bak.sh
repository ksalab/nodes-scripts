#!/bin/bash

# Default settings
BLOCK_THRESHOLD=10
SERVICE_NAME="0gchaind"
USER_MODE="user"  # или "root"

# Processing command line arguments
while getopts "t:b:u:" opt; do
    case $opt in
        t) BLOCK_THRESHOLD="$OPTARG";;
        b) SERVICE_NAME="$OPTARG";;
        u) USER_MODE="$OPTARG";;
        ?) echo "Usage: $0 [-t threshold] [-b binary_name] [-u user_mode(root/user)]"
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
    local_height=$(curl -s localhost:$rpc_port/status | jq -r '.result.sync_info.latest_block_height')
    network_height=$(curl -s http://65.109.78.118:26657/status | jq -r '.result.sync_info.latest_block_height')

    if ! [[ "$local_height" =~ ^[0-9]+$ ]] || ! [[ "$network_height" =~ ^[0-9]+$ ]]; then
        echo -e "\033[1;31mError: Invalid block height data. Retrying...\033[0m"
        sleep 5
        continue
    fi

    blocks_left=$((network_height - local_height))
    if [ "$blocks_left" -lt 0 ]; then
        blocks_left=0
    fi

    echo -e "\033[1;33mNode Height:\033[1;34m $local_height\033[0m \033[1;33m| Network Height:\033[1;36m $network_height\033[0m \033[1;33m| Blocks Left:\033[1;31m $blocks_left\033[0m"

    # Check block height difference and restart if necessary
    if [ "$blocks_left" -gt "$BLOCK_THRESHOLD" ]; then
        echo -e "\033[1;31mNode is behind by $blocks_left blocks (threshold: $BLOCK_THRESHOLD). Restarting...\033[0m"
        
        # Stopping the service
        systemctl stop $SERVICE_NAME

        # Updating the list of peers
        PEERS=$(curl -sS https://og-testnet-rpc.itrocket.net/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)
        sed -i "s|^persistent_peers *=.*|persistent_peers = \"${PEERS}\"|" "$CONFIG_DIR/config.toml"

        # Start the service
        systemctl start $SERVICE_NAME

        echo -e "\033[1;32mNode restarted with updated peers\033[0m"
        sleep 30  # Give the node time to start
    fi

    sleep 5
done