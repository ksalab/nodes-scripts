#!/bin/bash

# Define colors
if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh); then
    error "Failed to load utility script!"
    exit 1
fi

# Stop Nillion service

title "Stopping Nillion service..."
sudo systemctl stop nilliond || { error "Failed to stop Nillion service"; exit 1; }
info "Nillion service stopped successfully."

# Download new version for Nillion

title "Downloading new version for Nillion..."
wget -O /home/ritual/.local/bin/nilliond https://snapshots.kjnodes.com/nillion-testnet/nilchaind-v0.2.2-linux-amd64 || { error "Failed to download new version for Nillion"; exit 1; }
info "New version for Nillion downloaded successfully."

# Check and set ownership

title "Checking and setting ownership for /home/ritual/.local/bin..."
sudo chown -R ritual:ritual /home/ritual/.local/bin || { error "Failed to set ownership for /home/ritual/.local/bin"; exit 1; }
info "Ownership set successfully."

# Restart Nillion service

title "Restarting Nillion service..."
sudo systemctl restart nilliond || { error "Failed to restart Nillion service"; exit 1; }
info "Nillion service restarted successfully."

# Display Nillion version

title "Displaying Nillion version..."
/home/ritual/.local/bin/nilliond version || { error "Failed to display Nillion version"; exit 1; }

#
