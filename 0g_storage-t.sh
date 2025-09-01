#!/bin/bash

# Set the version variable
NAME="0g (ZeroGravity) Storage Node"
BIN_VER="1.0.0"

0G_HOME=".ogchain"
0G_NODE_PORT=8545
CONFIG_URL="https://server-7.itrocket.net/testnet/og/storage/config-testnet-turbo.toml"
SERVICE_NAME="zgs"
SNAPSHOTS_DIR="https://server-7.itrocket.net/testnet/og/storage/"
SNAPSHOT_MASK_NAME1="og_storage_.*_snap\.tar\.lz4"
SNAPSHOT_MASK_NAME2=""
# Combine masks into a single pattern
# example: SNAPSHOTS_PATTERN="$SNAPSHOT_MASK_NAME1|$SNAPSHOT_MASK_NAME2"
SNAPSHOTS_PATTERN="$SNAPSHOT_MASK_NAME1"

NETWORK_DIR="network"
NETWORK_LISTEN_ADDRESS="0.0.0.0"
NETWORK_ENR_TCP_PORT=1234
NETWORK_ENR_UDP_PORT=$NETWORK_ENR_TCP_PORT
NETWORK_LIBP2P_PORT=$NETWORK_ENR_TCP_PORT
NETWORK_DISCOVERY_PORT=$NETWORK_ENR_TCP_PORT
NETWORK_TARGET_PEERS=100
RPC_LISTEN_ADDRESS="0.0.0.0:5678"
DB_DIR="db"
LOG_CONFIG_FILE="log_config"
LOG_DIRECTORY="log"
NETWORK_BOOT_NODES="/ip4/47.251.117.133/udp/1234/p2p/16Uiu2HAmTVDGNhkHD98zDnJxQWu3i1FL1aFYeh9wiQTNu4pDCgps","/ip4/47.76.61.226/udp/1234/p2p/16Uiu2HAm2k6ua2mGgvZ8rTMV8GhpW71aVzkQWy7D37TTDuLCpgmX","/ip4/47.251.79.83/udp/1234/p2p/16Uiu2HAkvJYQABP1MdvfWfUZUzGLx1sBSDZ2AT92EFKcMCCPVawV","/ip4/47.238.87.44/udp/1234/p2p/16Uiu2HAmFGsLoajQdEds6tJqsLX7Dg8bYd2HWR4SbpJUut4QXqCj","/ip4/47.251.78.104/udp/1234/p2p/16Uiu2HAmSe9UWdHrqkn2mKh99b9DwYZZcea6krfidtU3e5tiHiwN","/ip4/47.76.30.235/udp/1234/p2p/16Uiu2HAm5tCqwGtXJemZqBhJ9JoQxdDgkWYavfCziaqaAYkGDSfU","/ip4/54.219.26.22/udp/1234/p2p/16Uiu2HAmTVDGNhkHD98zDnJxQWu3i1FL1aFYeh9wiQTNu4pDCgps","/ip4/52.52.127.117/udp/1234/p2p/16Uiu2HAkzRjxK2gorngB1Xq84qDrT4hSVznYDHj6BkbaE4SGx9oS","/ip4/18.162.65.205/udp/1234/p2p/16Uiu2HAm2k6ua2mGgvZ8rTMV8GhpW71aVzkQWy7D37TTDuLCpgmX"
NETWORK_PRIVATE=false
NETWORK_DISABLE_DISCOVERY=false
DISCV5_REQUEST_TIMEOUT_SECS=10
DISCV5_QUERY_PEER_TIMEOUT_SECS=5
DISCV5_REQUEST_RETRIES=3
LOG_CONTRACT_ADDRESS="0xbD75117F80b4E22698D0Cd7612d92BDb8eaff628"
MINE_CONTRACT="0x3A0d1d67497Ad770d6f72e7f4B8F0BAbaa2A649C"
MARKET_CONTRACT="0x53191725d260221bBa307D8EeD6e2Be8DD265e19"
REWARD_CONTRACT="0xd3D4D91125D76112AE256327410Dd0414Ee08Cb4"
ZGS_LOG_SYNC_BLOCK="595059"
BLOCKCHAIN_RPC_ENDPOINT="https://evmrpc-testnet.0g.ai"
AUTO_SYNC_ENABLED=true
FIND_PEER_TIMEOUT="30s"

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER

# Define colors
if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "❌ Failed to load utility script!"
    exit 1
fi

#

# Processing a command line parameter
parse_arguments() {
    case "$1" in
        user) BASE_PATH="/home/ritual" ;;
        root | "") BASE_PATH="/root" ;;
        *) text_box "ERROR" "Invalid parameter. Use 'user' or 'root'."; exit 1 ;;
    esac
    [[ "$2" == "restart" ]] && ENABLE_RESTART=true
}

