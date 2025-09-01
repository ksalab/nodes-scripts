#!/bin/bash

# Set the version variable
NAME="0g (ZeroGravity) DA Node"

DA_VERSION="1.1.3"
SERVICE_NAME="0gda"
GRPC_LISTEN_ADDRESS="0.0.0.0:34000"
ETH_RPC_ENDPOINT="https://evmrpc-testnet.0g.ai"
SOCKET_ADDRESS="${ENR_ADDRESS}:34000"
DA_ENTRANCE_ADDRESS="0x857C0A28A8634614BB2C96039Cf4a20AFF709Aa9"
START_BLOCK_NUMBER=940000
ENABLE_DAS="true"

# Export the version variable to make it available in the sourced script
VER="${NAME} v${DA_VERSION}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "❌ Failed to load utility script!"
    exit 1
fi

#

# Function to install node
install_node() {
    cd $HOME
    text_box "TITLE" "Installing node ${NAME}..."

    # Check Rust versions
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

    # Download and build binary, download params
    text_box "INFO" "Clone DA node repo..."
    cd "$HOME" || { text_box "ERROR" "Failed to change directory to $HOME"; exit 1; }
    rm -rf 0g-da-node
    git clone https://github.com/0glabs/0g-da-node.git || { text_box "ERROR" "Failed to clone repository"; exit 1; }
    cd 0g-da-node || { error "Failed to change directory to 0g-da-node"; exit 1; }
    git checkout tags/v${DA_VERSION} -b v${DA_VERSION} || { text_box "ERROR" "Failed to checkout tag v${DA_VERSION}"; exit 1; }

    text_box "INFO" "Building a binary file..."
    if ! cargo build --release; then
        text_box "ERROR" "Error while building a binary file!" >&2
        exit 1
    fi

    git checkout tags/v${DA_VERSION} -b v${DA_VERSION} || { error "Failed to checkout tag v${DA_VERSION}"; exit 1; }

    # Get public IP
    text_box "INFO" "Get current ip address..."
    ENR_ADDRESS=$(wget -qO- eth0.me)
    if [ -z "$ENR_ADDRESS" ]; then
        text_box "ERROR" "Failed to determine the public IP. Verify that the eth0.me service is available." >&2
        exit 1
    fi
    text_box "NOTE" "Current IP: ${ENR_ADDRESS}"

    # Request ETH and BLS private keys
    text_box "INFO" "Request ETH and BLS private keys..."
    while [ -z "$ETH_PRIVATE_KEY" ]; do
        text_box "INFO" "Enter ETH PRIVATE_KEY: "
        read -r ETH_PRIVATE_KEY
    done

    while [ -z "$BLS_PRIVATE_KEY" ]; do
        text_box "INFO" "Enter BLS PRIVATE_KEY: "
        read -r BLS_PRIVATE_KEY
    done

    # Create a config.toml file
    text_box "INFO" "Create a config.toml file..."
    sudo tee $HOME/0g-da-node/config.toml > /dev/null <<EOF
log_level = "info"

data_path = "./db/"

# path to downloaded params folder
encoder_params_dir = "params/" 

# grpc server listen address
grpc_listen_address = "${GRPC_LISTEN_ADDRESS}"
# chain eth rpc endpoint
eth_rpc_endpoint = "${ETH_RPC_ENDPOINT}"
# public grpc service socket address to register in DA contract
# ip:34000 (keep same port as the grpc listen address)
# or if you have dns, fill your dns
socket_address = "${SOCKET_ADDRESS}"

# data availability contract to interact with
da_entrance_address = "${DA_ENTRANCE_ADDRESS}"
# deployed block number of da entrance contract
start_block_number = ${START_BLOCK_NUMBER}

# signer BLS private key
signer_bls_private_key = "$BLS_PRIVATE_KEY"
# signer eth account private key
signer_eth_private_key = "$ETH_PRIVATE_KEY"
# miner eth account private key, (could be the same as 'signer_eth_private_key', but not recommended)
miner_eth_private_key = "$ETH_PRIVATE_KEY"

# whether to enable data availability sampling
enable_das = "${ENABLE_DAS}"
EOF

    if [ $? -ne 0 ]; then
        text_box "ERROR" "Failed to create config.toml file" >&2
        exit 1
    fi

    # Downloads parameters
    text_box "INFO" "Downloads parameters..."
    $HOME/0g-da-node/dev-support/download_params.sh || { text_box "ERROR" "Failed to download parameters"; exit 1; }
    sudo mv "$HOME/0g-da-node/dev-support/params" "$HOME/0g-da-node/params" || { text_box "ERROR" "Failed to move parameters"; exit 1; }

    # Create Service file
    text_box "INFO" "Create ${SERVICE_NAME}.service file..."
    sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=0G-DA Node
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/0g-da-node
ExecStart=$HOME/0g-da-node/target/release/server --config $HOME/0g-da-node/config.toml
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        text_box "ERROR" "Error when creating service file!" >&2
        exit 1
    fi

    # Enable and start service:
    text_box "INFO" "Start ${SERVICE_NAME}.service file..."
    sudo systemctl daemon-reload
    sudo systemctl enable ${SERVICE_NAME}
    sudo systemctl start ${SERVICE_NAME}

    if ! sudo systemctl is-active --quiet ${SERVICE_NAME}; then
        text_box "WARNING" "The ${SERVICE_NAME} service is not running. Check the logs with 'journalctl -u ${SERVICE_NAME} -o cat'." >&2
        exit 1
    fi

    text_box "DONE" "Node installed successfully."
    return 0
}

