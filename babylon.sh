#!/bin/bash

# Set the version variable
NAME="Babylon"
BIN_VER="1.0.0-rc.6-fix"

# ------------------------------------------------------------------------
# Set blockchain variable
# ------------------------------------------------------------------------
REQUIRED_GO=false
REQUIRED_COSMOVISOR=false
REQUIRED_RUST=false

MONIKER=""
KEYRING_BACKEND="file"
PORT="41"
PRUNING="custom"
PRUNING_KEEP_RECENT=100
PRUNING_KEEP_EVERY=0
PRUNING_INTERVAL=19
GAS="auto"
GAS_ADJUSTMENT=1.5
MINIMUM_GAS_PRICES=0.002
TOKEN="BBN"
TOKEN_M="ubbn"
INDEXER="null"
WALLET_NAME="wallet"
BIN_VERSION=${BIN_VER}
BIN_NAME="babylond"
MAIN_FOLDER="babylon"
HOME_FOLDER=".babylond"
CHAIN_ID="bbn-test-5"
LINK_BIN="https://github.com/babylonlabs-io/babylon/releases/download/v${BIN_VERSION}/babylon-1.0.0-rc.6-hot-fix-linux-amd64"
SEEDS="be232be53f7ac3c4a6628f98becb48fd25df1adf@babylon-testnet-seed.nodes.guru:55706,ade4d8bc8cbe014af6ebdf3cb7b1e9ad36f412c0@testnet-seeds.polkachu.com:20656,59df4b3832446cd0f9c369da01f2aa5fe9647248@65.109.49.115:16256,0c949c3bcd83b81c794af8c3ae026a97d9c4564e@babylon-testnet-seed.itrocket.net:60656"
PEERS=$(curl -sS https://babylon-testnet-rpc.itrocket.net/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)

IAVL_CACHE_SIZE="5000"
IAVL_DISABLE_FASTNODE="false"
BTC_CONFIG_NETWORK="signet"
CONSENSUS_TIMEOUT_COMMIT="10s"

SNAP_RPC="https://babylon-testnet-rpc.itrocket.net:443"
SNAPSHOTS_DIR="https://server-7.itrocket.net/testnet/babylon/"
SNAPSHOT_MASK_NAME1="babylon_.*_snap\.tar\.lz4"
SNAPSHOT_MASK_NAME2="babylon-snap\.tar\.lz4"
# Combine masks into a single pattern
SNAPSHOTS_PATTERN="$SNAPSHOT_MASK_NAME1|$SNAPSHOT_MASK_NAME2"

LINK_ADDRBOOK="${SNAPSHOTS_DIR}addrbook.json"
LINK_GENESIS="${SNAPSHOTS_DIR}genesis.json"
# Place libwasmvm.x86_64.so to /usr/lib
LINK_LIBWASM="https://github.com/CosmWasm/wasmvm/releases/download/v2.1.0/libwasmvm.x86_64.so"

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
ExecStart=/root/go/bin/${BIN_NAME} start --chain-id bbn-test-5 --x-crisis-skip-assert-invariants
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$HOME/go/bin"

[Install]
WantedBy=multi-user.target
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

    # download binary
    title "Download binary..."
    if [ -d "${HOME}/${MAIN_FOLDER}" ]; then
        sudo rm -rf ${HOME}/${MAIN_FOLDER}
    fi
    wget -O ${BIN_NAME} ${LINK_BIN} || { error "Failed to download ${BIN_NAME} binary"; exit 1; }
    info "${BIN_NAME} binary downloaded successfully."

    title "Making binaries executable..."
    chmod +x "${HOME}/${BIN_NAME}" || { error "Failed to make binary executable"; exit 1; }
    info "${BIN_NAME} made executable successfully."

    mv ${HOME}/${BIN_NAME} ${HOME}/go/bin/${BIN_NAME}

    # Prompt user for moniker
    prompt_moniker

    # Prompt user for port
    prompt_port

    # Config and init app
    title "Configuration and init app..."
    ${BIN_NAME} config node tcp://localhost:${PORT}657 || { error "Failed to configure node"; exit 1; }
    ${BIN_NAME} config keyring-backend ${KEYRING_BACKEND} || { error "Failed to configure keyring backend"; exit 1; }
    ${BIN_NAME} config chain-id ${CHAIN_ID} || { error "Failed to configure chain ID"; exit 1; }
    ${BIN_NAME} init "${MONIKER}" --chain-id ${CHAIN_ID} || { error "Failed to initialize application"; exit 1; }
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
    info "Seeds and peers installed successfully."

    # Config pruning
    title "Set pruning..."
    sed -i "s|^pruning *=.*|pruning = \"${PRUNING}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i "s|^pruning-keep-recent *=.*|pruning-keep-recent = \"${PRUNING_KEEP_RECENT}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i "s|^pruning-keep-every *=.*|pruning-keep-every = \"${PRUNING_KEEP_EVERY}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i "s|^pruning-interval *=.*|pruning-interval = \"${PRUNING_INTERVAL}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    info "The pruning has been established successfully."

    # Config babylon
    title "Set babylon configs..."

    sed -i '/^\[btc-config\]/,/^\[/{s/^network *=.*/network = \"signet\"/}' "${HOME}/${HOME_FOLDER}/config/app.toml"
    sed -i "s|^timeout_commit *=.*|timeout_commit = \"10s\"|" ${HOME}/${HOME_FOLDER}/config/config.toml

    info "Babylon configs has been established successfully."

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



    info "${NAME} restarted successfully."
    return 0
}

# Function to stop node
stop_node() {
    title "Stop ${NAME}..."



    info "${NAME} stopped successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    title "Checking node logs for ${NAME}..."


    return 0
}

# Function to update node
update_node() {
    title "Updating node ${NAME}..."



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



    info "${NAME} deleted successfully."
    return 0
}

#

# Menu

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