parse_arguments "$@"

# Get public IP
ENR_ADDRESS=$(wget -qO- eth0.me)
if [ -z "$ENR_ADDRESS" ]; then
    text_box "ERROR" "Failed to determine the public IP. Verify that the eth0.me service is available." >&2
    exit 1
fi
text_box "INFO" "Current IP: ${ENR_ADDRESS}"

BLOCKCHAIN_RPC_ENDPOINT="http://${ENR_ADDRESS}:8545"

#

# Function to install node
install_node() {
    cd $HOME
    text_box "TITLE" "Installing node ${NAME}..."

    # Check Go versions
    check_go_versions

    # Check Rust versions
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

    text_box "INFO" "Download and build binaries..."
    cd $HOME || { text_box "ERROR" "Failed to change directory to $HOME"; exit 1; }
    rm -rf 0g-storage-node
    git clone https://github.com/0glabs/0g-storage-node.git || { text_box "ERROR" "Failed to clone repository"; exit 1; }
    cd 0g-storage-node || { text_box "ERROR" "Failed to change directory to 0g-da-node"; exit 1; }
    git checkout v${BIN_VER} || { text_box "ERROR" "Failed to checkout tag v${BIN_VER}"; exit 1; }
    git submodule update --init

    text_box "INFO" "Building a binary file..."
    if ! cargo build --release; then
        text_box "ERROR" "Error while building a binary file!" >&2
        exit 1
    fi

    # Create and use your RPC. Follow these steps on the server running your validator node:
    text_box "INFO" "Update json-rpc settings..."
    sed -i '/\[json-rpc\]/,/^\[/{|^address = "| s|\(address = "\)[^:]*\(:[0-9]\+\)"|\10.0.0.0\2"|; t; }' $HOME/$0G_HOME/config/app.toml
    sed -i '/\[json-rpc\]/,/^\[/{|^api = "| s|\(api = "\)[^"]*"|\1eth,txpool,personal,net,debug,web3"|; t; }' $HOME/$0G_HOME/config/app.toml

    # Request 0G Node json_rpc port
    text_box "INFO" "Request 0G Node json_rpc port..."
    while [ -z "$0G_NODE_PORT_USER" ]; do
        text_box "INFO" "Enter 0G Node json_rpc port (default ${0G_NODE_PORT}): "
        read -r 0G_NODE_PORT_USER
        # If the user has not entered anything, set the default value
        if [ -z "$0G_NODE_PORT_USER" ]; then
            0G_NODE_PORT_USER=8545
        fi
    done

    # Request ETH and BLS private keys
    text_box "INFO" "Request ETH private keys..."
    while [ -z "$ETH_PRIVATE_KEY" ]; do
        echo "Enter ETH PRIVATE_KEY: "
        read -r ETH_PRIVATE_KEY
    done

    # Assign a value to the variable 0G_NODE_PORT
    0G_NODE_PORT=$0G_NODE_PORT_USER
    BLOCKCHAIN_RPC_ENDPOINT="http://${ENR_ADDRESS}:${0G_NODE_PORT}"

    # Open port 8545
    sudo ufw allow ${0G_NODE_PORT}/tcp || { text_box "ERROR" "Failed to open port ${0G_NODE_PORT}"; exit 1; }
    sudo ufw reload || { text_box "ERROR" "Failed to reload UFW"; exit 1; }

    # Download config example
    text_box "INFO" "Download config file..."
    wget -O $HOME/0g-storage-node/run/config-testnet-turbo.toml ${CONFIG_URL}

    text_box "INFO" "Set Configuration..."
    sed -i -e "s|^network_dir *=.*|network_dir = \"${NETWORK_DIR}\"|;
    s|^network_listen_address *=.*|network_listen_address = \"${NETWORK_LISTEN_ADDRESS}\"|;
    s|^network_enr_address *=.*|network_enr_address = \"${ENR_ADDRESS}\"|;
    s|^network_enr_tcp_port *=.*|network_enr_tcp_port = $NETWORK_ENR_TCP_PORT|;
    s|^network_enr_udp_port *=.*|network_enr_udp_port = $NETWORK_ENR_UDP_PORT|;
    s|^network_libp2p_port *=.*|network_libp2p_port = $NETWORK_LIBP2P_PORT|;
    s|^network_discovery_port *=.*|network_discovery_port = $NETWORK_DISCOVERY_PORT|;
    s|^network_target_peers *=.*|network_target_peers = $NETWORK_TARGET_PEERS|;
    s|^rpc_listen_address *=.*|rpc_listen_address = \"$RPC_LISTEN_ADDRESS\"|;
    s|^db_dir *=.*|db_dir = \"$DB_DIR\"|;
    s|^log_config_file *=.*|log_config_file = \"$LOG_CONFIG_FILE\"|;
    s|^log_directory *=.*|log_directory = \"$LOG_DIRECTORY\"|;
    s|^network_boot_nodes *=.*|network_boot_nodes = \[$NETWORK_BOOT_NODES]|;
    s|^network_private *=.*|network_private = $NETWORK_PRIVATE|;
    s|^network_disable_discovery *=.*|network_disable_discovery = $NETWORK_DISABLE_DISCOVERY|;
    s|^discv5_request_timeout_secs *=.*|discv5_request_timeout_secs = $DISCV5_REQUEST_TIMEOUT_SECS|;
    s|^discv5_query_peer_timeout_secs *=.*|discv5_query_peer_timeout_secs = $DISCV5_QUERY_PEER_TIMEOUT_SECS|;
    s|^discv5_request_retries *=.*|discv5_request_retries = $DISCV5_REQUEST_RETRIES|;
    s|^log_contract_address *=.*|log_contract_address = \"$LOG_CONTRACT_ADDRESS\"|;
    s|^listen_address *=.*|listen_address = \"$RPC_LISTEN_ADDRESS\"|;
    s|^mine_contract_address *=.*|mine_contract_address = \"$MINE_CONTRACT\"|;
    s|^miner_key *=.*|miner_key = \"$ETH_PRIVATE_KEY\"
    s|^reward_contract_address *=.*|reward_contract_address = \"$REWARD_CONTRACT\"|;
    s|^log_sync_start_block_number *=.*|log_sync_start_block_number = \"$ZGS_LOG_SYNC_BLOCK\"|;
    s|^blockchain_rpc_endpoint *=.*|blockchain_rpc_endpoint = \"$BLOCKCHAIN_RPC_ENDPOINT\"|;
    s|^# \[sync\]|\[sync\]|;
    s|^auto_sync_enabled *=.*|auto_sync_enabled = $AUTO_SYNC_ENABLED|;
    s|^# find_peer_timeout = .*|find_peer_timeout = \"$FIND_PEER_TIMEOUT\"|;
    " "$HOME/0g-storage-node/run/config-testnet-turbo.toml"

    # Create Service file
    text_box "INFO" "Create ${SERVICE_NAME}.service file..."
    sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=ZGS Node
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/0g-storage-node/run
ExecStart=$HOME/0g-storage-node/target/release/zgs_node --config $HOME/0g-storage-node/run/config-testnet-turbo.toml
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        text_box "ERROR" "Error when creating ${SERVICE_NAME} service file!" >&2
        exit 1
    fi

    # Get information about the latest snapshot
    if ! get_latest_snapshot_info "$SNAPSHOTS_DIR" "$SNAPSHOTS_PATTERN"; then
        return 1
    fi

    # Prompt user to install the snapshot
    while true; do
        read -p "Do you want to install this snapshot? (y/n): " choice
        case "$choice" in
            y|Y )
                # Install the snapshot
                install_snapshot "$SNAPSHOT_URL" "${HOME}/0g-storage-node/run/db"
                break
                ;;
            n|N )
                # Continue without installing the snapshot
                text_box "INFO" "Continuing without installing the snapshot."
                break
                ;;
            * )
                # Invalid input
                text_box "ERROR" "Invalid choice. Please enter 'y' or 'n'."
                ;;
        esac
    done

    # Enable and start service:
    text_box "INFO" "Start ${SERVICE_NAME}.service file..."
    sudo systemctl daemon-reload
    sudo systemctl enable ${SERVICE_NAME}
    sudo systemctl start ${SERVICE_NAME}

    if ! sudo systemctl is-active --quiet ${SERVICE_NAME}; then
        text_box "WARNING" "The ${SERVICE_NAME} service is not running. Check the logs with 'journalctl -u ${SERVICE_NAME} -o cat'." >&2
        exit 1
    fi

    text_box "DONE" "${NAME} installed successfully."
    return 0
}