# Function to restart node
restart_node() {
    text_box "TITLE" "Restart node ${NAME}..."
    sudo systemctl restart ${SERVICE_NAME}
    if ! sudo systemctl is-active --quiet ${SERVICE_NAME}; then
        text_box "WARNING" "The ${SERVICE_NAME} service is not running. Check the logs with 'journalctl -fu ${SERVICE_NAME} -o cat'." >&2
        exit 1
    fi

    text_box "DONE" "Node restarted successfully."
    return 0
}

# Function to stop node
stop_node() {
    text_box "TITLE" "Stop node ${NAME}..."
    sudo systemctl stop ${SERVICE_NAME}

    text_box "DONE" "Node stopped successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    cd $HOME
    text_box "TITLE" "Checking node logs..."
    sudo journalctl -fu ${SERVICE_NAME} -o cat --no-hostname
    return 0
}

# Function to update node
update_node() {
    text_box "TITLE" "Update node ${NAME}..."

    # Stop node...
    stop_node

    # Backup configs...
    cp ${HOME}/0g-da-node/config.toml ${HOME}/config.toml.bak

    # Download and build binary, download params
    text_box "INFO" "Update DA node repo..."
    cd "$HOME" || { text_box "ERROR" "Failed to change directory to $HOME"; exit 1; }
    # git clone https://github.com/0glabs/0g-da-node.git || { error "Failed to clone repository"; exit 1; }
    cd 0g-da-node || { text_box "ERROR" "Failed to change directory to 0g-da-node"; exit 1; }
    git fetch --all --tag
    git checkout v${DA_VERSION}
    git submodule update --init
    cargo build --release

    text_box "INFO" "Building a binary file..."
    if ! cargo build --release; then
        text_box "ERROR" "Error while building a binary file!" >&2
        exit 1
    fi

    # Restore configs...
    mv ${HOME}/config.toml.bak ${HOME}/0g-da-node/config.toml

    # Restart node
    restart_node

    text_box "DONE" "Node updated successfully."
    return 0
}

# Function to delete node
delete_node() {
    text_box "TITLE" "Make sure you back up your node data before continuing.\n"
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
    DONE "Node stopped successfully."

    text_box "INFO" "Delete service for node ${NAME}..."
    sudo rm -rf /etc/systemd/system/${SERVICE_NAME}.service
    text_box "DONE" "Service for node deleted successfully."

    text_box "INFO" "Delete binaries for node..."
    sudo rm $(which ${SERVICE_NAME})
    text_box "DONE" "Binaries for node deleted successfully."

    text_box "INFO" "Remove node folders..."
    sudo rm -rf $HOME/0g-da-node
    text_box "DONE" "Node folders removed successfully."

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