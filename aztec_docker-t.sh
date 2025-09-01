#!/bin/bash

# Set the version variable
NAME="Aztec (testnet)"
BIN_VER=".latest"
P2P_PORT=40400
PORT_INFO=8084
INSTALL_DIR="aztec-sequencer"

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "❌ Failed to load utility script!"
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

# Function to install node
install_node() {
    if ! check_docker_installed; then
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi
    cd $HOME
    text_box "TITLE" "Installing node ${NAME}..."
    text_box "INFO" "Creating project directory: $INSTALL_DIR"
    mkdir -p $INSTALL_DIR && cd $INSTALL_DIR
    text_box "INFO" "Installing Aztec CLI Tools..."
    bash -i <(curl -s https://install.aztec.network)
    echo 'export PATH="$PATH:/root/.aztec/bin"' >> ~/.bashrc && source ~/.bashrc
    text_box "INFO" "Aztec alpha-testnet preparation..."
    aztec-up alpha-testnet

    # Get public IP
    text_box "INFO" "Getting public IP address..."
    ENR_ADDRESS=$(wget -qO- eth0.me)
    if [ -z "$ENR_ADDRESS" ]; then
        text_box "ERROR" "Failed to determine the public IP. Verify that the eth0.me service is available."
        exit 1
    fi
    text_box "DONE" "Public IP address: $ENR_ADDRESS"

    # Request info...
    text_box "INFO" "Request info..."
    while [ -z "$L1_RPC" ]; do
        read -p "Enter L1 RPC url (e.g. https://sepolia.rpc.url): " L1_RPC
    done
    while [ -z "$BLOB_SYNC_URL" ]; do
        read -p "Enter L1 Consensus host url (e.g. https://beacon.rpc.url): " BLOB_SYNC_URL
    done
    while [ -z "$WALLET_ADDRESS" ]; do
        read -p "Enter ETH wallet address (0x...): " WALLET_ADDRESS
    done
    while [ -z "$WALLET_PRIVATE_KEY" ]; do
        read -sp "Enter ETH private key (0x...): " WALLET_PRIVATE_KEY
    done

    # Create .env file
    text_box "INFO" "Creating .env file..."
cat <<EOF > .env
ETHEREUM_HOSTS=$L1_RPC
L1_CONSENSUS_HOST_URLS=$BLOB_SYNC_URL
VALIDATOR_PRIVATE_KEY=$WALLET_PRIVATE_KEY
VALIDATOR_ADDRESS=$WALLET_ADDRESS
P2P_IP=$ENR_ADDRESS
AZTEC_PORT="${PORT_INFO}"
P2P_MAX_TX_POOL_SIZE=100000000
LOG_LEVEL="debug"
EOF
    text_box "DONE" ".env file created."

# Create docker-compose.yml
    text_box "INFO" "Creating docker-compose.yml file..."
cat <<EOF > docker-compose.yml
version: '3.8'

services:
    aztec-node:
        container_name: aztec-sequencer
        image: aztecprotocol/aztec:alpha-testnet
        restart: unless-stopped
        env_file:
            - .env
        entrypoint: >
            sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --network alpha-testnet --node --archiver --sequencer'
        ports:
            - ${P2P_PORT}:40400/tcp
            - ${P2P_PORT}:40400/udp
            - ${PORT_INFO}:8080
        volumes:
            - ./data:/root/.aztec
        network_mode: host
    volumes:
    data:
EOF
    text_box "DONE" "docker-compose.yml file created."

    text_box "DONE" "${NAME} installed successfully."
    return 0
}

# Function to restart node
restart_node() {
    text_box "TITLE" "Restart node ${NAME}..."
    cd $HOME/$INSTALL_DIR
    docker compose down
    docker compose up
    text_box "DONE" "${NAME} restarted successfully."
    return 0
}

# Function to stop node
stop_node() {
    text_box "TITLE" "Stop ${NAME}..."
    cd $HOME/$INSTALL_DIR
    docker compose down
    text_box "DONE" "${NAME} stopped successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    if ! check_docker_installed; then
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi
    text_box "TITLE" "Checking node logs for ${NAME}..."
    cd $HOME/$INSTALL_DIR
    docker compose logs -f
    return 0
}

# Function to update node
update_node() {
    text_box "TITLE" "Updating node ${NAME}..."



    text_box "DONE" "${NAME} updated successfully."
    return 0
}

# Function to delete node
delete_node() {
    text_box "TITLE" "Delete node ${NAME}..."
    text_box "WARNING" "Make sure you back up your node data before continuing. Yeah, I backed it up: (y/n)"
    read -r backup
    if [[ "$backup" =~ ^[Yy]$ ]]; then
        text_box "INFO" "It's backed up. Continued..."
    else
        text_box "ERROR" "The backup has not been saved. Back to the menu......"
        return 1
    fi



    text_box "DONE" "${NAME} deleted successfully."
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
            *) text_box "ERROR" "Invalid option $REPLY" ;;
        esac
    done
done