# Function to restart node
restart_node() {
    text_box "TITLE" "Restart node ${NAME}..."
    local target_service=""

    # Check if the zgs or zgstorage service exists
    if systemctl list-units --type=service --all | grep -q "^zgs.service"; then
        target_service="zgs"
    elif systemctl list-units --type=service --all | grep -q "^zgstorage.service"; then
        target_service="zgstorage"
    else
        text_box "WARNING" "Neither zgs nor zgstorage services exist." >&2
        exit 1
    fi

    sudo systemctl restart ${target_service}

    if ! sudo systemctl is-active --quiet ${target_service}; then
        text_box "WARNING" "The ${target_service} service is not running." >&2
        exit 1
    fi

    text_box "DONE" "${NAME} restarted successfully."
    return 0
}

# Function to stop node
stop_node() {
    text_box "TITLE" "Stop ${NAME}..."
    local target_service="${SERVICE_NAME}"

    # Check to see if zgs is active
    if ! sudo systemctl is-active --quiet "${SERVICE_NAME}"; then
        # If zgs is not active, check zgstorage
        if sudo systemctl is-active --quiet "zgstorage"; then
            target_service="zgstorage"
        else
            text_box "WARNING" "Neither ${SERVICE_NAME} nor zgstorage services are running." >&2
            #exit 1
        fi
    fi

    sudo systemctl stop "${target_service}"

    if ! sudo systemctl is-active --quiet "${target_service}"; then
        text_box "WARNING" "The ${target_service} service is not running." >&2
        #exit 1
    fi

    text_box "DONE" "${NAME} stopped successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    text_box "TITLE" "Checking node logs for ${NAME}..."
    tail -f ~/0g-storage-node/run/log/zgs.log.$(TZ=UTC date +%Y-%m-%d)
    return 0
}

