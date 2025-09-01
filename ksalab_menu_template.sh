#!/bin/bash

# Set the version variable
NAME=""
BIN_VER=""

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
    cd $HOME
    text_box "TITLE" "Installing node ${NAME}..."



    text_box "DONE" "${NAME} installed successfully."
    return 0
}

# Function to restart node
restart_node() {
    text_box "TITLE" "Restart node ${NAME}..."



    text_box "DONE" "${NAME} restarted successfully."
    return 0
}

# Function to stop node
stop_node() {
    text_box "TITLE" "Stop ${NAME}..."



    text_box "DONE" "${NAME} stopped successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    text_box "TITLE" "Checking node logs for ${NAME}..."


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