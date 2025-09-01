#!/bin/bash

# Set the version variable
NAME="Elixir"
BIN_VER="3.6.0"

INFO_PORT=17690

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "Failed to load utility script!"
    exit 1
fi

#

# Stop Elixir container
stop_container() {
    docker stop elixir
    docker rm elixir
}

# Remove old Elixir container
remove_old_container() {
    title "Removing old unused Elixir Docker images..."

    # Get names of images containing elixir (case-insensitive)
    image_names=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -i 'elixir')

    # Remove images containing elixir
    if [ -n "$image_names" ]; then
        title "Removing images with name elixir..."
        docker rmi $image_names 2>/dev/null
    else
        info "No images with name elixir."
    fi

    # Check if there are any elixir images remaining
    remaining_images=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'elixir' | awk '{print $1":"$2}')
    if [ -z "$remaining_images" ]; then
        info "All elixir images have been deleted."
    else
        error "There are images of elixir left:"
        docker images --format '{{.Repository}}:{{.Tag}}' | grep 'elixir' | awk '{print $1":"$2}'
    fi

    # Prune unused Docker images
    title "Pruning unused Docker images..."
    docker system prune -f || { error "Failed to prune unused Docker images"; exit 1; }
    info "Unused Docker images pruned successfully."
}

find_validator_env() {
    local user_home=${1:-"/root"}  # If no parameter is specified, /root is used
    local root_env="/root/.elixir/validator.env"
    local user_env="$user_home/.elixir/validator.env"

    if [ -f "$root_env" ]; then
        echo "$root_env"
        return 0
    elif [ -f "$user_env" ]; then
        echo "$user_env"
        return 0
    else
        echo ""
        return 1
    fi
}

# Function to install node
install_node() {
    if ! check_docker_installed; then
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi

    info "Installing node ${NAME}..."
    cd

    # Update system and install build tools
    title "Updating system and installing build tools..."
    sudo apt -q update || { error "Failed to update system"; exit 1; }
    sudo apt -qy install curl git jq lz4 build-essential || { error "Failed to install build tools"; exit 1; }
    sudo apt -qy upgrade || { error "Failed to upgrade system"; exit 1; }
    info "System updated and build tools installed successfully."

    # Docker download
    title "Downloading Docker image..."
    cd
    docker pull elixirprotocol/validator:testnet || { error "Failed to pull Docker image"; exit 1; }
    info "Docker image downloaded successfully."

    # Check and set ports
    title "Checking if default ports are available..."
    if check_port_usage "${INFO_PORT}"; then
        error "Port ${INFO_PORT} is in use. Please enter a new port:"
        read -r INFO_PORT
        while check_port_usage "${INFO_PORT}"; do
            error "Port ${INFO_PORT} is still in use. Please enter a different port:"
            read -r INFO_PORT
        done
    fi

    # Open ports
    title "Opening port ${INFO_PORT}..."
    sudo ufw allow $INFO_PORT/tcp || { error "Failed to open port $INFO_PORT"; exit 1; }
    sudo ufw reload || { error "Failed to reload UFW"; exit 1; }
    info "Port $INFO_PORT opened successfully."

    # Get public IP
    title "Getting public IP address..."
    ENR_ADDRESS=$(wget -qO- eth0.me)
    if [ -z "$ENR_ADDRESS" ]; then
        error "Failed to determine the public IP. Verify that the eth0.me service is available."
        exit 1
    fi
    info "Public IP address: $ENR_ADDRESS"

    # Request ETH public, private key and MONIKER
    while [ -z "$NEW_PUBLIC_KEY" ]; do
        read -p "Enter ETH public key: " NEW_PUBLIC_KEY
    done
    while [ -z "$NEW_PRIVATE_KEY" ]; do
        read -sp "Enter ETH private key: " NEW_PRIVATE_KEY
    done
    echo ""
    while [ -z "$MONIKER" ]; do
        read -p "Enter MONIKER: " MONIKER
    done

    # Create a config.toml file
    title "Creating validator.env file..."
    mkdir -p "$HOME/.elixir" || { error "Failed to create directory $HOME/.elixir"; exit 1; }
    sudo tee "$HOME/.elixir/validator.env" > /dev/null <<EOF
ENV=testnet-3
STRATEGY_EXECUTOR_IP_ADDRESS=$ENR_ADDRESS
STRATEGY_EXECUTOR_DISPLAY_NAME=$MONIKER
STRATEGY_EXECUTOR_BENEFICIARY=$NEW_PUBLIC_KEY
SIGNER_PRIVATE_KEY=$NEW_PRIVATE_KEY
EOF
    info "validator.env file created successfully."

    # Docker run
    title "Running Docker container..."
    docker run -d \
        --env-file "$HOME/.elixir/validator.env" \
        --name elixir \
        --restart unless-stopped \
        elixirprotocol/validator:testnet || { error "Failed to run Docker container"; exit 1; }
    info "Docker container started successfully."

    info "Node ${NAME} installed successfully."
    return 0
}

