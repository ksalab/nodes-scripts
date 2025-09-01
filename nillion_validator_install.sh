#!/bin/bash

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh); then
    error "Failed to load utility script!"
    exit 1
fi

# Default values

NILLION_MONIK=${1:-"default_name"}
NILLION_PORT=${2:-"27"}  # Default port prefix
NIL_TARGET_PATH="/home/ritual"

# Sleep for a moment

sleep 1

# Check if the target path exists

if [ ! -d "$NIL_TARGET_PATH" ]; then
    error "Target path $NIL_TARGET_PATH does not exist."
    exit 1
fi

# Check if netstat is available

if ! command -v netstat &> /dev/null; then
    error "netstat could not be found. Please install netstat."
    exit 1
fi

# Check if port 657 is in use

title "Checking if port 657 is in use..."
if netstat -tulpn | grep 657; then
    warning "Port 657 is already in use. Ensure no other service is using this port."
fi

# Change directory to the target path

title "Changing directory to $NIL_TARGET_PATH..."
cd "$NIL_TARGET_PATH" || { error "Failed to change directory to $NIL_TARGET_PATH"; exit 1; }

# Export PATH

title "Exporting PATH..."
export PATH=$PATH:$NIL_TARGET_PATH/.local/bin

# Check Nillion version

title "Checking Nillion version..."
nilliond version || { error "Failed to check Nillion version"; exit 1; }
info "Nillion version checked successfully."

# Initialize Nillion node

title "Initializing Nillion node..."
nilliond init "$NILLION_MONIK" --chain-id "$CHAIN_ID" || { error "Failed to initialize Nillion node"; exit 1; }
info "Nillion node initialized successfully."

# Configure Nillion node settings

title "Configuring Nillion node settings..."
nilliond config set client chain-id "$CHAIN_ID" || { error "Failed to set chain-id"; exit 1; }
nilliond config set client keyring-backend os || { error "Failed to set keyring-backend"; exit 1; }
nilliond config set client node "tcp://localhost:${NILLION_PORT}657" || { error "Failed to set node"; exit 1; }
info "Node configuration set successfully."

# Create necessary directories

title "Creating necessary directories..."
mkdir -p "$NIL_TARGET_PATH/.nillionapp/config" || { error "Failed to create directories"; exit 1; }
info "Directories created successfully."

# Copy config files from /root to target path

title "Copying config files from /root to target path..."
cp -R /root/.nillionapp/config/ "$NIL_TARGET_PATH/.nillionapp/config/" || { error "Failed to copy config files"; exit 1; }
info "Config files copied successfully."

# Create or overwrite validator.json

title "Creating or overwriting validator.json..."
sudo tee "$NIL_TARGET_PATH/.nillionapp/validator.json" > /dev/null <<EOF
{
    "pubkey": $(nilliond tendermint show-validator),
    "amount": "unil",
    "moniker": "$NILLION_MONIK",
    "identity": "",
    "website": "",
    "security": "",
    "details": "",
    "commission-rate": "0.1",
    "commission-max-rate": "0.2",
    "commission-max-change-rate": "0.01",
    "min-self-delegation": "1"
}
EOF
info "validator.json created successfully."

# Remove old genesis.json and addrbook.json

title "Removing old genesis.json and addrbook.json..."
rm -f "$NIL_TARGET_PATH/.nillionapp/config/genesis.json" "$NIL_TARGET_PATH/.nillionapp/config/addrbook.json" || { error "Failed to remove old files"; exit 1; }
info "Old files removed successfully."

# Download new genesis.json and addrbook.json

title "Downloading new genesis.json and addrbook.json..."
wget -P "$NIL_TARGET_PATH/.nillionapp/config" http://88.99.208.54:1433/genesis.json || { error "Failed to download genesis.json"; exit 1; }
wget -P "$NIL_TARGET_PATH/.nillionapp/config" http://88.99.208.54:1433/addrbook.json || { error "Failed to download addrbook.json"; exit 1; }
info "New genesis.json and addrbook.json downloaded successfully."

# Remove old data directory

title "Removing old data directory..."
rm -rf "$NIL_TARGET_PATH/.nillionapp/data" || { error "Failed to remove old data directory"; exit 1; }
info "Old data directory removed successfully."

# Download and extract snapshot

title "Downloading and extracting snapshot..."
curl -L http://88.99.208.54:1433/nillion_snap.tar.gz | tar -xzf - -C "$NIL_TARGET_PATH/.nillionapp" || { error "Failed to download and extract snapshot"; exit 1; }
info "Snapshot downloaded and extracted successfully."

# Set peers and seeds

