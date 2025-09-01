#!/bin/bash

# Set the version variable
VER="Pipe v0.1.3 (DevNet 1)"

# Export the version variable to make it available in the sourced script
export VER
# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "Failed to load utility script!"
    exit 1
fi

#

# Allowed characters for password generation

PASSWORD_CHARS='A-Za-z0-9!@#$%^_=+?.,'

# Variables (default values are empty)

PIPE_URL="https://ksalab.xyz/dl/pipe-tool"
DCDND_URL="https://ksalab.xyz/dl/dcdnd"
DEFAULT_GRPC_PORT=8002
DEFAULT_HTTP_PORT=8003

# Ensure the script is run as root

if [ "$EUID" -ne 0 ]; then
    error "Please run this script as root (sudo)."
    exit 1
fi

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
    info "Installing node..."
    cd

    # Step 1: Ask for download URLs if not provided

    if [ -z "$PIPE_URL" ]; then
        while [ -z "$PIPE_URL" ]; do
            info "Please enter the URL for pipe-tool (PIPE_URL):"
            read -r PIPE_URL
            if [ -z "$PIPE_URL" ]; then
                error "PIPE_URL cannot be empty. Please provide a valid URL."
            fi
        done
    fi

    if [ -z "$DCDND_URL" ]; then
        while [ -z "$DCDND_URL" ]; do
            info "Please enter the URL for dcdnd (DCDND_URL):"
            read -r DCDND_URL
            if [ -z "$DCDND_URL" ]; then
                error "DCDND_URL cannot be empty. Please provide a valid URL."
            fi
        done
    fi

    # Step 2: Check and set ports

    title "Checking if default ports are available..."
    GRPC_PORT=$DEFAULT_GRPC_PORT
    HTTP_PORT=$DEFAULT_HTTP_PORT

    if check_port_usage "$GRPC_PORT"; then
        error "Port $GRPC_PORT is in use. Please enter a new gRPC port:"
        read -r GRPC_PORT
        while check_port_usage "$GRPC_PORT"; do
            error "Port $GRPC_PORT is still in use. Please enter a different gRPC port:"
            read -r GRPC_PORT
        done
    fi

    if check_port_usage "$HTTP_PORT"; then
        error "Port $HTTP_PORT is in use. Please enter a new HTTP port:"
        read -r HTTP_PORT
        while check_port_usage "$HTTP_PORT"; do
            error "Port $HTTP_PORT is still in use. Please enter a different HTTP port:"
            read -r HTTP_PORT
        done
    fi

    # Step 3: Open necessary ports using UFW

    title "Opening required ports..."
    sudo ufw allow "$GRPC_PORT"/tcp || { error "Failed to open port $GRPC_PORT"; exit 1; }
    sudo ufw allow "$HTTP_PORT"/tcp || { error "Failed to open port $HTTP_PORT"; exit 1; }
    sudo ufw reload || { error "Failed to reload UFW"; exit 1; }
    info "Required ports ($GRPC_PORT, $HTTP_PORT) opened successfully."

    # Step 4: Create the installation directory

    title "Creating installation directory..."
    sudo mkdir -p /opt/dcdn || { error "Failed to create installation directory"; exit 1; }
    info "Installation directory created successfully."

    # Step 5: Download binaries

    title "Downloading pipe-tool binary..."
    sudo curl -L "$PIPE_URL" -o /opt/dcdn/pipe-tool || { error "Failed to download pipe-tool binary"; exit 1; }
    info "pipe-tool binary downloaded successfully."

    title "Downloading dcdnd binary..."
    sudo curl -L "$DCDND_URL" -o /opt/dcdn/dcdnd || { error "Failed to download dcdnd binary"; exit 1; }
    info "dcdnd binary downloaded successfully."

    # Step 6: Make binaries executable

    title "Making binaries executable..."
    sudo chmod +x /opt/dcdn/pipe-tool || { error "Failed to make pipe-tool executable"; exit 1; }
    sudo chmod +x /opt/dcdn/dcdnd || { error "Failed to make dcdnd executable"; exit 1; }
    info "Binaries made executable successfully."

    # Step 7: Log in to generate Access Token

    title "Logging in to generate Access Token..."
    /opt/dcdn/pipe-tool login --node-registry-url="https://rpc.pipedev.network" || { error "Failed to log in to Pipe Network"; exit 1; }
    info "Access Token generated successfully."

    # Step 8: Generate Registration Token

    title "Generating Registration Token..."
    /opt/dcdn/pipe-tool generate-registration-token --node-registry-url="https://rpc.pipedev.network" || { error "Failed to generate Registration Token"; exit 1; }
    info "Registration Token generated successfully."

    # Step 9: Create systemd service for dcdnd

    title "Creating systemd service for dcdnd..."
    sudo tee /etc/systemd/system/dcdnd.service > /dev/null << EOF
[Unit]
Description=DCDN Node Service
After=network.target
Wants=network-online.target