# Function to update node
update_node() {
    text_box "TITLE" "Updating node ${NAME}..."
    stop_node

    text_box "INFO" "Backup config file..."
    mv $HOME/0g-storage-node/run/config-testnet-turbo.toml $HOME/config-testnet-turbo_backup.toml

    text_box "INFO" "Check new version..."
    cd $HOME/0g-storage-node
    git fetch --all --tags
    git checkout v${BIN_VER}
    git submodule update --init

    text_box "INFO" "Building a binary file..."
    if ! cargo build --release; then
        text_box "ERROR" "Error while building a binary file!" >&2
        exit 1
    fi

    text_box "INFO" "Move back config file..."
    mv $HOME/config-testnet-turbo_backup.toml $HOME/0g-storage-node/run/config-testnet-turbo.toml

    text_box "INFO" "Start ${SERVICE_NAME}.service file..."
    sudo systemctl restart ${SERVICE_NAME}

    if ! sudo systemctl is-active --quiet ${SERVICE_NAME}; then
        text_box "WARNING" "The ${SERVICE_NAME} service is not running" >&2
        exit 1
    fi

    text_box "DONE" "${NAME} updated successfully."
    return 0
}

update_network() {
    stop_node
    text_box "INFO" "Update network..."

    rm -rf $BASE_PATH/0g-storage-node/run/db
    rm -rf $BASE_PATH/0g-storage-node/run/log

    text_box "INFO" "Set Configuration..."
    sed -i -e "s|^network_boot_nodes *=.*|network_boot_nodes = \[$NETWORK_BOOT_NODES]|;
    s|^log_contract_address *=.*|log_contract_address = \"$LOG_CONTRACT_ADDRESS\"|;
    s|^mine_contract_address *=.*|mine_contract_address = \"$MINE_CONTRACT\"|;
    s|^market_contract_address *=.*|mine_contract_address = \"$MINE_CONTRACT\"|;
    s|^reward_contract_address *=.*|reward_contract_address = \"$REWARD_CONTRACT\"|;
    " "$BASE_PATH/0g-storage-node/run/config-testnet-turbo.toml"

}

# Function to delete node
delete_node() {
    text_box "INFO" "Make sure you back up your node data before continuing.\n"
    text_box "WARNING" "Yeah, I backed it up: (y/n)"
    read -r backup
    if [[ "$backup" =~ ^[Yy]$ ]]; then
        text_box "INFO" "It's backed up. Continued..."
    else
        text_box "ERROR" "The backup has not been saved. Back to the menu......"
        return 1
    fi

    text_box "INFO" "Stop node ${NAME}..."
    sudo systemctl stop ${SERVICE_NAME}
    sudo systemctl disable ${SERVICE_NAME}
    sudo rm /etc/systemd/system/${SERVICE_NAME}.service
    text_box "INFO" "Delete node folder..."
    rm -rf $HOME/0g-storage-node

    text_box "DONE" "${NAME} deleted successfully."
    return 0
}

#

# Menu

while true
do
    PS3="Select an action for ${NAME}: "
    options=(
        "Install node"
        "Restart node"
        "Stop node"
        "Check node logs"
        "Update node"
        "Update network"
        "Delete node"
        "Exit"
    )

    select opt in "${options[@]}"
    do
        case $opt in
            "Install node")
                install_node
                break
                ;;
            "Restart node")
                restart_node
                break
                ;;
            "Stop node")
                stop_node
                break
                ;;
            "Check node logs")
                check_node_logs
                break
                ;;
            "Update node")
                update_node
                break
                ;;
            "Update network")
                update_network
                break
                ;;
            "Delete node")
                delete_node
                break
                ;;
            "Exit")
                exit 0
                ;;
            *) 
                error "Invalid option $REPLY"
                ;;
        esac
    done

done