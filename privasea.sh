#!/bin/bash

# Set the version variable
VER="Privanetix "

# Export the version variable to make it available in the sourced script
export VER
# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "Failed to load utility script!"
    exit 1
fi

#

# Function to install node
install_node() {
    if ! check_docker_installed; then
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi

    # Ensure the script is run as root

    if [ "$EUID" -ne 0 ]; then
        error "Please run this script as root (sudo)."
        exit 1
    fi

    info "Installing node..."

    # Update packages and Install dependencies
    title "Updating system and installing build tools..."
    sudo apt update && sudo apt upgrade -y
    sudo apt -qy install curl git jq lz4 build-essential ca-certificates -y
    info "System updated and build tools installed successfully."

    # Docker download

    title "Downloading Docker image..."
    cd
    docker pull privasea/acceleration-node-beta
    info "Docker image downloaded successfully."

    # Create the program running directory and navigate to it:
    title "Creating folder ~/privasea..."
    mkdir -p  $HOME/privasea/config && cd  /privasea

    # Run docker command to generate keystore
    title "Generating keystore..."

    # Create a temporary file to capture the output
    TEMP_FILE=$(mktemp)

    # Run the docker command and capture the output to both the terminal and the temp file
    docker run -it -v "$HOME/privasea/config:/app/config" privasea/acceleration-node-beta:latest ./node-calc new_keystore 2>&1 | tee "$TEMP_FILE"

    # Extract the UTC-- string from the output
    UTC_STRING=$(grep -oP 'UTC--\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.\d+Z--\w+' "$TEMP_FILE")

    if [ -z "$UTC_STRING" ]; then
        error "Failed to extract UTC string from the output."
        rm "$TEMP_FILE"
        return 1
    fi

    info "Extracted UTC string: $UTC_STRING"

    # Define the source and destination paths
    SOURCE_PATH="$HOME/privasea/config/$UTC_STRING"
    DESTINATION_PATH="$HOME/privasea/config/wallet_keystore"

    # Rename the file
    title "Renaming file to wallet_keystore..."
    sudo mv "$SOURCE_PATH" "$DESTINATION_PATH" || { error "Failed to rename file"; rm "$TEMP_FILE"; exit 1; }
    info "File renamed successfully to wallet_keystore."

    # Clean up the temporary file
    rm "$TEMP_FILE"

    #Check that the wallet_keystore file in the $HOME/privasea/config folder was modified correctly:
    ls

    cd

    info "Node installed successfully."
    return 0
}

# Run node
run_node() {
    info "Running node..."

    # Switch to the program running directory
    title "Switching to the program running directory..."
    cd $HOME/privasea/ || { error "Failed to switch to /privasea/ directory"; return 1; }

    # Request keystore password from the user
    while true; do
        warning "Enter the keystore password (or press Ctrl+C to cancel):"
        read -sp "Keystore Password: " KEYSTORE_PASSWORD
        echo
        
        # Check if the password is empty
        if [ -z "$KEYSTORE_PASSWORD" ]; then
            error "Keystore password cannot be empty. Please try again."
        else
            break
        fi
    done

    # Run the compute node command:
    title "Starting the compute node..."
    docker run -d \
        -v "$HOME/privasea/config:/app/config" \
        -e KEYSTORE_PASSWORD="$KEYSTORE_PASSWORD" \
        --name privasea \
        privasea/acceleration-node-beta:latest || { error "Failed to start the node"; return 1; }

    info "The node has been successfully started..."
    return 0
}

# Stop node
stop_node() {
    info "Stopping node..."
    
    # Check if the container exists
    if ! docker ps -a --filter "name=privasea" -q | grep -q .; then
        warning "Container 'privasea' not found. Returning to menu..."
        return 1
    fi
    
    # Stop the container
    docker stop privasea || { error "Failed to stop the node"; return 1; }
    docker rm privasea || { error "Failed to remove the node"; return 1; }
    
    info "The node has been successfully stopped."
    return 0
}

