#!/bin/bash

# Set the version variable
NAME="Dria Compute Node"
BIN_VER="0.4.0"

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER
# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "Failed to load utility script!"
    exit 1
fi

#

# Variables (default values are empty)
DRIA_P2P_PORT=4001

# Ensure the script is run as root

if [ "$EUID" -ne 0 ]; then
    error "Please run this script as root (sudo)."
    exit 1
fi

#

# Function to install node
install_node() {
    info "Installing node..."
    cd

    # Step 1: Check and set ports
    title "Checking if default ports are available..."
    DRIA_PORT=$DRIA_P2P_PORT

    if check_port_usage "$DRIA_PORT"; then
        error "Port $DRIA_PORT is in use. Please enter a new gRPC port:"
        read -r DRIA_PORT
        while check_port_usage "$DRIA_PORT"; do
            error "Port $DRIA_PORT is still in use. Please enter a different gRPC port:"
            read -r DRIA_PORT
        done
    fi

    # Step 2: Open necessary ports using UFW
    title "Opening required ports..."
    sudo ufw allow "$DRIA_PORT"/tcp || { error "Failed to open port $DRIA_PORT"; exit 1; }
    sudo ufw reload || { error "Failed to reload UFW"; exit 1; }
    info "Required ports ($DRIA_PORT) opened successfully."

    # Step 3: Update system
    title "Update system components..."
    cd
    sudo apt update && sudo apt install -y curl git make jq build-essential gcc unzip wget lz4 aria2 tmux || { error "Failed to update system"; exit 1; }
    info "System updated successfully."

    # Step 4: Download dria node
    title "Downloading and install dria node..."
    cd
    sudo curl -fsSL https://dria.co/launcher | bash || { error "Failed to download and install dria node"; exit 1; }
    info "dria node archives downloaded successfully."

    echo "Before source: PATH=$PATH"
    export PATH="/root/.dria/bin:$PATH"
    echo "After source: PATH=$PATH"

    sleep 3

    # Step 5: Download and install ollama
    title "Downloading and install ollama..."
    cd
    curl -fsSL https://ollama.com/install.sh | sh || { error "Failed to download and install ollama"; exit 1; }
    info "Ollama downloaded and installed successfully."

    # Step 6: Replace .env file
    title "Change parameters in the .env file."
    mkdir /root/.dria/dkn-compute-launcher || { error "Failed to create .dria/dkn-compute-launcher folder"; exit 1; }
    touch /root/.dria/dkn-compute-launcher/.env || { error "Failed to create .dria/dkn-compute-launcher/.env file"; exit 1; }
    info "The .env file has been successfully updated."

    title "Start Dria node..."
    dkn-compute-launcher start

    info "Node installed successfully."
    return 0
}

# Function to start node
start_node() {
    title "Start dria service..."
    dkn-compute-launcher start
    info "Dria node started successfully."
    return 0
}

# Function to restart node
restart_node() {
    title "Restart dria service..."
    sudo systemctl restart dria.service
    info "Dria service container restarted successfully."
    return 0
}

# Function to stop node
stop_node() {
    title "Stop drip service..."
    sudo systemctl stop drip.service
    info "Drip service container stopped successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    title "Checking dria node logs..."
    sudo journalctl -fu dria -o cat --no-hostname
    return 0
}

# Function to update node
update_node() {
    title "Update dria node..."

    return 0
}

# Function to delete node
delete_node() {
    title "Delete dria node..."

    return 0
}

#

# Menu

while true
do

    PS3='Select an action for Dria: '
    options=(
        "Install node"
        "Start node"
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
            "Start node")
                start_node
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