#!/bin/bash

# Set the version variable
VER="Ritual v1.4.0"

# Export the version variable to make it available in the sourced script
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "Failed to load utility script!"
    exit 1
fi

#

# Files for change settings
DEPLOY_CONFIG_JSON="$HOME/infernet-container-starter/deploy/config.json"
HELLO_WORLD_CONFIG_JSON="$HOME/infernet-container-starter/projects/hello-world/container/config.json"
SOLIDITY_FILE="$HOME/infernet-container-starter/projects/hello-world/contracts/script/Deploy.s.sol"
MAKE_FILE="$HOME/infernet-container-starter/projects/hello-world/contracts/Makefile"
DOCKER_COMPOSE_FILE="$HOME/infernet-container-starter/deploy/docker-compose.yaml"

#RPC_URL="https://mainnet.base.org/"
REGISTRY_ADDRESS="0x3B1554f346DFe5c482Bb4BA31b880c1C18412170"
TRAIL_HEAD_BLOCKS=3
SLEEP=3
BATH_SIZE=800
STARTING_SUB_ID=220000
SYNC_PERIOD=30
IMAGE="ritualnetwork/infernet-node:1.4.0"
GRAFANA_PORT=8645
INFO_PORT=4000

#

# # Remove old Elixir container
remove_old_container() {
    # Get names of images containing ritualnetwork (case-insensitive)
    image_names=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'ritualnetwork|redis|fluent')
    # Remove images containing ritualnetwork
    if [ -n "$image_names" ]; then
        text_box "TITLE" "Removing images with name ritualnetwork..."
        docker rmi $image_names 2>/dev/null
    else
        text_box "INFO" "No images with name ritualnetwork."
    fi

    # Check if there are any ritualnetwork images remaining
    remaining_images=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'ritualnetwork' | awk '{print $1":"$2}')
    if [ -z "$remaining_images" ]; then
        text_box "DONE" "All ritualnetwork images have been deleted."
    else
        text_box "ERROR" "There are images of ritualnetwork left:"
        docker images --format '{{.Repository}}:{{.Tag}}' | grep 'ritualnetwork' | awk '{print $1":"$2}'
    fi
}

# Update json files
update_json_file() {
    local file="$1"

    if [ ! -f "$file" ]; then
        text_box "ERROR" "Error: File $file not found!"
        return 1
    fi

    jq \
        --arg rpc_url "$NEW_RPC_URL" \
        --arg registry_address "$REGISTRY_ADDRESS" \
        --arg private_key "$NEW_PRIVATE_KEY" \
        --argjson trail_head_blocks "$TRAIL_HEAD_BLOCKS" \
        --argjson sleep "$SLEEP" \
        --argjson batch_size "$BATH_SIZE" \
        --argjson starting_sub_id "$STARTING_SUB_ID" \
        --argjson sync_period "$SYNC_PERIOD" \
        --arg container_id "$NEW_CONTAINER_ID" \
        '
        .chain.rpc_url = $rpc_url |
        .chain.registry_address = $registry_address |
        .chain.wallet.private_key = $private_key |
        .chain.trail_head_blocks = $trail_head_blocks |
        .chain.snapshot_sync.sleep = $sleep |
        .chain.snapshot_sync.batch_size = $batch_size |
        .chain.snapshot_sync += {starting_sub_id: $starting_sub_id, sync_period: $sync_period} |
        .containers |= map(
        if .id then .id = $container_id else . end
        ) |
    #    .chain.containers.id = $container_id |
        del(.docker)
        ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

    if [ $? -eq 0 ]; then
        text_box "DONE" "Updated $file successfully!"
    else
        text_box "ERROR" "Failed to update $file!"
        return 1
    fi
}

