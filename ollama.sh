#!/bin/bash

# Set the version variable
VER="Ollama:latest"

# Export the version variable to make it available in the sourced script
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "Failed to load utility script!"
    exit 1
fi

#

# Function to install
install_node() {
    title "Ollama setup..."

    title "Download and extract the package..."
    curl -L https://ollama.com/download/ollama-linux-amd64.tgz -o ollama-linux-amd64.tgz
    info "Download the package successfully..."
    sudo tar -C /usr/local -xzf ollama-linux-amd64.tgz
    info "Extract the package successfully..."

    if ! id ollama >/dev/null 2>&1; then
        title "Creating ollama user..."
        sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
    fi
    if getent group render >/dev/null 2>&1; then
        title "Adding ollama user to render group..."
        sudo usermod -a -G render ollama
    fi
    if getent group video >/dev/null 2>&1; then
        title "Adding ollama user to video group..."
        sudo usermod -a -G video ollama
    fi

    print_message "Adding current user to ollama group..."
    sudo usermod -a -G ollama $(whoami)

    status "Creating ollama systemd service..."
    cat <<EOF | sudo tee /etc/systemd/system/ollama.service >/dev/null
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=$PATH"

[Install]
WantedBy=default.target
EOF

    if [ $? -ne 0 ]; then
        error "Error when creating ollama service file!"
        exit 1
    fi
    info "Systemd ollama service created successfully."

    title "Reloading systemd and starting the service..."
    sudo systemctl daemon-reload || { error "Failed to reload systemd daemon"; exit 1; }
    sudo systemctl enable ollama.service || { error "Failed to enable ollama service"; exit 1; }
    sudo systemctl start ollama.service || { error "Failed to start ollama service"; exit 1; }
    info "Ollama service started successfully."

    info "Ollama installed successfully."
    return 0
}

# Function to restart
restart_node() {
    title "Restart ollama service..."
    sudo systemctl restart ollama.service
    info "Ollama service container restarted successfully."
    return 0
}

# Function to stop
stop_node() {
    title "Stop ollama service..."
    sudo systemctl stop ollama.service
    info "Ollama service container stopped successfully."
    return 0
}

# Function to check logs
check_node_logs() {
    title "Ollama setup..."
    journalctl -e -u ollama
    return 0
}

# Function to update
update_node() {
    title "Ollama update..."

    title "Download and extract the new package..."
    curl -L https://ollama.com/download/ollama-linux-amd64.tgz -o ollama-linux-amd64.tgz
    info "Download the new package successfully..."
    sudo tar -C /usr/local -xzf ollama-linux-amd64.tgz
    info "Extract the new package successfully..."

    info "Ollama updated successfully."
    return 0
}

# Function to delete
delete_node() {
    warning "Make sure you back up your data before continuing.\n"
    warning "Yeah, I backed it up: (y/n)"
    read -r backup
    if [[ "$backup" =~ ^[Yy]$ ]]; then
        info "It's backed up. Continued..."
    else
        error "The backup has not been saved. Back to the menu......"
        return 1
    fi

    # Stop and remove Ollama service
    title "Stopping and disabling the ollama process..."
    sudo systemctl stop ollama.service || { error "Failed to stop ollama service"; exit 1; }
    sudo systemctl disable ollama.service || { error "Failed to disable ollama service"; exit 1; }
    info "Ollama service stopped and disabled successfully."

    title "Removing the ollama process..."
    sudo rm /etc/systemd/system/ollama.service || { error "Failed to remove ollama service"; exit 1; }
    info "Ollama service removed successfully."

    sudo systemctl daemon-reload

    # Stop and remove Ollama packages...
    title "Removing the ollama binaries..."
    sudo rm /usr/local/bin/ollama || { error "Failed to remove ollama binaries"; exit 1; }
    title "Removing the ollama packages..."
    sudo rm -r /usr/local/lib/ollama || { error "Failed to remove ollama packages"; exit 1; }
    title "Removing the ollama models..."
    sudo rm -r /usr/share/ollama || { error "Failed to remove ollama models"; exit 1; }
    info "Ollama binaries, packages and models removed successfully."

    title "Removing the ollama user and group..."
    sudo userdel ollama || { error "Failed to remove ollama user"; exit 1; }
    sudo groupdel ollama || { error "Failed to remove ollama group"; exit 1; }
    info "Ollama user and group removed successfully."

    info "Ollama deleted successfully."
    return 0
}

#

# Menu

while true
do

    PS3='Select an action for Ollama: '
    options=(
        "Install"
        "Restart"
        "Stop"
        "Check logs"
        "Update"
        "Delete"
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