# Restart node
restart_node() {
    title "Restart docker container for ${NAME}..."
    stop_container
    docker run -d --env-file $HOME/.elixir/validator.env --name elixir --restart unless-stopped elixirprotocol/validator:testnet

    info "Docker container for ${NAME} restarted successfully."
    return 0
}

# Stop node
stop_node() {
    title "Stop docker container for ${NAME}..."
    stop_container
    info "Docker container for ${NAME} stopped successfully."
}

# Function to check node logs
check_node_logs() {
    title "Checking node logs for ${NAME}..."
    docker logs -f elixir
    return 0
}

# Function to update node
update_node() {
    if ! check_docker_installed; then
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi

    info "Updating node ${NAME}..."

    # Stop and remove old Elixir Docker container
    title "Stopping and removing old Elixir Docker container..."
    if docker ps -a --filter "name=elixir" -q | grep -q .; then
        stop_container
        info "Old Elixir Docker container stopped and removed successfully."
    else
        warning "No old Elixir Docker container found."
    fi

    # Remove old unused Elixir Docker images
    remove_old_container

    title "Checking for validator.env file..."
    VALIDATOR_ENV=$(find_validator_env "/home/ritual")

    if [ -z "$VALIDATOR_ENV" ]; then
        error "validator.env file not found in both locations. Exiting..."
        exit 1
    elif [ "$VALIDATOR_ENV" != "/root/.elixir/validator.env" ]; then
        warning "validator.env not found in /root/.elixir/"
        warning "But it was found in $VALIDATOR_ENV"
        read -p "Do you want to use this file instead? (y/n): " choice
        if [[ ! "$choice" =~ ^[Yy]$ ]]; then
            error "validator.env file is required. Exiting..."
            exit 1
        fi
    fi

    # Start new Elixir Docker container
    title "Starting new Elixir Docker container..."
    docker run -d \
        --env-file "$VALIDATOR_ENV" \
        --name elixir \
        --restart unless-stopped \
        elixirprotocol/validator:testnet || { error "Failed to start new Elixir Docker container"; exit 1; }

    check_node_logs

    info "Node ${NAME} updated successfully."
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

    if ! check_docker_installed; then
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi

    info "Deleting node ${NAME}..."

    # Stop and remove old Elixir Docker container
    title "Stopping and removing old Elixir Docker container..."
    if docker ps -a --filter "name=elixir" -q | grep -q .; then
        stop_node
        info "Old Elixir Docker container stopped and removed successfully."
    else
        warning "No old Elixir Docker container found."
    fi

    # Remove old unused Elixir Docker images
    remove_old_container

    # Remove config file
    title "Remove config file..."
    rm -rf $HOME/.elixir || { error "Failed to remove config file"; exit 1; }
    info "Config file removed successfully."

    info "Node ${NAME} deleted successfully."
    return 0
}


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