# Update configurations files
update_configs() {
    text_box "TITLE" "Updating config files..."
    update_json_file "$DEPLOY_CONFIG_JSON"
    update_json_file "$HELLO_WORLD_CONFIG_JSON"

    # Solidity script
    if [ ! -f "$SOLIDITY_FILE" ]; then
        text_box "ERROR" "File $SOLIDITY_FILE not found!"
        exit 1
    fi

    text_box "INFO" "Update Solidity script"
    sed -i -E "s/(address registry\s*=\s*)[0-9a-zA-Z]+;/\1$REGISTRY_ADDRESS;/" "$SOLIDITY_FILE"
    if [ $? -eq 0 ]; then
        text_box "DONE" "Updated registry address in $SOLIDITY_FILE successfully!"
    else
        text_box "ERROR" "Failed to update registry address in $SOLIDITY_FILE!"
    fi

    if [ ! -f "$MAKE_FILE" ]; then
        text_box "ERROR" "File $MAKE_FILE not found!"
        exit 1
    fi

    text_box "INFO" "Updating Makefile..."
    sed -i -E "s/^sender\s*:=.*/sender := $NEW_PRIVATE_KEY;/" "$MAKE_FILE"
    sed -i -E "s|(RPC_URL\s*:=\s*).*|\1$NEW_RPC_URL|" "$MAKE_FILE"

    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        text_box "ERROR" "File $DOCKER_COMPOSE_FILE not found!"
        exit 1
    fi

    text_box "INFO" "Updating docker-compose.yaml..."
    sed -i -E "s|(image: ritualnetwork/infernet-node:)[0-9]+\.[0-9]+\.[0-9]+|\1${IMAGE#*:}|" "$DOCKER_COMPOSE_FILE"
    sed -i "s/8545:3000/$GRAFANA_PORT:3000/g" "$DOCKER_COMPOSE_FILE"

    # Remove the anvil dependencies
    sed -i '/- infernet-anvil/d' "$DOCKER_COMPOSE_FILE"

    temp_file=$(mktemp)

    # remove block infernet-anvil
    awk '
    BEGIN { delete_block = 0 }
    /^  infernet-anvil:/ { delete_block = 1; next }
    delete_block && /^[[:space:]]*$/ { delete_block = 0; next }
    !delete_block { print }
    ' $HOME/infernet-container-starter/deploy/docker-compose.yaml > "$temp_file"

    # replace original file
    mv "$temp_file" $HOME/infernet-container-starter/deploy/docker-compose.yaml

    if [ $? -eq 0 ]; then
        text_box "DONE" "Updated image in $DOCKER_COMPOSE_FILE successfully!"
    else
        text_box "ERROR" "Failed to update image in $DOCKER_COMPOSE_FILE!"
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

    text_box "TITLE" "Installing node..."

    # Update packages and Install dependencies
    # title "Updating system and installing build tools..."
    # sudo apt update && sudo apt upgrade -y
    # sudo apt -qy install curl git jq lz4 build-essential ca-certificates -y
    # info "System updated and build tools installed successfully."

    # Check and set ports
    # title "Checking if default ports are available..."
    # if check_port_usage "${INFO_PORT}"; then
    #     error "Port ${INFO_PORT} is in use. Please enter a new port:"
    #     read -r INFO_PORT
    #     while check_port_usage "${INFO_PORT}"; do
    #         error "Port ${INFO_PORT} is still in use. Please enter a different port:"
    #         read -r INFO_PORT
    #     done
    # fi

    # Stop Ritual containers
    # cd $HOME/infernet-container-starter/deploy/

    # Docker down
    # title "Stopping existing containers..."
    # docker compose down || { error "Failed to stop containers!"; exit 1; }
    # info "Existing containers stopped successfully."

    # Remove old containers
    remove_old_container

    # Open ports
    text_box "INFO" "Opening port ${INFO_PORT}..."
    sudo ufw allow ${INFO_PORT}/tcp || { text_box "ERROR" "Failed to open port $INFO_PORT"; exit 1; }
    sudo ufw reload || { text_box "ERROR" "Failed to reload UFW"; exit 1; }
    text_box "DONE" "Port $INFO_PORT opened successfully."

    # Clone repo
    text_box "INFO" "Clone repo..."
    cd
    git clone https://github.com/ritual-net/infernet-container-starter || { text_box "ERROR" "Failed to clone Git repository"; exit 1; }
    text_box "DONE" "Git repository cloned successfully."

    # Request info...
    text_box "INFO" "Request info..."

    # New keys for DEPLOY_CONFIG_JSON
    while [ -z "$NEW_RPC_URL" ]; do
        read -p "Enter RPC url: " NEW_RPC_URL
    done

    while [ -z "$NEW_PRIVATE_KEY" ]; do
        read -sp "Enter ETH private key: " NEW_PRIVATE_KEY
    done

    echo ""

    while [ -z "$NEW_CONTAINER_ID" ]; do
        read -p "Enter contract ID: " NEW_CONTAINER_ID
    done

    # Update configurations files
    update_configs

    cd $HOME/infernet-container-starter || { text_box "ERROR" "Failed to change directory to $HOME/infernet-container-starter"; exit 1; }
    project=hello-world make deploy-container || { text_box "ERROR" "Failed to deploy container"; exit 1; }

    cd $HOME/infernet-container-starter/deploy/

    # Docker down
    text_box "INFO" "Stopping existing containers..."
    docker compose down || { text_box "ERROR" "Failed to stop containers!"; exit 1; }
    text_box "DONE" "Existing containers stopped successfully."

    # Docker up
    text_box "INFO" "Starting new containers..."
    docker compose up -d || { text_box "ERROR" "Failed to start containers!"; exit 1; }
    text_box "DONE" "New containers started successfully."

    text_box "DONE" "Node installed successfully."
    return 0
}

