#!/bin/bash

# Set the version variable
NAME=""
BIN_VER=""

# ------------------------------------------------------------------------
# Set blockchain variable
# ------------------------------------------------------------------------
REQUIRED_GO=true
REQUIRED_COSMOVISOR=true
REQUIRED_RUST=false

MONIKER=""
KEYRING_BACKEND="file"
PORT="36"
PRUNING="custom"
PRUNING_KEEP_RECENT=100
PRUNING_KEEP_EVERY=0
PRUNING_INTERVAL=19
GAS="auto"
GAS_ADJUSTMENT=1.6
MINIMUM_GAS_PRICES=0.00252
TOKEN="AOGI"
TOKEN_M="ua0gi"
INDEXER="kv"
WALLET_NAME="wallet"
BIN_VERSION="0.5.0"
BIN_NAME="0gchaind"
MAIN_FOLDER="0gchain"
HOME_FOLDER=".0gchain"
CHAIN_ID="zgtendermint_16600-2"
LINK_BIN="https://github.com/0glabs/0g-chain/releases/download/v${BIN_VERSION}/0gchaind-linux-v${BIN_VERSION}"
SEEDS="8f21742ea5487da6e0697ba7d7b36961d3599567@og-testnet-seed.itrocket.net:47656"
PEERS=$(curl -sS https://lightnode-rpc-0g.grandvalleys.com/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)

SNAP_RPC="https://og-testnet-rpc.itrocket.net:443"
SNAPSHOTS_DIR="https://server-5.itrocket.net/testnet/og/"
SNAPSHOT_MASK_NAME1="og_.*_snap\.tar\.lz4"
SNAPSHOT_MASK_NAME2="og-snap\.tar\.lz4"
# Combine masks into a single pattern
SNAPSHOTS_PATTERN="$SNAPSHOT_MASK_NAME1|$SNAPSHOT_MASK_NAME2"

LINK_ADDRBOOK="${SNAPSHOTS_DIR}addrbook.json"
LINK_GENESIS="${SNAPSHOTS_DIR}genesis.json"

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "Failed to load utility script!"
    exit 1
fi

#

# Parse command-line arguments
RUN_OPTION=""

for arg in "$@"; do
    case "$arg" in
        run=*) RUN_OPTION="${arg#run=}" ;;
    esac
done

# Function to create service file
create_service_file() {
    title "Create service file..."

    # Create the service file
    sudo tee /etc/systemd/system/${BIN_NAME}.service > /dev/null <<EOF
[Unit]
Description=${MAIN_FOLDER} node
After=network-online.target

[Service]
User=${USER}
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/${HOME_FOLDER}"
Environment="DAEMON_NAME=${BIN_NAME}"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$HOME/${HOME_FOLDER}/cosmovisor/current/bin"

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        error "Error when creating service file!"
        exit 1
    fi

    info "Service file created successfully."
}

# Function to install node
install_node() {
    cd $HOME
    title "Installing node ${NAME}..."



    info "${NAME} installed successfully."
    return 0
}

# Function to restart node
restart_node() {
    title "Restart node ${NAME}..."



    info "${NAME} restarted successfully."
    return 0
}

# Function to stop node
stop_node() {
    title "Stop ${NAME}..."



    info "${NAME} stopped successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    title "Checking node logs for ${NAME}..."


    return 0
}

# Function to update node
update_node() {
    title "Updating node ${NAME}..."



    info "${NAME} updated successfully."
    return 0
}

# Function to delete node
delete_node() {
    warning "Make sure you back up your node data before continuing.\n"
    warning "Yeah, I backed it up: (y/n)"
    read -r backup
    if [[ "$backup" =~ ^[Yy]$ ]]; then
        info "It's backed up. Continued..."
    else
        error "The backup has not been saved. Back to the menu......"
        return 1
    fi

    title "Stop node ${NAME}..."



    info "${NAME} deleted successfully."
    return 0
}

#

# Menu

# Menu options mapping
declare -A ACTIONS=(
    [1]=install_node
    [2]=restart_node
    [3]=stop_node
    [4]=check_node_logs
    [5]=update_node
    [6]=delete_node
    [7]=exit
)

while true
do
    PS3="Select an action for ${NAME}: "
    options=(
        "Install node"
        "Restart node"
        "Stop node"
        "Check node logs"
        "Update node"
        "Delete node"
        "Exit"
    )

    select opt in "${options[@]}"; do
        case $REPLY in
            1|2|3|4|5|6|7) "${ACTIONS[$REPLY]}"; break ;;
            *) error "Invalid option $REPLY" ;;
        esac
    done
done