# Function to check node logs
check_node_logs() {
    info "Checking node logs..."
    
    # Check if the container exists
    if ! docker ps -a --filter "name=privasea" -q | grep -q .; then
        warning "Container 'privasea' not found. Returning to menu..."
        return 1
    fi
    
    # Display logs
    docker logs -f privasea || { error "Failed to retrieve logs"; return 1; }
    
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

    # Ensure the script is run as root
    if [ "$EUID" -ne 0 ]; then
        error "Please run this script as root (sudo)."
        exit 1
    fi

    info "Updating node..."

    # Stop and remove the existing container
    title "Stopping and removing the existing container..."
    if docker ps -a --filter "name=privasea" -q | grep -q .; then
        docker stop privasea || { error "Failed to stop Docker container 'privasea'"; return 1; }
        docker rm privasea || { error "Failed to remove Docker container 'privasea'"; return 1; }
        info "Existing Docker container stopped and removed successfully."
    else
        warning "No existing Docker container found."
    fi

    # Remove old unused Docker images
    title "Removing old unused Docker images..."
    old_images=$(docker images --format "{{.Repository}} {{.ID}}" | grep privasea | awk '{print $2}')
    if [ -n "$old_images" ]; then
        echo "$old_images" | xargs docker rmi || { error "Failed to remove old unused Docker images"; return 1; }
        info "Old unused Docker images removed successfully."
    else
        warning "No old unused Docker images found."
    fi

    # Prune unused Docker images
    title "Pruning unused Docker images..."
    docker system prune -f || { error "Failed to prune unused Docker images"; return 1; }
    info "Unused Docker images pruned successfully."

    # Download the latest Docker image
    title "Downloading the latest Docker image..."
    cd
    docker pull privasea/acceleration-node-beta || { error "Failed to pull Docker image"; exit 1; }
    info "Docker image downloaded successfully."

    # # Generate a new keystore (optional)
    # warning "Do you want to generate a new keystore? (y/n)"
    # read -r generate_keystore
    # if [[ "$generate_keystore" =~ ^[Yy]$ ]]; then
    #     title "Generating keystore..."
    #     # Create a temporary file to capture the output
    #     TEMP_FILE=$(mktemp)
    #     # Run the docker command and capture the output to both the terminal and the temp file
    #     docker run -it -v "$HOME/privasea/config:/app/config" privasea/acceleration-node-beta:latest ./node-calc new_keystore 2>&1 | tee "$TEMP_FILE"
    #     # Extract the UTC-- string from the output
    #     UTC_STRING=$(grep -oP 'UTC--\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.\d+Z--\w+' "$TEMP_FILE")
    #     if [ -z "$UTC_STRING" ]; then
    #         error "Failed to extract UTC string from the output."
    #         rm "$TEMP_FILE"
    #         return 1
    #     fi
    #     info "Extracted UTC string: $UTC_STRING"
    #     # Define the source and destination paths
    #     SOURCE_PATH="$HOME/privasea/config/$UTC_STRING"
    #     DESTINATION_PATH="$HOME/privasea/config/wallet_keystore"
    #     # Rename the file
    #     title "Renaming file to wallet_keystore..."
    #     sudo mv "$SOURCE_PATH" "$DESTINATION_PATH" || { error "Failed to rename file"; rm "$TEMP_FILE"; exit 1; }
    #     info "File renamed successfully to wallet_keystore."
    #     # Clean up the temporary file
    #     rm "$TEMP_FILE"
    # fi

    # Start the new Docker container
    title "Starting the new Docker container..."
    docker run -d \
        -v "$HOME/privasea/config:/app/config" \
        -e KEYSTORE_PASSWORD="$KEYSTORE_PASSWORD" \
        --name privasea \
        privasea/acceleration-node-beta:latest || { error "Failed to start the node"; return 1; }
    info "Node updated successfully."
    return 0
}

# Function to delete node
delete_node() {
    info "Deleting node..."
    
    # Confirm deletion
    warning "Are you sure you want to delete the node? This action cannot be undone. (y/n)"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        warning "Deletion canceled. Returning to menu..."
        return 1
    fi
    
    # Stop and remove the container
    title "Stopping and removing the Docker container..."
    if docker ps -a --filter "name=privasea" -q | grep -q .; then
        docker stop privasea || { error "Failed to stop Docker container 'privasea'"; return 1; }
        docker rm privasea || { error "Failed to remove Docker container 'privasea'"; return 1; }
        info "Docker container stopped and removed successfully."
    else
        warning "No Docker container found."
    fi
    
    # Remove Docker image
    title "Removing Docker image..."
    docker rmi privasea/acceleration-node-beta || { error "Failed to remove Docker image"; return 1; }
    info "Docker image removed successfully."
    
    # Remove configuration files and directories
    title "Removing configuration files and directories..."
    sudo rm -rf "$HOME/privasea" || { error "Failed to remove configuration files and directories"; return 1; }
    info "Configuration files and directories removed successfully."
    
    info "Node deleted successfully."
    return 0
}

#

# Menu

while true
do

    PS3='Select an action for Privanetix node: '
    options=(
        "Install node"
        "Run node"
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
            "Run node")
                run_node
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