# Restart node
restart_node() {
    text_box "TITLE" "Restart docker container for Ritual..."
    cd $HOME/infernet-container-starter/deploy/
    docker compose down
    docker compose up

    text_box "DONE" "Docker container restarted successfully."
}

# Function to stop node
stop_node() {
    text_box "TITLE" "Stop docker container for Ritual..."
    cd $HOME/infernet-container-starter/deploy/
    docker compose down
    containers=$(docker ps -a --filter "ancestor=ritualnetwork/hello-world-infernet:latest" -q)
    if [ -n "$containers" ]; then
        docker stop $containers 2>/dev/null
        docker rm $containers 2>/dev/null
    else
        echo "No containers found"
    fi
    text_box "DONE" "Docker container stopped successfully."
}

# Function to check node logs
check_node_logs() {
    if ! check_docker_installed; then
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi

    text_box "TITLE" "Checking node logs..."
    cd $HOME/infernet-container-starter/deploy
    docker compose logs -f
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

    text_box "TITLE" "Updating node..."

    text_box "DONE" "Node updated successfully."
    return 0
}

# Function to update validator (change validator)
update_validator() {
    text_box "TITLE" "Updating validator info..."

    cd $HOME/infernet-container-starter/deploy/

    # Docker down
    text_box "INFO" "Stopping existing containers..."
    docker compose down || { text_box "ERROR" "Failed to stop containers!"; exit 1; }
    text_box "DONE" "Existing containers stopped successfully."

    # Request info...
    text_box "INFO" "Request info..."

    # New keys for DEPLOY_CONFIG_JSON
    while [ -z "$NEW_RPC_URL" ]; do
        read -p "Enter RPC url: " NEW_RPC_URL
    done

    while [ -z "$NEW_PRIVATE_KEY" ]; do
        read -sp "Enter ETH private key: " NEW_PRIVATE_KEY
    done

    echo ""

    while [ -z "$NEW_CONTAINER_ID" ]; do
        read -p "Enter contract ID: " NEW_CONTAINER_ID
    done

    # Update configurations files
    update_configs

    # Docker up
    text_box "INFO" "Starting containers..."
    docker compose up -d || { text_box "ERROR" "Failed to start containers!"; exit 1; }
    text_box "DONE" "Containers started successfully."

    text_box "DONE" "Validator info updated successfully..."
    return 0
}

# Function to delete node
delete_node() {
    text_box "TITLE" "Deleting node..."
    text_box "WARNING" "Make sure you back up your node data before continuing. Yeah, I backed it up: (y/n)"
    read -r backup
    if [[ "$backup" =~ ^[Yy]$ ]]; then
        text_box "INFO" "It's backed up. Continued..."
    else
        text_box "ERROR" "The backup has not been saved. Back to the menu......"
        return 1
    fi

    if ! check_docker_installed; then
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi

    text_box "INFO" "Deleting node..."

    # Stop and remove old Ritual Docker container
    cd $HOME/infernet-container-starter/deploy/

    # Docker down
    stop_node

    # Delete Ritual folder
    rm -r $HOME/infernet-container-starter
    rm -r $HOME/infernet-node

    # Remove old unused containers
    remove_old_container

    text_box "DONE" "Node deleted successfully."
    return 0
}

#

# Menu

while true
do
    PS3='Select an action for Ritual: '
    options=(
        "Install node"
        "Restart node"
        "Stop node"
        "Check node logs"
        "Update node"
        "Update validator info"
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
            "Update validator info (change validator)")
                update_validator
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
                text_box "ERROR" "Invalid option $REPLY"
                ;;
        esac
    done
done