title "Setting peers and seeds in config.toml..."
PEERS="ce05aec98558f9a8289f983b083badf9d37e4d44@141.95.35.110:56316,c59dff7e20c675fe4f76162e9886dcca9b5104ce@135.181.238.38:28156"
SEEDS=""
sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" "$NIL_TARGET_PATH/.nillionapp/config/config.toml" || { error "Failed to set peers and seeds"; exit 1; }
info "Peers and seeds set successfully."

# Set pruning

title "Setting pruning in app.toml..."
sed -i \
  -e 's|^pruning *=.*|pruning = "custom"|' \
  -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
  -e 's|^pruning-interval *=.*|pruning-interval = "10"|' \
  "$NIL_TARGET_PATH/.nillionapp/config/app.toml" || { error "Failed to set pruning"; exit 1; }
info "Pruning settings configured successfully."

# Set custom ports in config.toml

title "Setting custom ports in config.toml..."
sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:${NILLION_PORT}958\"%" "$NIL_TARGET_PATH/.nillionapp/config/config.toml" || { error "Failed to set proxy_app port"; exit 1; }
sed -i -e "s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:${NILLION_PORT}657\"%" "$NIL_TARGET_PATH/.nillionapp/config/config.toml" || { error "Failed to set laddr port"; exit 1; }
sed -i -e "s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:${NILLION_PORT}960\"%" "$NIL_TARGET_PATH/.nillionapp/config/config.toml" || { error "Failed to set pprof_laddr port"; exit 1; }
sed -i -e "s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:${NILLION_PORT}656\"%" "$NIL_TARGET_PATH/.nillionapp/config/config.toml" || { error "Failed to set P2P laddr port"; exit 1; }
sed -i -e "s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":${NILLION_PORT}660\"%" "$NIL_TARGET_PATH/.nillionapp/config/config.toml" || { error "Failed to set prometheus_listen_addr port"; exit 1; }
info "Custom ports set successfully in config.toml."

# Set custom ports in app.toml

title "Setting custom ports in app.toml..."
sed -i -e "s%^address = \"tcp://localhost:1317\"%address = \"tcp://0.0.0.0:${NILLION_PORT}917\"%" "$NIL_TARGET_PATH/.nillionapp/config/app.toml" || { error "Failed to set API address port"; exit 1; }
sed -i -e "s%^address = \":8080\"%address = \":${NILLION_PORT}980\"%" "$NIL_TARGET_PATH/.nillionapp/config/app.toml" || { error "Failed to set gRPC address port"; exit 1; }
sed -i -e "s%^address = \"localhost:9090\"%address = \"0.0.0.0:${NILLION_PORT}990\"%" "$NIL_TARGET_PATH/.nillionapp/config/app.toml" || { error "Failed to set pprof_laddr port"; exit 1; }
sed -i -e "s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:${NILLION_PORT}991\"%" "$NIL_TARGET_PATH/.nillionapp/config/app.toml" || { error "Failed to set metrics address port"; exit 1; }
sed -i -e "s%:8545%:${NILLION_PORT}545%" "$NIL_TARGET_PATH/.nillionapp/config/app.toml" || { error "Failed to set JSON-RPC port"; exit 1; }
sed -i -e "s%:8546%:${NILLION_PORT}546%" "$NIL_TARGET_PATH/.nillionapp/config/app.toml" || { error "Failed to set WebSocket port"; exit 1; }
sed -i -e "s%:6065%:${NILLION_PORT}665%" "$NIL_TARGET_PATH/.nillionapp/config/app.toml" || { error "Failed to set additional port"; exit 1; }
info "Custom ports set successfully in app.toml."

# Open necessary ports

title "Opening necessary ports..."
for port in "${NILLION_PORT}958" "${NILLION_PORT}657" "${NILLION_PORT}960" "${NILLION_PORT}656" "${NILLION_PORT}660" "${NILLION_PORT}917" "${NILLION_PORT}980" "${NILLION_PORT}990" "${NILLION_PORT}991" "${NILLION_PORT}545" "${NILLION_PORT}546" "${NILLION_PORT}665"; do
    sudo ufw allow "$port" || { error "Failed to open port $port"; exit 1; }
done
sudo ufw reload || { error "Failed to reload UFW"; exit 1; }
info "Necessary ports opened successfully."

# Restart Nillion service

title "Restarting Nillion service..."
sudo systemctl restart nilliond || { error "Failed to restart Nillion service"; exit 1; }
info "Nillion service restarted successfully."

# Display Nillion version

title "Displaying Nillion version..."
/home/ritual/.local/bin/nilliond version || { error "Failed to display Nillion version"; exit 1; }
info "Nillion version displayed successfully."

# View logs

title "Viewing logs for Nillion service..."
sudo journalctl -u nilliond -f --no-hostname -o cat

#
