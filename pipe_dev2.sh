#!/bin/bash

# Set the version variable
NAME="Pipe CDN PoP Cache Node"
BIN_VER="0.3.0"

# Allowed characters for password generation
PASSWORD_CHARS='A-Za-z0-9!@#$%^_=+?.,'

# Variables (default values are empty)
SERVICE_FILE="/etc/systemd/system/pop.service"
POP_URL="https://ksalab.xyz/dl/pop"
INFO_PORT=8002
GRPC_PORT=8003
HTTP_PORT=80
HTTPS_PORT=443

VER="${NAME} v${BIN_VER} (DevNet 2)"

# Export the version variable to make it available in the sourced script
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

# Ensure the script is run as root

if [ "$EUID" -ne 0 ]; then
    text_box "ERROR" "Please run this script as root (sudo)."
    exit 1
fi

#

# Function to generate a random password

generate_password() {
    tr -dc "$PASSWORD_CHARS" < /dev/urandom | head -c 16
}

# Function to check if a password meets requirements

validate_password() {
    local password=$1
    if [[ "$password" =~ [A-Z] && "$password" =~ [a-z] && "$password" =~ [0-9] && "$password" =~ [!@#$%^_=+?.,] && ${#password} -eq 16 ]]; then
        return 0 # Password is valid
    else
        return 1 # Password is invalid
    fi
}

#

# Function to install node
install_node() {
    text_box "TITLE" "Installing ${NAME} node..."
    cd

    # Step 1: Ask for download URLs if not provided

    if [ -z "$POP_URL" ]; then
        while [ -z "$POP_URL" ]; do
            text_box "INFO" "Please enter the URL for pipe-tool (POP_URL):"
            read -r POP_URL
            if [ -z "$POP_URL" ]; then
                text_box "ERROR" "POP_URL cannot be empty. Please provide a valid URL."
            fi
        done
    fi

    # Step 2: Check and set ports

    # text_box "INFO" "Checking if default ports are available..."

    # for port_var in GRPC_PORT INFO_PORT; do
    #     while check_port_usage "${!port_var}"; do
    #         text_box "WARNING" "Port ${!port_var} is in use. Please enter a new ${port_var/:_PORT/} port:"
    #         read -r "$port_var"
    #     done
    # done

    # for port_var in HTTP_PORT HTTPS_PORT; do
    #     if check_port_usage "${!port_var}"; then
    #         text_box "ERROR" "Port ${!port_var} is already in use. It's impossible to continue. Release the ports ($HTTP_PORT, $HTTPS_PORT) and repeat the installation from the beginning...."
    #         exit 1
    #     fi
    # done

    # Step 3: Open necessary ports using UFW

    text_box "INFO" "Opening required ports..."
    for port in ${GRPC_PORT}/tcp ${INFO_PORT}/tcp ${HTTP_PORT} ${HTTPS_PORT}; do
        sudo ufw allow "$port" || { text_box "ERROR" "Failed to open port $port"; exit 1; }
    done
    sudo ufw reload || { text_box "ERROR" "Failed to reload UFW"; exit 1; }
    text_box "DONE" "Required ports opened successfully."

    # Step 4: Create the installation directory

    text_box "INFO" "Creating installation directory..."
    sudo mkdir -p /opt/dcdn || { text_box "ERROR" "Failed to create /opt/dcdn directory"; exit 1; }
    sudo mkdir -p /opt/dcdn/download_cache || { text_box "ERROR" "Failed to create /opt/dcdn/download_cache directory"; exit 1; }
    text_box "DONE" "Installation directory created successfully."

    # Step 5: Download binaries

    text_box "INFO" "Downloading pop binary..."
    sudo curl -L "$POP_URL" -o /opt/dcdn/pop || { text_box "ERROR" "Failed to download pop binary"; exit 1; }
    text_box "DONE" "pop binary downloaded successfully."

    # Step 6: Make binaries executable

    text_box "INFO" "Making binaries executable..."
    sudo chmod +x /opt/dcdn/pop || { text_box "ERROR" "Failed to make pop executable"; exit 1; }
    text_box "DONE" "Binaries made executable successfully."

    # Step 7: Request public key
    while true; do
        text_box "INFO" "Please enter public key for node..."
        read -r -p "Public key: " PUBLIC_KEY
        if [[ -n "$PUBLIC_KEY" ]]; then
            break
        else
            text_box "ERROR" "Public key cannot be empty. Please try again."
        fi
    done

    # Step 8: Create systemd service for pop

    text_box "INFO" "Creating systemd service for pop..."
    sudo tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=Pipe POP Node Service
After=network.target
Wants=network-online.target

[Service]
User=root
Group=root
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStart=/opt/dcdn/pop \
    --ram=6 \
    --pubKey ${PUBLIC_KEY} \
    --max-disk 50 \
    --enable-80-443 \
    --cache-dir /opt/dcdn/download_cache
Restart=always
RestartSec=5
LimitNOFILE=65536
LimitNPROC=4096
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dcdn-node
WorkingDirectory=/opt/dcdn

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        text_box "ERROR" "Error when creating pop service file!"
        exit 1
    fi
    text_box "DONE" "Systemd pop service created successfully."

    # Step 9: Set config file symlink and pop alias: prevent dup configs/registrations, convenient pop commands.

    text_box "INFO" "Create simlink..."
    ln -sf /opt/dcdn/node_info.json ~/node_info.json
    grep -q "alias pop='cd /opt/dcdn && /opt/dcdn/pop'" ~/.bashrc || echo "alias pop='cd /opt/dcdn && /opt/dcdn/pop'" >> ~/.bashrc && source ~/.bashrc
    text_box "DONE" "Created simlink successfully..."

    # Step 10: Reload systemd, enable and start the service

    text_box "INFO" "Reloading systemd and starting the service..."
    sudo systemctl daemon-reload || { text_box "ERROR" "Failed to reload systemd daemon"; exit 1; }
    sudo systemctl enable pop.service || { text_box "ERROR" "Failed to enable pop service"; exit 1; }
    sudo systemctl start pop.service || { text_box "ERROR" "Failed to start pop service"; exit 1; }
    text_box "DONE" "pop service started successfully."

    # Step 11: Display the status of the pop service

    # title "Checking the pop service status..."
    # sudo systemctl status pop.service || { error "Failed to check pop service status"; exit 1; }
    # info "Pop service status checked successfully."

    text_box "DONE" "Node ${NAME} installed successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    text_box "TITLE" "Checking ${NAME} node logs..."
    sudo journalctl -fu pop -o cat --no-hostname
    return 0
}

# Function to check node stats
check_node_stats() {
    text_box "TITLE" "Checking ${NAME} node stats..."
    cd /opt/dcdn
    ./pop --status
    ./pop --stats
    ./pop --points
    cd
    return 0
}

# Function to update node
update_node() {
    text_box "TITLE" "Updating ${NAME} node..."
    if [ -z "$POP_URL" ]; then
        while [ -z "$POP_URL" ]; do
            echo -e "\n${GREEN}- Please enter the URL for pop (POP_URL):${RESET}\n"
            read -r POP_URL
            if [ -z "$POP_URL" ]; then
                echo -e "${RED}! POP_URL cannot be empty. Please provide a valid URL.${RESET}\n"
            fi
        done
    fi

    # Step 2: Stop POP process
    text_box "INFO" "Stopping the pop process..."
    sudo systemctl stop pop.service || { text_box "ERROR" "Failed to stop pop service"; exit 1; }
    text_box "DONE" "pop service stopped successfully."

    # Step 3: Remove files pipe-tool and dcdnd
    text_box "INFO" "Removing old files pop..."
    sudo rm -f /opt/dcdn/pop || { text_box "ERROR" "Failed to remove pop"; exit 1; }
    # sudo rm -f /opt/dcdn/download_cache || { error "Failed to remove /opt/dcdn/download_cache"; exit 1; }
    text_box "DONE" "Old files removed successfully."

    # Step 4: Edit service (only for v0.2.6 !!!)
    text_box "INFO" "Edit service for v0.2.6..."
    if ! grep -q -- "AmbientCapabilities=CAP_NET_BIND_SERVICE" "$SERVICE_FILE"; then
        # If no, added before Restart=always
        sed -i "/^\[Service\]/,/^\[/{s|^\(Restart=always\)|AmbientCapabilities=CAP_NET_BIND_SERVICE\n\1|}" "$SERVICE_FILE"
        text_box "INFO" "Added string 'AmbientCapabilities=CAP_NET_BIND_SERVICE' in $SERVICE_FILE"
    fi

    if ! grep -q -- "CapabilityBoundingSet=CAP_NET_BIND_SERVICE" "$SERVICE_FILE"; then
        # If no, added before Restart=always
        sed -i "/^\[Service\]/,/^\[/{s|^\(Restart=always\)|CapabilityBoundingSet=CAP_NET_BIND_SERVICE\n\1|}" "$SERVICE_FILE"
        text_box "INFO" "Added string 'CapabilityBoundingSet=CAP_NET_BIND_SERVICE' in $SERVICE_FILE"
    fi

    # Step 4a: Edit service (only for v0.2.7 v0.2.8 !!!)
    text_box "INFO" "Edit service for v0.2.7-0.2.8..."
    if ! grep -q -- "--enable-80-443" "$SERVICE_FILE"; then
        # If no, added before --cache-dir
        sed -i "s|--cache-dir /opt/dcdn/download_cache|--enable-80-443 --cache-dir /opt/dcdn/download_cache|" "$SERVICE_FILE"
        info "Added string '--enable-80-443' in $SERVICE_FILE"
    else
        text_box "WARNING" "String '--enable-80-443' already exists in $SERVICE_FILE. No change."
    fi

    text_box "DONE" "Service edited successfully."

    # Step 5: Download binaries
    text_box "INFO" "Downloading new pop binary..."
    sudo curl -L "$POP_URL" -o /opt/dcdn/pop || { text_box "ERROR" "Failed to download pop binary"; exit 1; }
    text_box "DONE" "pop binary downloaded successfully."

    # Step 6: Make binaries executable
    text_box "INFO" "Making binaries executable..."
    sudo chmod +x /opt/dcdn/pop || { text_box "ERROR" "Failed to make pop executable"; exit 1; }
    text_box "DONE" "Binaries made executable successfully."

    # Step 7: Open necessary ports using UFW
    text_box "INFO" "Opening required ports..."
    sudo ufw allow "$HTTPS_PORT"/tcp || { text_box "ERROR" "Failed to open port $HTTPS_PORT"; exit 1; }
    sudo ufw allow "$HTTP_PORT"/tcp || { text_box "ERROR" "Failed to open port $HTTP_PORT"; exit 1; }
    sudo ufw reload || { text_box "ERROR" "Failed to reload UFW"; exit 1; }
    text_box "DONE" "Required ports ($HTTPS_PORT, $HTTP_PORT) opened successfully."

    # Step 8: Reload systemd, enable and start the service
    text_box "INFO" "Reloading systemd and starting the service..."
    sudo systemctl daemon-reload || { text_box "ERROR" "Failed to reload systemd daemon"; exit 1; }
    #sudo systemctl enable pop.service || { error "Failed to enable pop service"; exit 1; }
    sudo systemctl restart pop.service || { text_box "ERROR" "Failed to restart pop service"; exit 1; }
    text_box "DONE" "pop service started successfully."

    /opt/dcdn/pop --version

    # Step 9: Display the log of the pop service
    #title "Checking the service log..."
    #sudo journalctl -u pop -f --no-hostname -o cat || { error "Failed to check service log"; exit 1; }
    #info "Service log checked successfully."

    text_box "DONE" "Node updated successfully."
    exit 0
}

# Function to delete node
delete_node() {
    text_box "TITLE" "Deleting ${NAME} node..."
    text_box "WARNING" "Make sure you back up your node data ($HOME/.permissionless folder) before continuing.\nYeah, I backed it up: (y/n)"
    read -r backup
    if [[ "$backup" =~ ^[Yy]$ ]]; then
        text_box "INFO" "It's backed up. Continued..."
    else
        text_box "ERROR" "The backup has not been saved. Back to the menu......"
        return 1
    fi

    # Stop and remove Pipe Network node service
    text_box "INFO" "Stopping and disabling the pop process..."
    sudo systemctl stop pop.service || { text_box "ERROR" "Failed to stop pop service"; exit 1; }
    sudo systemctl disable pop.service || { text_box "ERROR" "Failed to disable pop service"; exit 1; }
    text_box "DONE" "pop service stopped and disabled successfully."

    text_box "INFO" "Removing the pop process..."
    sudo rm /etc/systemd/system/pop.service || { text_box "ERROR" "Failed to remove pop service"; exit 1; }
    text_box "DONE" "pop service removed successfully."

    sudo systemctl daemon-reload

    # Stop and remove Pipe Network node dcdnd binaries
    text_box "INFO" "Removing the pop binaries..."
    sudo rm -r /opt/dcdn/pop || { text_box "ERROR" "Failed to remove pop binaries"; exit 1; }
    text_box "DONE" "pop binaries removed successfully."

    # Request user to enter node_id
    node_id=""
    while [ -z "$node_id" ]; do
        text_box "WARNING" "To continue, you need to enter the node_id of your node:"
        read -r node_id
        if [ -z "$node_id" ]; then
            text_box "ERROR" "Node ID cannot be empty. Please try again."
        fi
    done

    # Delete a node completely
    text_box "WARNING" "Do you want to delete the node completely (it will be impossible to recover)? If you are migrating the node to a new server, skip this item."
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Check if pop is installed
        if [ ! -x "/opt/dcdn/pop" ]; then
            text_box "ERROR" "pop is not installed. Cannot decommission the node."
            return 1
        fi

        # Remove the folder containing the tokens
        text_box "WARNING" "Removing the folder containing the tokens..."
        sudo rm -r ~/.permissionless || { text_box "ERROR" "Failed to remove .permissionless folder"; exit 1; }
        text_box "DONE" "Folder containing the tokens removed successfully."
    else
        text_box "WARNING" "Delete canceled."
    fi

    # Stop and remove Pipe Network node pop binaries
    text_box "INFO" "Removing the pop binaries..."
    sudo rm -r /opt/dcdn/pop || { text_box "ERROR" "Failed to remove pop binaries"; exit 1; }
    text_box "DONE" "pop binaries removed successfully."

    # Remove the dcdn folder from /opt
    text_box "INFO" "Removing the dcdn folder from /opt..."
    sudo rm -r /opt/dcdn || { text_box "ERROR" "Failed to remove dcdn folder from /opt"; exit 1; }
    text_box "DONE" "dcdn folder removed successfully."

    text_box "DONE" " ${NAME} node deleted successfully."
    return 0
}

#

# Main function to run the script inside tmux
#main() {
#    info "Running script inside tmux session 'pipe'..."
#    # Stop and disable Pipe Network node for DevNet 1
#    title "Stop and disable Pipe Network node for DevNet 1..."
#    sudo systemctl stop dcdnd.service || { error "Failed to stop dcdnd service"; exit 1; }
#    sudo systemctl disable dcdnd.service || { error "Failed to disable dcdnd service"; exit 1; }
#    info "Stopped and disabled Pipe Network node for DevNet 1 successfully..."
#    # Remove old session tmux for Pipe Network DevNet 1
#    title "Remove old session tmux for Pipe Network DevNet 1..."
#    if tmux has-session -t pipe 2>/dev/null; then
#        tmux kill-session -t pipe
#        info "Session tmux 'pipe' deleted successfully."
#    else
#        warning "Session tmux 'pipe' not found."
#    fi
#    # Create new session tmux for Pipe Network DevNet 2
#    title "Create new session tmux for Pipe Network DevNet 2..."
#    tmux new -d -s pipe || { error "Failed to create new tmux session 'pipe'"; exit 1; }
#    tmux send-keys -t pipe "bash <(curl -s https://ksalab.xyz/dl/pipe_dev2.sh) inner" C-m || { error "Failed to send command to tmux session 'pipe'"; exit 1; }
#    tmux attach -t pipe || { error "Failed to attach to tmux session 'pipe'"; exit 1; }
#    info "Attached to new session tmux for Pipe Network DevNet 2 successfully..."
#}

# Menu

# Menu options mapping
declare -A ACTIONS=(
    [1]=install_node
    [2]=check_node_logs
    [3]=check_node_stats
    [4]=update_node
    [5]=delete_node
    [6]=exit
)

# If the run= parameter is passed, execute the desired item
if [[ -n "$RUN_OPTION" && "$RUN_OPTION" =~ ^[1-6]$ ]]; then
    "${ACTIONS[$RUN_OPTION]}"
    exit 0
fi

#inner() {
while true
do
    PS3="Select an action for ${NAME}: "
    options=(
        "Install node"
        "Check node logs"
        "Check node stats"
        "Update node"
        "Delete node"
        "Exit"
    )

    select opt in "${options[@]}"; do
        case $REPLY in
            1|2|3|4|5|6) "${ACTIONS[$REPLY]}"; break ;;
            *) text_box "ERROR" "Invalid option $REPLY" ;;
        esac
    done
done
#}


# Check if the script is being run inside tmux session 'pipe'
#if [ "$1" == "inner" ]; then
#    inner
#else
#    main
#fi
