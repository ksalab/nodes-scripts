#!/bin/bash

# Set the version variable
VER="Cysic verifier v1.0.0 (docker)"

# Export the version variable to make it available in the sourced script
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "Failed to load utility script!"
    exit 1
fi

#

# File with keys
KEYS_FILE="keys.json"

# Base folder for all containers
BASE_FOLDER="cysic_containers"
mkdir -p "$BASE_FOLDER"

#

# Function to install node (create containers)
install_node() {
    title "Creating containers..."

    # Checks
    if [ ! -f "Dockerfile" ]; then
        error "Error: Dockerfile not found in the current directory."
        return 1
    fi
    if [ ! -f "$KEYS_FILE" ]; then
        error "Error: $KEYS_FILE was not found. Make sure that the file exists in the folder from which the script is run."
        warning "The format of the keys.json file should be in the form:"
        warning "["
        warning "    {"
        warning "        { “address”: “0x11...”,"
        warning "    },"
        warning "    {"
        warning "        { “address”: “0xa3...”,"
        warning "    },"
        warning "    {...}"
        warning "]"
        return 1
    fi

    # Request the number of containers
    while true; do
        read -rp "Enter the number of containers to create: " NUM_CONTAINERS
        [[ "$NUM_CONTAINERS" =~ ^[0-9]+$ ]] && break
        error "Invalid input. Enter a number."
    done

    # Initial index query
    while true; do
        read -rp "Enter the start index for container numbering: " START_INDEX
        [[ "$START_INDEX" =~ ^[0-9]+$ ]] && break
        error "Invalid input. Enter a number."
    done

    # Creating containers
    for i in $(seq 0 $((NUM_CONTAINERS - 1))); do
        CONTAINER_INDEX=$((START_INDEX + i))
        CONFIG_FOLDER="$BASE_FOLDER/verifier$CONTAINER_INDEX"
        mkdir -p "$CONFIG_FOLDER/cysic" "$CONFIG_FOLDER/data"

        # Extract address from keys.json
        ADDRESS=$(jq -r ".[$CONTAINER_INDEX].address" "$KEYS_FILE")
        if [ -z "$ADDRESS" ] || [ "$ADDRESS" == "null" ]; then
            warning "Address for container verifier$CONTAINER_INDEX not found in $KEYS_FILE. Skipping..."
            continue
        fi

        # Create config.yaml
        cat > "$CONFIG_FOLDER/config.yaml" <<EOL
chain:
    endpoint: "grpc-testnet.prover.xyz:80"
    chain_id: "cysicmint_9001-1"
    gas_coin: "CYS"
    gas_price: 10
    claim_reward_address: "$ADDRESS"

server:
    cysic_endpoint: "https://api-testnet.prover.xyz"
EOL

        # Создание .env
        cat > "$CONFIG_FOLDER/.env" <<EOL
EVM_ADDR=$ADDRESS
CHAIN_ID=534352
EOL

        # Создание docker-compose.yml
        cat > "$CONFIG_FOLDER/docker-compose.yml" <<EOL
version: '3.8'
services:
    verifier:
        build:
            context: ../../
            dockerfile: Dockerfile
        volumes:
            - ./data:/app/data
            - ./cysic:/root/.cysic
    env_file:
            - .env
    network_mode: "host"
    restart: unless-stopped
EOL

        info "Configured container verifier$CONTAINER_INDEX with address $ADDRESS"
    done

    info "Containers have been created."
    return 0
}

# Function to start containers
start_node() {
    NUM_CONTAINERS=$(ls "$BASE_FOLDER" | wc -l)
    title "Starting $NUM_CONTAINERS containers..."

    for i in $(seq 11 $NUM_CONTAINERS); do
        CONFIG_FOLDER="$BASE_FOLDER/verifier$i"
        if [ -d "$CONFIG_FOLDER" ]; then
            docker-compose -p verifier$i -f "$CONFIG_FOLDER/docker-compose.yml" up -d
            info "The verifier$i container is running"
        else
            warning "Folder $CONFIG_FOLDER not found, skipping..."
        fi
    done
    return 0
}

# Function to stop containers
stop_node() {
    NUM_CONTAINERS=$(ls "$BASE_FOLDER" | wc -l)
    title "Stopping $NUM_CONTAINERS containers..."

    for i in $(seq 11 $NUM_CONTAINERS); do
        CONFIG_FOLDER="$BASE_FOLDER/verifier$i"
        if [ -d "$CONFIG_FOLDER" ]; then
            docker-compose -p verifier$i -f "$CONFIG_FOLDER/docker-compose.yml" down
            info "The verifier$i container has been stopped"
        else
            warning "Folder $CONFIG_FOLDER not found, skipping..."
        fi
    done
    return 0
}

# Function to restart containers
restart_node() {
    NUM_CONTAINERS=$(ls "$BASE_FOLDER" | wc -l)
    title "Restarting $NUM_CONTAINERS containers..."

    for i in $(seq 11 $NUM_CONTAINERS); do
        CONFIG_FOLDER="$BASE_FOLDER/verifier$i"
        if [ -d "$CONFIG_FOLDER" ]; then
            docker-compose -p verifier$i -f "$CONFIG_FOLDER/docker-compose.yml" down
            docker-compose -p verifier$i -f "$CONFIG_FOLDER/docker-compose.yml" up -d
            info "The verifier$i container has been restarted"
        else
            warning "Folder $CONFIG_FOLDER not found, skipping..."
        fi
    done
    return 0
}

# Function to check node logs
check_node_logs() {
    return 0
}

# Function to update node
update_node() {
    return 0
}

# Function to delete containers
delete_node() {
    warning "Are you sure you want to delete all containers? (y/n)"
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        title "Stopping containers..."
        stop_node
        info "All containers have been stopped."
        title "Deleting containers..."
        rm -rf "$BASE_FOLDER"
        info "All containers have been deleted."
    else
        warning "Deletion cancelled."
    fi
    return 0
}

#

# Menu

while true
do

    PS3='Select an action for Cysic verifier (docker): '
    options=(
        "Install nodes"
        "Start nodes"
        "Stop nodes"
        "Restart nodes"
        "Check nodes logs"
        "Update nodes"
        "Delete nodes"
        "Exit"
    )

    select opt in "${options[@]}"
    do
        case $opt in
            "Install nodes")
                install_node
                break
                ;;
            "Start nodes")
                start_node
                break
                ;;
            "Stop nodes")
                stop_node
                break
                ;;
            "Restart nodes")
                restart_node
                break
                ;;
            "Check nodes logs")
                check_node_logs
                break
                ;;
            "Update nodes")
                update_node
                break
                ;;
            "Delete nodes")
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