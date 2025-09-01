#!/bin/bash

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh); then
    echo "Failed to load utility script!"
    exit 1
fi

# Update system and install build tools

title "Updating package list and upgrading installed packages..."
sudo apt -q update || { error "Failed to update package list"; exit 1; }
sudo apt -qy install curl git jq lz4 build-essential || { error "Failed to install build tools"; exit 1; }
sudo apt -qy upgrade || { error "Failed to upgrade installed packages"; exit 1; }
info "Package list updated and installed packages upgraded successfully."

# Download project binaries

title "Downloading project binaries..."
mkdir -p "$HOME/.nillionapp/cosmovisor/genesis/bin" || { error "Failed to create directory"; exit 1; }
wget -O "$HOME/.nillionapp/cosmovisor/genesis/bin/nilchaind" https://snapshots.kjnodes.com/nillion-testnet/nilchaind-v0.2.2-linux-amd64 || { error "Failed to download nilchaind binary"; exit 1; }
chmod +x "$HOME/.nillionapp/cosmovisor/genesis/bin/nilchaind" || { error "Failed to make binary executable"; exit 1; }
info "Project binaries downloaded and made executable successfully."

# Create application symlinks
title "Creating application symlinks..."
ln -s "$HOME/.nillionapp/cosmovisor/genesis" "$HOME/.nillionapp/cosmovisor/current" -f || { error "Failed to create symlink for genesis"; exit 1; }
sudo ln -s "$HOME/.nillionapp/cosmovisor/current/bin/nilchaind" "/usr/local/bin/nilchaind" -f || { error "Failed to create symlink for nilchaind"; exit 1; }
info "Application symlinks created successfully."

# Download and install Cosmovisor
title "Installing Cosmovisor..."
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.7.0 || { error "Failed to install Cosmovisor"; exit 1; }
info "Cosmovisor installed successfully."

# Create service
title "Creating systemd service for nillion-testnet..."
sudo tee /etc/systemd/system/nillion-testnet.service > /dev/null <<EOF
[Unit]
Description=nillion node service
After=network-online.target
[Service]
User=$USER
ExecStart=$(which cosmovisor) run start --home=$HOME/.nillionapp
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/.nillionapp"
Environment="DAEMON_NAME=nilchaind"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$HOME/.nillionapp/cosmovisor/current/bin"
[Install]
WantedBy=multi-user.target
EOF
if [ $? -ne 0 ]; then
  error "Error when creating service file!"
  exit 1
fi
info "Systemd service created successfully."

# Enable and start service
title "Enabling and starting nillion-testnet service..."
sudo systemctl daemon-reload || { error "Failed to reload systemd daemon"; exit 1; }
sudo systemctl enable nillion-testnet.service || { error "Failed to enable nillion-testnet service"; exit 1; }
info "nillion-testnet service enabled successfully."

# Set node configuration
title "Setting node configuration..."
nilchaind config set client chain-id nillion-chain-testnet-1 || { error "Failed to set chain-id"; exit 1; }
nilchaind config set client keyring-backend test || { error "Failed to set keyring-backend"; exit 1; }
nilchaind config set client node tcp://localhost:27657 || { error "Failed to set node"; exit 1; }
info "Node configuration set successfully."

# Prompt for MONIKER
while [ -z "$MONIKER" ]; do
  read -p "Enter MONIKER: " MONIKER
done

# Initialize the node
title "Initializing the node..."
nilchaind init "$MONIKER" --chain-id nillion-chain-testnet-1 --home="$HOME/.nillionapp" || { error "Failed to initialize the node"; exit 1; }
info "Node initialized successfully."

# Download genesis and addrbook
title "Downloading genesis and addrbook files..."
curl -Ls https://snapshots.kjnodes.com/nillion-testnet/genesis.json > "$HOME/.nillionapp/config/genesis.json" || { error "Failed to download genesis file"; exit 1; }
curl -Ls https://snapshots.kjnodes.com/nillion-testnet/addrbook.json > "$HOME/.nillionapp/config/addrbook.json" || { error "Failed to download addrbook file"; exit 1; }
info "Genesis and addrbook files downloaded successfully."

# Add seeds
title "Adding seeds to config.toml..."
sed -i -e "s|^seeds *=.*|seeds = \"3f472746f46493309650e5a033076689996c8881@nillion-testnet.rpc.kjnodes.com:18059\"|" "$HOME/.nillionapp/config/config.toml" || { error "Failed to add seeds"; exit 1; }
info "Seeds added successfully."

# Set minimum gas price
title "Setting minimum gas price in app.toml..."
sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0unil\"|" "$HOME/.nillionapp/config/app.toml" || { error "Failed to set minimum gas price"; exit 1; }
info "Minimum gas price set successfully."

# Set pruning
title "Setting pruning in app.toml..."
sed -i \
  -e 's|^pruning *=.*|pruning = "custom"|' \
  -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
  -e 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|' \
  -e 's|^pruning-interval *=.*|pruning-interval = "19"|' \
  "$HOME/.nillionapp/config/app.toml" || { error "Failed to set pruning"; exit 1; }
info "Pruning settings configured successfully."

# Set custom ports
title "Setting custom ports in config.toml..."
sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:27658\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:27657\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:6160\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:27656\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":27660\"%" "$HOME/.nillionapp/config/config.toml" || { error "Failed to set custom ports in config.toml"; exit 1; }
sed -i -e "s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:1417\"%; s%^address = \":8080\"%address = \":8180\"%; s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:9190\"%; s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:9191\"%; s%:8545%:8745%; s%:8546%:8746%; s%:6065%:6165%" "$HOME/.nillionapp/config/app.toml" || { error "Failed to set custom ports in app.toml"; exit 1; }
info "Custom ports set successfully."

# Open ports
title "Opening necessary ports..."
for port in 1417 8745 8746 9190 9191 27656 27657 27658 27660; do
    sudo ufw allow "$port" || { error "Failed to open port $port"; exit 1; }
done
sudo ufw reload || { error "Failed to reload UFW"; exit 1; }
info "Necessary ports opened successfully."

# Download latest chain snapshot
title "Downloading latest chain snapshot..."
curl -L https://snapshots.kjnodes.com/nillion-testnet/snapshot_latest.tar.lz4 | tar -Ilz4 -xf - -C "$HOME/.nillionapp" || { error "Failed to download and extract snapshot"; exit 1; }
info "Chain snapshot downloaded and extracted successfully."

# Copy upgrade-info.json if it exists
if [[ -f "$HOME/.nillionapp/data/upgrade-info.json" ]]; then
    cp "$HOME/.nillionapp/data/upgrade-info.json" "$HOME/.nillionapp/cosmovisor/genesis/upgrade-info.json" || { error "Failed to copy upgrade-info.json"; exit 1; }
    info "upgrade-info.json copied successfully."
else
    warning "No upgrade-info.json found."
fi

# Start service and check the logs
title "Starting nillion-testnet service..."
sudo systemctl start nillion-testnet.service || { error "Failed to start nillion-testnet service"; exit 1; }
info "nillion-testnet service started successfully."

# View logs
title "Viewing logs for nillion-testnet service..."
sudo journalctl -u nillion-testnet.service -f --no-hostname -o cat

#
