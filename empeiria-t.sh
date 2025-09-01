#!/bin/bash

# Set the version variable
NAME="Empeiria (testnet)"
BIN_VER="0.3.0"

# ------------------------------------------------------------------------
# Set blockchain variable
# ------------------------------------------------------------------------
REQUIRED_GO=true
REQUIRED_COSMOVISOR=true
REQUIRED_RUST=false

MONIKER=""
KEYRING_BACKEND="file"
PORT="36"
PRUNING="custom"
PRUNING_KEEP_RECENT=100
PRUNING_KEEP_EVERY=0
PRUNING_INTERVAL=19
GAS="auto"
GAS_ADJUSTMENT=1.5
MINIMUM_GAS_PRICES=0.0001
TOKEN="EMPE"
TOKEN_M="uempe"
INDEXER="kv"
WALLET_NAME="wallet"
BIN_VERSION=${BIN_VER}
BIN_NAME="emped"
MAIN_FOLDER="empe-chains"
HOME_FOLDER=".empe-chain"
CHAIN_ID="empe-testnet-2"
LINK_BIN="https://github.com/empe-io/empe-chain-releases/raw/refs/heads/master/v${BIN_VER}/emped_v${BIN_VER}_linux_amd64.tar.gz"
SEEDS="20ca5fc4882e6f975ad02d106da8af9c4a5ac6de@empeiria-testnet-seed.itrocket.net:28656"
PEERS=$(curl -sS https://empeiria-testnet-rpc.itrocket.net/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)
MAX_NUM_INBOUND_PEERS=10
MAX_NUM_OUTBOUND_PEERS=40

SNAP_RPC="https://empeiria-testnet-rpc.itrocket.net:443"
SNAPSHOTS_DIR="https://server-5.itrocket.net/testnet/empeiria/"
SNAPSHOT_MASK_NAME1="empeiria_.*_snap\.tar\.lz4"
# SNAPSHOT_MASK_NAME2="empe-chain\.tar\.lz4"
# Combine masks into a single pattern (example: "$SNAPSHOT_MASK_NAME1|$SNAPSHOT_MASK_NAME2")
SNAPSHOTS_PATTERN="$SNAPSHOT_MASK_NAME1"
WASM_URL=""

LINK_ADDRBOOK="${SNAPSHOTS_DIR}addrbook.json"
LINK_GENESIS="${SNAPSHOTS_DIR}genesis.json"

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
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


# Function to create service file
create_service_file() {
    title "Create service file..."

    # Create the service file
    sudo tee /etc/systemd/system/${BIN_NAME}.service > /dev/null <<EOF
[Unit]
Description=${MAIN_FOLDER} node
After=network-online.target

[Service]
User=${USER}
WorkingDirectory=${HOME}/${HOME_FOLDER}
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/${HOME_FOLDER}"
Environment="DAEMON_NAME=${BIN_NAME}"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=true"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$HOME/${HOME_FOLDER}/cosmovisor/current/bin"
Environment="LD_LIBRARY_PATH=$HOME/${HOME_FOLDER}/lib"

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        error "Error when creating service file!"
        exit 1
    fi

    info "Service file created successfully."
}

# Function to install node
install_node() {
    cd $HOME
    title "Installing node ${NAME}..."

    # Check Go versions
    check_go_versions

    # Check Cosmovisor versions
    check_cosmovisor_versions

    # download binary
    title "Download binary..."
    if [ -d "${HOME}/${MAIN_FOLDER}" ]; then
        sudo rm -rf ${HOME}/${MAIN_FOLDER}
    fi
    wget -O ${BIN_NAME} ${LINK_BIN} || { error "Failed to download ${BIN_NAME} binary"; exit 1; }
    tar -xvf ${BIN_NAME}
    info "${BIN_NAME} binary downloaded successfully."

    title "Making binaries executable..."
    chmod +x "${HOME}/${BIN_NAME}" || { error "Failed to make binary executable"; exit 1; }
    info "${BIN_NAME} made executable successfully."

    title "Creating cosmovisor folder..."
    mkdir -p ${HOME}/${HOME_FOLDER}/cosmovisor/genesis/bin || { error "Failed to create ${HOME}/${HOME_FOLDER}/cosmovisor/genesis/bin folder"; exit 1; }
    mkdir -p ${HOME}/${HOME_FOLDER}/cosmovisor/upgrades || { error "Failed to create ${HOME}/${HOME_FOLDER}/cosmovisor/upgrades folder"; exit 1; }
    info "Installation folder created successfully."

    title "Move binaries to cosmovisor folder..."
    sudo cp ${HOME}/${BIN_NAME} ${HOME}/${HOME_FOLDER}/cosmovisor/genesis/bin || { error "Failed move binary to cosmovisor folder"; exit 1; }
    rm ${HOME}/${BIN_NAME}
    info "Binaries moved to cosmovisor folder successfully..."

    # Create application symlinks
    title "Create application symlinks..."
    ln -s "${HOME}/${HOME_FOLDER}/cosmovisor/genesis" "${HOME}/${HOME_FOLDER}/cosmovisor/current" -f || { error "Failed to create symbolic link for genesis"; exit 1; }
    sudo ln -s "${HOME}/${HOME_FOLDER}/cosmovisor/current/bin/${BIN_NAME}" "/usr/local/bin/${BIN_NAME}" -f || { error "Failed to create symbolic link for ${BIN_NAME}"; exit 1; }
    info "Application symlinks created successfully."

    # Prompt user for moniker
    prompt_moniker

    # Prompt user for port
    prompt_port

    # Install WASM
    title "Installing WASM..."
    mkdir ${HOME}/${HOME_FOLDER}/lib || { error "Failed to create ${HOME}/${HOME_FOLDER}/lib folder"; exit 1; }
    wget https://github.com/CosmWasm/wasmvm/releases/download/v1.5.2/libwasmvm.x86_64.so -P ${HOME}/${HOME_FOLDER}/lib
    # echo 'export LD_LIBRARY_PATH=${HOME}/${HOME_FOLDER}/lib:$LD_LIBRARY_PATH' >> ~/.profile
    source ~/.profile
    sleep 2
    info "WASM installed successfully."

    # Config and init app
    title "Configuration and init app..."
    ${BIN_NAME} config node tcp://localhost:${PORT}657 --home "${HOME}/${HOME_FOLDER}" || { error "Failed to configure node"; exit 1; }
    ${BIN_NAME} config keyring-backend ${KEYRING_BACKEND} --home "${HOME}/${HOME_FOLDER}" || { error "Failed to configure keyring backend"; exit 1; }
    ${BIN_NAME} config chain-id ${CHAIN_ID} --home "${HOME}/${HOME_FOLDER}" || { error "Failed to configure chain ID"; exit 1; }
    ${BIN_NAME} init "${MONIKER}" --chain-id ${CHAIN_ID} --home "${HOME}/${HOME_FOLDER}" || { error "Failed to initialize application"; exit 1; }
    info "Configuration and init app successfully..."

    # Download genesis and addrbook
    title "Download genesis.json..."
    wget -O ${HOME}/${HOME_FOLDER}/config/genesis.json ${LINK_GENESIS}
    if [ $? -ne 0 ]; then
        error "Error: Failed to download genesis.json"
        exit 1
    fi
    info "genesis.json downloaded successfully..."

    title "Download addrbook.json..."
    wget -O ${HOME}/${HOME_FOLDER}/config/addrbook.json ${LINK_ADDRBOOK}
    if [ $? -ne 0 ]; then
        error "Error: Failed to download addrbook.json"
        exit 1
    fi
    info "addrbook.json downloaded successfully..."

    # Set seeds and peers
    title "Set seeds and peers..."
    sed -i "s|^seeds *=.*|seeds = \"$(echo "$SEEDS" | sed 's|[&/]|\\&|g')\"|" "${HOME}/${HOME_FOLDER}/config/config.toml"
    sed -i "s|^persistent_peers *=.*|persistent_peers = \"$(echo "$PEERS" | sed 's|[&/]|\\&|g')\"|" "${HOME}/${HOME_FOLDER}/config/config.toml"
    sed -i "s|^max_num_inbound_peers =.*|max_num_inbound_peers = ${MAX_NUM_INBOUND_PEERS}|" "${HOME}/${HOME_FOLDER}/config/config.toml"
    sed -i "s|^max_num_outbound_peers =.*|max_num_outbound_peers = ${MAX_NUM_OUTBOUND_PEERS}|" "${HOME}/${HOME_FOLDER}/config/config.toml"
    info "Seeds and peers installed successfully."

    # Config pruning
    title "Set pruning..."
    sed -i "s|^pruning *=.*|pruning = \"${PRUNING}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i "s|^pruning-keep-recent *=.*|pruning-keep-recent = \"${PRUNING_KEEP_RECENT}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i "s|^pruning-keep-every *=.*|pruning-keep-every = \"${PRUNING_KEEP_EVERY}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i "s|^pruning-interval *=.*|pruning-interval = \"${PRUNING_INTERVAL}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    info "The pruning has been established successfully."

    # Set minimum gas price, enable prometheus and disable indexing
    title "Set gas price, prometheus, indexer..."
    sed -i "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"${MINIMUM_GAS_PRICES}${TOKEN_M}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i "s|^prometheus = false|prometheus = true|" ${HOME}/${HOME_FOLDER}/config/config.toml
    sed -i "s|^indexer *=.*|indexer = \"${INDEXER}\"|" ${HOME}/${HOME_FOLDER}/config/config.toml
    info "Gas price, prometheus, indexer set successfully."

    # Set ports
    title "Set ports..."
    sed -i -e "s|^proxy_app = \"tcp://127.0.0.1:26658\"|proxy_app = \"tcp://127.0.0.1:${PORT}658\"|; \
        s|^laddr = \"tcp://127.0.0.1:26657\"|laddr = \"tcp://0.0.0.0:${PORT}657\"|; \
        s|^pprof_laddr = \"localhost:6060\"|pprof_laddr = \"localhost:${PORT}160\"|; \
        s|^laddr = \"tcp://0.0.0.0:26656\"|laddr = \"tcp://0.0.0.0:${PORT}656\"|; \
        s|^prometheus_listen_addr = \":26660\"|prometheus_listen_addr = \":${PORT}660\"|" ${HOME}/${HOME_FOLDER}/config/config.toml

    sed -i -e "s|^address = \"tcp://localhost:1317\"|address = \"tcp://0.0.0.0:${PORT}317\"|; \
        s|^address = \":8080\"|address = \":${PORT}080\"|; \
        s|^address = \"localhost:9090\"|address = \"0.0.0.0:${PORT}090\"|; \
        s|^address = \"localhost:9091\"|address = \"0.0.0.0:${PORT}191\"|; \
        s|:6065|:${PORT}065|" ${HOME}/${HOME_FOLDER}/config/app.toml
    info "Ports set successfully."

    # Open API, RPC...
    title "Enable access to API, RPC ports..."
    sed -i '/^\[api\]/,/^\[/{s/^enable = false/enable = true/}' "${HOME}/${HOME_FOLDER}/config/app.toml"
    sed -i '/^\[grpc\]/,/^\[/{s/^enable = false/enable = true/}' "${HOME}/${HOME_FOLDER}/config/app.toml"
    sed -i '/^\[grpc-web\]/,/^\[/{s/^enable = false/enable = true/}' "${HOME}/${HOME_FOLDER}/config/app.toml"
    sed -i '/^\[json-rpc\]/,/^\[/{s/^enable = false/enable = true/}' "${HOME}/${HOME_FOLDER}/config/app.toml"
    info "Access to API, RPC ports granted successfully."

    # Open ports
    title "Open ports..."
    for port in ${PORT}658 ${PORT}657 ${PORT}660 ${PORT}317 ${PORT}090 ${PORT}191; do
        sudo ufw allow "$port" || { error "Failed to open port $port"; exit 1; }
    done
    sudo ufw reload || { error "Failed to reload UFW"; exit 1; }

    # Create service file
    create_service_file

    # Manage snapshot (get info and install if user agrees)
    manage_snapshot "$SNAPSHOTS_DIR" "$SNAPSHOTS_PATTERN" "${HOME}/${HOME_FOLDER}"

    # enable and start service
    title "Reloading systemd and starting the service..."
    sudo systemctl daemon-reload
    sudo systemctl enable ${BIN_NAME}
    sudo systemctl restart ${BIN_NAME}
    # sudo journalctl -fu ${BIN_NAME} -o cat

    if ! sudo systemctl is-active --quiet ${BIN_NAME}; then
        warning "The ${BIN_NAME} service is not running. Check the logs with 'journalctl -fu ${BIN_NAME} -o cat'." >&2
        exit 1
    fi

    info "Service started successfully."

    info "${NAME} installed successfully."
    return 0
}

# Function to restart node
restart_node() {
    title "Restart node ${NAME}..."

    sudo systemctl restart ${BIN_NAME}

    if ! sudo systemctl is-active --quiet ${BIN_NAME}; then
        warning "The ${BIN_NAME} service is not running. Check the logs with 'journalctl -fu ${BIN_NAME} -o cat'." >&2
        exit 1
    fi

    info "${NAME} restarted successfully."
    return 0
}

# Function to stop node
stop_node() {
    title "Stop ${NAME}..."

    sudo systemctl stop ${BIN_NAME}

    if ! sudo systemctl is-active --quiet ${BIN_NAME}; then
        warning "The ${BIN_NAME} service is not running. Check the logs with 'journalctl -fu ${BIN_NAME} -o cat'." >&2
        exit 1
    fi


    info "${NAME} stopped successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    title "Checking node logs for ${NAME}..."

    sudo journalctl -fu ${BIN_NAME} -o cat --no-hostname

    return 0
}

# Function to update node
update_node() {
    title "Updating node ${NAME}..."
    cd $HOME

    title "Download new binary..."
    if [ -d "${HOME}/${MAIN_FOLDER}" ]; then
        sudo rm -rf ${HOME}/${MAIN_FOLDER}
    fi
    wget -O ${MAIN_FOLDER} ${LINK_BIN} || { error "Failed to download new ${BIN_NAME} binary"; exit 1; }
    info "New ${BIN_NAME} binary downloaded successfully."

    title "Making new binaries executable..."
    chmod +x "${HOME}/${BIN_NAME}" || { error "Failed to make binary executable"; exit 1; }
    info "New ${BIN_NAME} made executable successfully."

    title "Creating cosmovisor folder..."
    mkdir -p ${HOME}/${HOME_FOLDER}/cosmovisor/upgrades/v${BIN_VERSION}/bin || { error "Failed to create ${HOME}/${HOME_FOLDER}/cosmovisor/upgrades/v${BIN_VERSION}/bin folder"; exit 1; }
    info "Installation folder created successfully."

    title "Move binaries to cosmovisor folder..."
    sudo mv ${HOME}/${BIN_NAME} ${HOME}/${HOME_FOLDER}/cosmovisor/upgrades/v${BIN_VERSION}/bin
    info "Binaries moved to cosmovisor folder successfully..."

    # enable and start service
    title "Reloading systemd and starting the service..."
    sudo systemctl restart ${BIN_NAME}

    if ! sudo systemctl is-active --quiet ${BIN_NAME}; then
        warning "The ${BIN_NAME} service is not running. Check the logs with 'journalctl -fu ${BIN_NAME} -o cat'." >&2
        exit 1
    fi

    info "Service started successfully."

    info "${NAME} updated successfully."
    return 0
}

# Function to delete node
delete_node() {
    warning "Make sure you back up your node data before continuing.\n"
    warning "Yeah, I backed it up: (y/n)"
    read -r backup
    if [[ "$backup" =~ ^[Yy]$ ]]; then
        info "It's backed up. Continued..."
    else
        error "The backup has not been saved. Back to the menu......"
        return 1
    fi

    title "Stop node ${NAME}..."

    title "Stop node ${NAME}..."
    sudo systemctl stop ${BIN_NAME}
    sudo systemctl disable ${BIN_NAME}
    info "${NAME} node stopped successfully."

    title "Delete service for node ${NAME}..."
    sudo rm -rf /etc/systemd/system/${BIN_NAME}.service
    info "Service for node deleted successfully."

    title "Delete binaries for node..."
    sudo rm $(which ${BIN_NAME})
    info "Binaries for node deleted successfully."

    title "Remove node folders..."
    sudo rm -rf $HOME/${HOME_FOLDER}
    sudo rm -rf $HOME/${MAIN_FOLDER}
    info "Node folders removed successfully."

    info "${NAME} deleted successfully."
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
            *) error "Invalid option $REPLY" ;;
        esac
    done
done