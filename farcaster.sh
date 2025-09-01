#!/bin/bash

# Set the version variable
VER="Farcaster:latest"
INFO_PORT=2281

# Export the version variable to make it available in the sourced script
export VER
# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "Failed to load utility script!"
    exit 1
fi

#

# Remove old Farcaster (hubble) container
remove_old_container() {
    title "Removing old unused Farcaster Docker images..."
    old_images=$(docker images --format "{{.Repository}} {{.ID}}" | grep farcaster | awk '{print $2}')
    if [ -n "$old_images" ]; then
        echo "$old_images" | xargs docker rmi || { error "Failed to remove old unused Farcaster Docker images"; exit 1; }
        info "Old unused Farcaster Docker images removed successfully."
    else
        warning "No old unused Farcaster Docker images found."
    fi

    # Prune unused Docker images

    title "Pruning unused Docker images..."
    docker system prune -f || { error "Failed to prune unused Docker images"; exit 1; }
    info "Unused Docker images pruned successfully."
}

# Function to install node
install_node() {
    if ! check_docker_installed; then
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi

    info "Installing node..."
    cd

    # Prompt for unique values

    title "Prompt for unique values..."
    read -rp "Enter API_KEY: " API_KEY
    read -rp "Enter HUB_OPERATOR_FID: " HUB_OPERATOR_FID

    # Git repo clone

    title "Cloning Git repository..."
    git clone https://github.com/farcasterxyz/hub-monorepo.git || { error "Failed to clone Git repository"; exit 1; }
    info "Git repository cloned successfully."

    # Change directory to the appropriate location

    cd hub-monorepo/apps/hubble || { error "Failed to change directory to hub-monorepo/apps/hubble"; exit 1; }
    info "Changed directory to hub-monorepo/apps/hubble."

    # Create folders

    title "Creating folders..."
    mkdir -p .hub .rocks grafana/data || { error "Failed to create folders"; exit 1; }
    info "Folders created successfully."

    # Set the necessary permissions

    title "Setting the necessary permissions for: .hub .rocks grafana..."
    chmod -R 777 .hub .rocks grafana || { error "Failed to set permissions"; exit 1; }
    info "Permissions set successfully."

    # Create or overwrite the .env file with the provided values

    title "Creating or overwriting the .env file with the provided values..."
    cat <<EOL > .env
FC_NETWORK_ID=1
BOOTSTRAP_NODE=/dns/nemes.farcaster.xyz/tcp/2282
STATSD_METRICS_SERVER=statsd:8125
ETH_MAINNET_RPC_URL=https://mainnet.infura.io/v3/$API_KEY
OPTIMISM_L2_RPC_URL=https://optimism-mainnet.infura.io/v3/$API_KEY
HUB_OPERATOR_FID=$HUB_OPERATOR_FID
EOL

    info ".env file created successfully."

    # Generate a random port number between 3000 and 3999

    PRT=$(echo $((1000 + (RANDOM % 1000))))
    title "Generating random port number: 3${PRT}..."

    # Update the docker-compose.yml file with the new port

    title "Updating docker-compose.yml with the new port..."
    sed -i "s|3000:3000|3${PRT}:3000|" docker-compose.yml || { error "Failed to update docker-compose.yml"; exit 1; }
    info "Grafana port is 3${PRT}"
    info "docker-compose.yml updated successfully."

    # Run Docker Compose to create identity

    title "Running Docker Compose to create identity..."
    docker compose run hubble yarn identity create || { error "Failed to create identity"; exit 1; }
    info "Identity created successfully."

    # Run Docker Compose to start the services

    title "Running Docker Compose to start the services..."
    docker compose up || { error "Failed to start Docker Compose services"; exit 1; }
    info "Node installed successfully."
    return 0
}

# Restart node
restart_node() {
    title "Restart docker container for Farcaster..."
    cd $HOME/hub-monorepo/apps/hubble
    docker compose down
    docker compose up

    info "Docker container restarted successfully."
}

# Stop node
stop_node() {
    title "Stop docker container for Farcaster..."
    cd $HOME/hub-monorepo/apps/hubble
    docker compose down

    info "Docker container stopped successfully."
}

# Function to check node logs
check_node_logs() {
    if ! check_docker_installed; then
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi

    title "Checking node logs..."
    cd $HOME/hub-monorepo/apps/hubble
    docker logs -f
    return 0
}

# Function to update node
update_node() {
    info "Updating node..."

    # Remove old images
    remove_old_container

    cd $HOME/hub-monorepo

    # Checkout to the latest release
    git fetch --tags --force && git checkout @latest

    cd $HOME/hub-monorepo/apps/hubble

    # Stop current container and start the upgraded one
    docker compose down
    docker compose up -d --force-recreate --pull always  
    info "Node updated successfully."
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

    info "Deleting node..."

    # Stop and remove old Farcaster Docker container

    title "Stopping and removing old Farcaster Docker container..."

    cd $HOME/hub-monorepo/apps/hubble
    docker compose down || { error "Failed to stop Docker container 'Farcaster (hubble)'"; exit 1; }

    # Remove old images
    remove_old_container

    info "Node deleted successfully."
    return 0
}

#

# Menu

while true
do

    PS3='Select an action for Farcaster: '
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