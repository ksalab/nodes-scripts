#!/bin/bash

# Set the version variable
NAME="0g (ZeroGravity) DA Client Node"
PORT=51001

# envfile.env
COMBINED_SERVER_CHAIN_RPC=https://evmrpc-testnet.0g.ai
COMBINED_SERVER_PRIVATE_KEY=YOUR_PRIVATE_KEY
ENTRANCE_CONTRACT_ADDR=0x857C0A28A8634614BB2C96039Cf4a20AFF709Aa9

COMBINED_SERVER_RECEIPT_POLLING_ROUNDS=180
COMBINED_SERVER_RECEIPT_POLLING_INTERVAL=1s
COMBINED_SERVER_TX_GAS_LIMIT=2000000
COMBINED_SERVER_USE_MEMORY_DB=true
COMBINED_SERVER_KV_DB_PATH=/runtime/
COMBINED_SERVER_TIMETOEXPIRE=2592000
DISPERSER_SERVER_GRPC_PORT=$PORT
BATCHER_DASIGNERS_CONTRACT_ADDRESS=0x0000000000000000000000000000000000001000
BATCHER_FINALIZER_INTERVAL=20s
BATCHER_CONFIRMER_NUM=3
BATCHER_MAX_NUM_RETRIES_PER_BLOB=3
BATCHER_FINALIZED_BLOCK_COUNT=50
BATCHER_BATCH_SIZE_LIMIT=500
BATCHER_ENCODING_INTERVAL=3s
BATCHER_ENCODING_REQUEST_QUEUE_SIZE=1
BATCHER_PULL_INTERVAL=10s
BATCHER_SIGNING_INTERVAL=3s
BATCHER_SIGNED_PULL_INTERVAL=20s
BATCHER_EXPIRATION_POLL_INTERVAL=3600
BATCHER_ENCODER_ADDRESS=http://127.0.0.1:34000
BATCHER_ENCODING_TIMEOUT=300s
BATCHER_SIGNING_TIMEOUT=60s
BATCHER_CHAIN_READ_TIMEOUT=12s
BATCHER_CHAIN_WRITE_TIMEOUT=13s

# Export the version variable to make it available in the sourced script
VER="${NAME} v.latest"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "❌ Failed to load utility script!"
    exit 1
fi

#

# Stop 0g (ZeroGravity) DA Client Node container
stop_container() {
    docker stop 0g-da-client
    docker rm 0g-da-client
}

# Remove old 0g (ZeroGravity) DA Client Node container
remove_old_container() {
    text_box "TITLE" "Removing old unused ${NAME} Docker images..."

    # Get names of images containing 0g-da-client (case-insensitive)
    image_names=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -i '0g-da-client')

    # Remove images containing 0g-da-client
    if [ -n "$image_names" ]; then
        text_box "INFO" "Removing images with name 0g-da-client..."
        docker rmi $image_names 2>/dev/null
    else
        text_box "INFO" "No images with name 0g-da-client."
    fi

    # Check if there are any 0g-da-client images remaining
    remaining_images=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '0g-da-client' | awk '{print $1":"$2}')
    if [ -z "$remaining_images" ]; then
        text_box "INFO" "All 0g-da-client images have been deleted."
    else
        text_box "ERROR" "There are images of 0g-da-client left:"
        docker images --format '{{.Repository}}:{{.Tag}}' | grep '0g-da-client' | awk '{print $1":"$2}'
    fi

    # Prune unused Docker images
    text_box "INFO" "Pruning unused Docker images..."
    docker system prune -f || { text_box "ERROR" "Failed to prune unused Docker images"; exit 1; }
    text_box "DONE" "Unused Docker images pruned successfully."
}