[Service]
# Path to the executable and its arguments
ExecStart=/opt/dcdn/dcdnd \
    --grpc-server-url=0.0.0.0:$GRPC_PORT \
    --http-server-url=0.0.0.0:$HTTP_PORT \
    --node-registry-url="https://rpc.pipedev.network" \
    --cache-max-capacity-mb=1024 \
    --credentials-dir=/root/.permissionless \
    --allow-origin=* \
    --log-level=info

# Restart policy
Restart=always
RestartSec=5

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dcdn-node

# Working directory
WorkingDirectory=/opt/dcdn

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        error "Error when creating service file!"
        exit 1
    fi
    info "Systemd service created successfully."

    # Step 10: Reload systemd, enable and start the service

    title "Reloading systemd and starting the service..."
    sudo systemctl daemon-reload || { error "Failed to reload systemd daemon"; exit 1; }
    sudo systemctl enable dcdnd.service || { error "Failed to enable dcdnd service"; exit 1; }
    sudo systemctl start dcdnd.service || { error "Failed to start dcdnd service"; exit 1; }
    info "dcdnd service started successfully."

    # Step 11: Display the status of the dcdnd service

    # title "Checking the service status..."
    # sudo systemctl status dcdnd.service || { error "Failed to check service status"; exit 1; }
    # info "Service status checked successfully."

    # Step 12: Request or generate password

    while true; do
        info "Choose an option for the password:"
        echo -e "  1) Enter a custom password"
        echo -e "  2) Generate a random password"
        info "Enter your choice (1 or 2):"
        read -r PASSWORD_CHOICE

        if [ "$PASSWORD_CHOICE" == "2" ]; then
            PASSWORD=$(generate_password)
            info "Generated password: ${BLUE}$PASSWORD${RESET}"
            info "Please confirm you have saved the password by typing 'yes':"
            read -r CONFIRM
            if [ "$CONFIRM" == "yes" ]; then
                break
            else
                error "You did not confirm saving the password. Restarting the choice."
            fi
        elif [ "$PASSWORD_CHOICE" == "1" ]; then
            break
            # while true; do
            #     info "Please enter a password that meets the requirements (16 characters, uppercase, lowercase, numbers, and special characters):"
            #     read -r PASSWORD
            #     if validate_password "$PASSWORD"; then
            #         break
            #     else
            #         error "Password does not meet the requirements. Restarting the choice."
            #     fi
            # done
        else
            error "Invalid choice. Please try again."
        fi
    done

    # Step 13: Set the generated password

    # title "Setting the password..."
    # /opt/dcdn/pipe-tool set-password "$PASSWORD" --credentials-dir=/root/.permissionless || { error "Failed to set password"; exit 1; }
    # info "Password set successfully."

    # Step 14: Generate and register wallet

    title "Generating and registering a wallet..."
    # Redirect input to avoid interactive prompts
    echo -e "q\n" | /opt/dcdn/pipe-tool generate-wallet --node-registry-url="https://rpc.pipedev.network" || { error "Failed to generate and register wallet"; exit 1; }
    info "Wallet generated and registered successfully."
    info "Node installed successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    title "Checking node logs..."
    sudo journalctl -fu dcdnd -o cat --no-hostname
    return 0
}

# Function to update node
update_node() {
    info "Updating node..."
    if [ -z "$PIPE_URL" ]; then
        while [ -z "$PIPE_URL" ]; do
            echo -e "\n${GREEN}- Please enter the URL for pipe-tool (PIPE_URL):${RESET}\n"
            read -r PIPE_URL
            if [ -z "$PIPE_URL" ]; then
                echo -e "${RED}! PIPE_URL cannot be empty. Please provide a valid URL.${RESET}\n"
            fi
        done
    fi

    if [ -z "$DCDND_URL" ]; then
        while [ -z "$DCDND_URL" ]; do
            echo -e "\n${GREEN}- Please enter the URL for dcdnd (DCDND_URL):${RESET}\n"
            read -r DCDND_URL
            if [ -z "$DCDND_URL" ]; then
                echo -e "${RED}! DCDND_URL cannot be empty. Please provide a valid URL.${RESET}\n"
            fi
        done
    fi

    # Step 2: Stop DCDND process

    title "Stopping the dcdnd process..."
    sudo systemctl stop dcdnd.service || { error "Failed to stop dcdnd service"; exit 1; }
    info "dcdnd service stopped successfully."

    # Step 3: Remove files pipe-tool and dcdnd

    title "Removing old files pipe-tool and dcdnd..."
    sudo rm -f /opt/dcdn/pipe-tool || { error "Failed to remove pipe-tool"; exit 1; }
    sudo rm -f /opt/dcdn/dcdnd || { error "Failed to remove dcdnd"; exit 1; }
    info "Files removed successfully."

    # Step 4: Create the installation directory if it doesn't exist

    title "Creating installation directory /opt/dcdn if it doesn't exist..."
    sudo mkdir -p /opt/dcdn || { error "Failed to create installation directory"; exit 1; }
    info "Installation directory created successfully."

    # Step 5: Download binaries

    title "Downloading new pipe-tool binary..."
    sudo curl -L "$PIPE_URL" -o /opt/dcdn/pipe-tool || { error "Failed to download pipe-tool binary"; exit 1; }
    info "pipe-tool binary downloaded successfully."

    title "Downloading new dcdnd binary..."
    sudo curl -L "$DCDND_URL" -o /opt/dcdn/dcdnd || { error "Failed to download dcdnd binary"; exit 1; }
    info "dcdnd binary downloaded successfully."

    # Step 6: Make binaries executable

    title "Making binaries executable..."
    sudo chmod +x /opt/dcdn/pipe-tool || { error "Failed to make pipe-tool executable"; exit 1; }
    sudo chmod +x /opt/dcdn/dcdnd || { error "Failed to make dcdnd executable"; exit 1; }
    info "Binaries made executable successfully."

    # Step 7: Reload systemd, enable and start the service

    title "Reloading systemd and starting the service..."
    sudo systemctl daemon-reload || { error "Failed to reload systemd daemon"; exit 1; }
    sudo systemctl enable dcdnd.service || { error "Failed to enable dcdnd service"; exit 1; }
    sudo systemctl restart dcdnd.service || { error "Failed to restart dcdnd service"; exit 1; }
    info "dcdnd service started successfully."

    # Step 8: Display the status of the dcdnd service

    # title "Checking the service status..."
    # sudo systemctl status dcdnd.service || { error "Failed to check service status"; exit 1; }
    # info "Service status checked successfully."

    # Step 9: Log in to Pipe Network

    title "Logging in to Pipe Network..."
    /opt/dcdn/pipe-tool login --node-registry-url="https://rpc.pipedev.network" || { error "Failed to log in to Pipe Network"; exit 1; }
    info "Logged in to Pipe Network successfully."

    info "Node updated successfully."
    return 0
}

