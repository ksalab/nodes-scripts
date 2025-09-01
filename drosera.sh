#!/bin/bash

# Set the version variable
NAME="Drosera"
BIN_VER="1.15.0"

GIT_URL="https://github.com/drosera-network/releases/releases/download/v1.15.0/"
OPERATOR_ARC="${GIT_URL}drosera-operator-v1.15.0-x86_64-unknown-linux-gnu.tar.gz"
DELEGATOR_ARC="${GIT_URL}drosera-delegation-client-v1.15.0-x86_64-unknown-linux-gnu.tar.gz"
P2P_PORT=31313
SERVER_PORT=31314

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

# Function to install node
install_node() {
    cd $HOME
    title "Installing node ${NAME}..."

    title "Creating installation directory..."
    mkdir $HOME/.drosera  || { error "Failed to create $HOME/.drosera directory"; exit 1; }
    cd $HOME/.drosera
    info "Installation directory created successfully."

    title "Downloading drosera-operator binary..."
    curl -LO $GIT_URL$OPERATOR_ARC || { error "Failed to download drosera-operator binary"; exit 1; }
    tar -xvf $OPERATOR_ARC
    info "drosera-operator binary downloaded successfully."
    
    title "Check version drosera-operator..."
    ./drosera-operator --version

    # Open ports
    title "Open ports..."
    for port in ${P2P_PORT} ${SERVER_PORT}; do
        sudo ufw allow "$port" || { error "Failed to open port $port"; exit 1; }
    done
    sudo ufw reload || { error "Failed to reload UFW"; exit 1; }

    # Get public IP
    title "Getting public IP address..."
    ENR_ADDRESS=$(wget -qO- eth0.me)
    if [ -z "$ENR_ADDRESS" ]; then
        error "Failed to determine the public IP. Verify that the eth0.me service is available."
        exit 1
    fi
    info "Public IP address: $ENR_ADDRESS"

    # Request info...
    title "Request info..."

    # New keys for run node
    while [ -z "$NEW_RPC_URL" ]; do
        read -p "Enter Holesky RPC url: " NEW_RPC_URL
    done

    while [ -z "$NEW_RPC_URL_2" ]; do
        read -p "Enter Holesky RPC reserve url: " NEW_RPC_URL_2
    done

    while [ -z "$NEW_PRIVATE_KEY" ]; do
        read -sp "Enter ETH private key: " NEW_PRIVATE_KEY
    done

    echo ""

    title "Register as Operator..."
    ./drosera-operator register --eth-rpc-url $NEW_RPC_URL --eth-private-key $NEW_PRIVATE_KEY


    ./drosera-operator node --eth-rpc-url $NEW_RPC_URL --eth-backup-rpc-url $NEW_RPC_URL_2 --eth-private-key $NEW_PRIVATE_KEY --network-public-address $ENR_ADDRESS



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