# Function to install node
install_node() {
    cd $HOME
    text_box "TITLE" "Installing node ${NAME}..."

    # Check docker installed...
    check_docker_installed

    text_box "INFO" "Clone the DA Client Node repo..."
    rm -rf 0g-da-client
    git clone https://github.com/0glabs/0g-da-client.git || { text_box "ERROR" "Failed to clone repository"; exit 1; }
    text_box "DONE" "Cloning of DA Client Node repo successful."

    text_box "INFO" "Build the Docker Image..."
    cd 0g-da-client || { text_box "ERROR" "Failed to change directory to 0g-da-node"; exit 1; }
    docker build -t 0g-da-client -f combined.Dockerfile .
    text_box "DONE" "Docker image builded successfully."

    # Request ETH and BLS private keys
    text_box "INFO" "Request ETH private keys..."
    while [ -z "$ETH_PRIVATE_KEY" ]; do
        text_box "INFO" "Enter ETH PRIVATE_KEY: "
        read -r ETH_PRIVATE_KEY
    done

    text_box "INFO" "Create envfile.env..."
    nano envfile.env
    sudo tee $HOME/0g-da-client/envfile.env > /dev/null <<EOF
# envfile.env
COMBINED_SERVER_CHAIN_RPC=$COMBINED_SERVER_CHAIN_RPC
COMBINED_SERVER_PRIVATE_KEY=$ETH_PRIVATE_KEY
ENTRANCE_CONTRACT_ADDR=$ENTRANCE_CONTRACT_ADDR

COMBINED_SERVER_RECEIPT_POLLING_ROUNDS=$COMBINED_SERVER_RECEIPT_POLLING_ROUNDS
COMBINED_SERVER_RECEIPT_POLLING_INTERVAL=$COMBINED_SERVER_RECEIPT_POLLING_INTERVAL
COMBINED_SERVER_TX_GAS_LIMIT=$COMBINED_SERVER_TX_GAS_LIMIT
COMBINED_SERVER_USE_MEMORY_DB=$COMBINED_SERVER_USE_MEMORY_DB
COMBINED_SERVER_KV_DB_PATH=$COMBINED_SERVER_KV_DB_PATH
COMBINED_SERVER_TimeToExpire=$COMBINED_SERVER_TIMETOEXPIRE
DISPERSER_SERVER_GRPC_PORT=$DISPERSER_SERVER_GRPC_PORT
BATCHER_DASIGNERS_CONTRACT_ADDRESS=$BATCHER_DASIGNERS_CONTRACT_ADDRESS
BATCHER_FINALIZER_INTERVAL=$BATCHER_FINALIZER_INTERVAL
BATCHER_CONFIRMER_NUM=$BATCHER_CONFIRMER_NUM
BATCHER_MAX_NUM_RETRIES_PER_BLOB=$BATCHER_MAX_NUM_RETRIES_PER_BLOB
BATCHER_FINALIZED_BLOCK_COUNT=$BATCHER_FINALIZED_BLOCK_COUNT
BATCHER_BATCH_SIZE_LIMIT=$BATCHER_BATCH_SIZE_LIMIT
BATCHER_ENCODING_INTERVAL=$BATCHER_ENCODING_INTERVAL
BATCHER_ENCODING_REQUEST_QUEUE_SIZE=$BATCHER_ENCODING_REQUEST_QUEUE_SIZE
BATCHER_PULL_INTERVAL=$BATCHER_PULL_INTERVAL
BATCHER_SIGNING_INTERVAL=$BATCHER_SIGNING_INTERVAL
BATCHER_SIGNED_PULL_INTERVAL=$BATCHER_SIGNED_PULL_INTERVAL
BATCHER_EXPIRATION_POLL_INTERVAL=$BATCHER_EXPIRATION_POLL_INTERVAL
BATCHER_ENCODER_ADDRESS=$BATCHER_ENCODER_ADDRESS
BATCHER_ENCODING_TIMEOUT=$BATCHER_ENCODING_TIMEOUT
BATCHER_SIGNING_TIMEOUT=$BATCHER_SIGNING_TIMEOUT
BATCHER_CHAIN_READ_TIMEOUT=$BATCHER_CHAIN_READ_TIMEOUT
BATCHER_CHAIN_WRITE_TIMEOUT=$BATCHER_CHAIN_WRITE_TIMEOUT
EOF

    if [ $? -ne 0 ]; then
        text_box "ERROR" "Failed to create envfile.env file" >&2
        exit 1
    fi
    text_box "DONE" "File envfile.env created successfully."

    # Open ports
    text_box "INFO" "Open ports..."
    sudo ufw allow ${PORT}/tcp
    sudo ufw reload
    text_box "DONE" "Port $PORT opened successfully."

    text_box "INFO" "Run node..."
    docker run -d --env-file envfile.env --name 0g-da-client --restart always -v ./run:/runtime -p $PORT:$PORT 0g-da-client combined
    text_box "DONE" "Docker container started successfully."

    text_box "DONE" "${NAME} installed successfully."
    return 0
}

# Function to restart node
restart_node() {
    text_box "TITLE" "Restart docker container for ${NAME}..."
    stop_container
    docker run -d --env-file envfile.env --name 0g-da-client --restart always -v ./run:/runtime -p $PORT:$PORT 0g-da-client combined

    text_box "DONE" "Docker container restarted successfully."
    return 0
}

# Function to stop node
stop_node() {
    text_box "TITLE" "Stop docker container for ${NAME}..."
    stop_container
    text_box "DONE" "Docker container stopped successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    cd $HOME
    text_box "TITLE" "Checking node logs..."
    docker logs -f 0g-da-client
    return 0
}

# Function to update node
update_node() {
    text_box "TITLE" "Updating node ${NAME}..."

    # Stop and remove old ${NAME} Docker container
    text_box "INFO" "Stopping and removing old ${NAME} Docker container..."
    if docker ps -a --filter "name=0g-da-client" -q | grep -q .; then
        stop_container
        text_box "DONE" "Old ${NAME} Docker container stopped and removed successfully."
    else
        text_box "WARNING" "No old ${NAME} Docker container found."
    fi

    # Remove old unused ${NAME} Docker images
    remove_old_container

    # Start new ${NAME} Docker container
    text_box "INFO" "Starting new ${NAME} Docker container..."
    docker run -d --env-file envfile.env --name 0g-da-client --restart always -v ./run:/runtime -p $PORT:$PORT 0g-da-client combined

    text_box "DONE" "Node updated successfully."
    return 0
}

# Function to delete node
delete_node() {
    text_box "TITLE" "Make sure you back up your node data before continuing."
    text_box "WARNING" "Yeah, I backed it up: (y/n)"
    read -r backup
    if [[ "$backup" =~ ^[Yy]$ ]]; then
        text_box "INFO" "It's backed up. Continued..."
    else
        text_box "ERROR" "The backup has not been saved. Back to the menu......"
        return 1
    fi

    text_box "INFO" "Delete ${NAME}..."
    stop_container
    rm -rf $HOME/0g-da-client

    # Remove old unused 0g-da-client Docker images
    remove_old_container

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