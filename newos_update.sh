#!/bin/bash

# Set the version variable
NAME="New server (Hetzner)"
BIN_VER="1.0.0"

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "Failed to load utility script!"
    exit 1
fi

# Update the package list and upgrade all installed packages

title "Updating package list and upgrading installed packages..."
sudo apt update -y || { error "Failed to update package list"; exit 1; }
sudo apt upgrade -y || { error "Failed to upgrade installed packages"; exit 1; }
info "Package list updated and installed packages upgraded successfully."

# Install necessary components

title "Installing necessary components..."
sudo apt install -y build-essential git curl wget jq tmux lz4 mc ufw || { error "Failed to install necessary components"; exit 1; }
info "Necessary components installed successfully."

# Create .tmux.conf file in /root directory and add the content

title "Creating .tmux.conf file..."
echo "setw -g mouse on" | sudo tee /root/.tmux.conf || { error "Failed to create .tmux.conf file"; exit 1; }
info ".tmux.conf file created successfully."

# Allowing the ports of SSH, HTTP, HTTPS, etc

title "Allowing necessary ports..."
sudo ufw allow 22 || { error "Failed to allow port 22"; exit 1; }
sudo ufw enable || { error "Failed to enable UFW"; exit 1; }
sudo ufw status || { error "Failed to get UFW status"; exit 1; }
info "Necessary ports allowed and UFW enabled successfully."

# Block any communications to private networks

title "Blocking communications to private networks..."
for network in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4; do
    sudo ufw deny out from any to "$network" || { error "Failed to deny out traffic to $network"; exit 1; }
done
info "Communications to private networks blocked successfully."

# Clean the package cache

title "Cleaning package cache..."
sudo apt clean || { error "Failed to clean package cache"; exit 1; }
info "Package cache cleaned successfully."

# Warn the user about the reboot and ask for confirmation

error "Warning: The system will reboot to apply all changes."
read -p "Do you want to continue? (y/n): " confirm

if [ "$confirm" == "y" ]; then
    # Reboot the system to apply all changes
    info "Rebooting the system..."
    sudo reboot
else
    warning "Reboot cancelled."
fi

#