# Function to delete node
delete_node() {
    warning "Make sure you back up your node data ($HOME/.permissionless folder) before continuing.\n"
    warning "Yeah, I backed it up: (y/n)"
    read -r backup
    if [[ "$backup" =~ ^[Yy]$ ]]; then
        info "It's backed up. Continued..."
    else
        error "The backup has not been saved. Back to the menu......"
        return 1
    fi

    info "Deleting node..."

    # Stop and remove Pipe Network node service
    title "Stopping and disabling the dcdnd process..."
    sudo systemctl stop dcdnd.service || { error "Failed to stop dcdnd service"; exit 1; }
    sudo systemctl disable dcdnd.service || { error "Failed to disable dcdnd service"; exit 1; }
    info "dcdnd service stopped and disabled successfully."

    title "Removing the dcdnd process..."
    sudo rm /etc/systemd/system/dcdnd.service || { error "Failed to remove dcdnd service"; exit 1; }
    info "dcdnd service removed successfully."

    sudo systemctl daemon-reload

    # Stop and remove Pipe Network node dcdnd binaries
    title "Removing the dcdnd binaries..."
    sudo rm -r /opt/dcdn/dcdnd || { error "Failed to remove dcdnd binaries"; exit 1; }
    info "dcdnd binaries removed successfully."

    # Request user to enter node_id
    node_id=""
    while [ -z "$node_id" ]; do
        warning "To continue, you need to enter the node_id of your node:"
        read -r node_id
        if [ -z "$node_id" ]; then
            error "Node ID cannot be empty. Please try again."
        fi
    done

    # Unregister a node completely (node will no longer appear in 'list-nodes')
    warning "Do you want to delete the node completely (it will be impossible to recover)? If you are migrating the node to a new server, skip this item."
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Check if pipe-tool is installed
        if [ ! -x "/opt/dcdn/pipe-tool" ]; then
            error "pipe-tool is not installed. Cannot decommission the node."
            return 1
        fi

        # Remove the folder containing the tokens
        warning "Removing the folder containing the tokens..."
        sudo rm -r ~/.permissionless || { error "Failed to remove .permissionless folder"; exit 1; }
        info "Folder containing the tokens removed successfully."
        
        # Execute the decommission command
        title "Decommissioning the node..."
        pipe-tool decommission-node --node-registry-url "https://rpc.pipedev.network" --node-id "${node_id}" || { error "Failed to decommission the node"; exit 1; }
        info "Node decommissioned successfully."
    else
        warning "Decommission canceled."
    fi

    # Stop and remove Pipe Network node pipe-tool binaries
    title "Removing the pipe-tool binaries..."
    sudo rm -r /opt/dcdn/pipe-tool || { error "Failed to remove pipe-tool binaries"; exit 1; }
    info "pipe-tool binaries removed successfully."
    
    # Remove the dcdn folder from /opt
    title "Removing the dcdn folder from /opt..."
    sudo rm -r /opt/dcdn || { error "Failed to remove dcdn folder from /opt"; exit 1; }
    info "dcdn folder removed successfully."

    info "Node deleted successfully."
    return 0
}

#

# Menu

while true
do

    PS3='Select an action for Pipe Network: '
    options=(
        "Install node"
        "Check node logs"
        "Update node"
        "Delete node (will need node_id from list-node)"
        "Exit"
    )

    select opt in "${options[@]}"
    do
        case $opt in
            "Install node")
                install_node
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