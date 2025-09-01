#!/bin/bash

# Set the version variable
NAME="0g (ZeroGravity) Node"

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
GAS_ADJUSTMENT=1.6
MINIMUM_GAS_PRICES=0.00252
TOKEN="AOGI"
TOKEN_M="ua0gi"
INDEXER="kv"
WALLET_NAME="wallet"
BIN_VERSION="0.5.0"
BIN_NAME="0gchaind"
MAIN_FOLDER="0gchain"
HOME_FOLDER=".0gchain"
CHAIN_ID="zgtendermint_16600-2"
LINK_BIN="https://github.com/0glabs/0g-chain/releases/download/v${BIN_VERSION}/0gchaind-linux-v${BIN_VERSION}"
SEEDS="8f21742ea5487da6e0697ba7d7b36961d3599567@og-testnet-seed.itrocket.net:47656"
PEERS=$(curl -sS https://og-testnet-rpc.itrocket.net/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)

SNAP_RPC="https://og-testnet-rpc.itrocket.net:443"
SNAPSHOTS_DIR="https://server-5.itrocket.net/testnet/og/"
SNAPSHOT_MASK_NAME1="og_.*_snap\.tar\.lz4"
SNAPSHOT_MASK_NAME2="og-snap\.tar\.lz4"
# Combine masks into a single pattern
SNAPSHOTS_PATTERN="$SNAPSHOT_MASK_NAME1|$SNAPSHOT_MASK_NAME2"

LINK_ADDRBOOK="${SNAPSHOTS_DIR}addrbook.json"
LINK_GENESIS="${SNAPSHOTS_DIR}genesis.json"

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VERSION}"
export VER

# Loading universal functions
if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "❌ Failed to load utility script!"
    exit 1
fi

#

# Function to create service file
create_service_file() {
    text_box "TITLE" "Create service file..."

    # Create the service file
    sudo tee /etc/systemd/system/${BIN_NAME}.service > /dev/null <<EOF
[Unit]
Description=${MAIN_FOLDER} node
After=network-online.target

[Service]
User=${USER}
WorkingDirectory=${HOME}/${HOME_FOLDER}
ExecStart=$(which ${BIN_NAME}) start --home ${HOME}/${HOME_FOLDER} --log_output_console
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        text_box "ERROR" "Error when creating service file!"
        exit 1
    fi

    text_box "DONE" "Service file created successfully."
}

# Function to install node
install_node() {
    cd $HOME
    text_box "TITLE" "Installing node ${NAME}..."

    # Check Go versions
    check_go_versions

    # Check Cosmovisor versions
    check_cosmovisor_versions

    # download binary

    text_box "INFO" "Download binary..."
    if [ -d "${HOME}/${MAIN_FOLDER}" ]; then
        sudo rm -rf ${HOME}/${MAIN_FOLDER}
    fi
    wget -O ${MAIN_FOLDER} ${LINK_BIN} || { text_box "ERROR" "Failed to download ${BIN_NAME} binary"; exit 1; }
    text_box "DONE" "${BIN_NAME} binary downloaded successfully."

    text_box "INFO" "Making binaries executable..."
    chmod +x "${HOME}/${BIN_NAME}" || { text_box "ERROR" "Failed to make binary executable"; exit 1; }
    text_box "DONE" "${BIN_NAME} made executable successfully."

    text_box "INFO" "Creating cosmovisor folder..."
    mkdir -p ${HOME}/${HOME_FOLDER}/cosmovisor/genesis/bin || { text_box "ERROR" "Failed to create ${HOME}/${HOME_FOLDER}/cosmovisor/genesis/bin folder"; exit 1; }
    # mkdir -p ${HOME}/${HOME_FOLDER}/cosmovisor/upgrades/v${BIN_VERSION}/bin || { error "Failed to create ${HOME}/${HOME_FOLDER}/cosmovisor/upgrades/v${BIN_VERSION}/bin folder"; exit 1; }
    text_box "DONE" "Installation folder created successfully."

    text_box "INFO" "Move binaries to cosmovisor folder..."
    sudo cp ${HOME}/${BIN_NAME} ${HOME}/${HOME_FOLDER}/cosmovisor/genesis/bin || { text_box "ERROR" "Failed move binary to cosmovisor folder"; exit 1; }
    # sudo mv ${HOME}/${BIN_NAME} ${HOME}/${HOME_FOLDER}/cosmovisor/upgrades/v${BIN_VERSION}/bin
    text_box "DONE" "Binaries moved to cosmovisor folder successfully..."

    # Create application symlinks
    text_box "INFO" "Create application symlinks..."
    ln -s "${HOME}/${HOME_FOLDER}/cosmovisor/genesis" "${HOME}/${HOME_FOLDER}/cosmovisor/current" -f || { text_box "ERROR" "Failed to create symbolic link for genesis"; exit 1; }
    sudo ln -s "${HOME}/${HOME_FOLDER}/cosmovisor/current/bin/${BIN_NAME}" "/usr/local/bin/${BIN_NAME}" -f || { text_box "ERROR" "Failed to create symbolic link for ${BIN_NAME}"; exit 1; }
    text_box "DONE" "Application symlinks created successfully."

    # Prompt user for moniker
    prompt_moniker

    # Prompt user for port
    prompt_port

    # Config and init app
    text_box "INFO" "Configuration and init app..."
    ${BIN_NAME} config node tcp://localhost:${PORT}657 || { text_box "ERROR" "Failed to configure node"; exit 1; }
    ${BIN_NAME} config keyring-backend ${KEYRING_BACKEND} || { text_box "ERROR" "Failed to configure keyring backend"; exit 1; }
    ${BIN_NAME} config chain-id ${CHAIN_ID} || { text_box "ERROR" "Failed to configure chain ID"; exit 1; }
    ${BIN_NAME} init "${MONIKER}" --chain-id ${CHAIN_ID} || { text_box "ERROR" "Failed to initialize application"; exit 1; }
    text_box "DONE" "Configuration and init app successfully..."

    # Download genesis and addrbook
    text_box "INFO" "Download genesis.json..."
    wget -O ${HOME}/${HOME_FOLDER}/config/genesis.json ${LINK_GENESIS}
    if [ $? -ne 0 ]; then
        text_box "ERROR" "Error: Failed to download genesis.json"
        exit 1
    fi
    text_box "DONE" "genesis.json downloaded successfully..."

    text_box "INFO" "Download addrbook.json..."
    wget -O ${HOME}/${HOME_FOLDER}/config/addrbook.json ${LINK_ADDRBOOK}
    if [ $? -ne 0 ]; then
        text_box "ERROR" "Error: Failed to download addrbook.json"
        exit 1
    fi
    text_box "DONE" "addrbook.json downloaded successfully..."

    # Set seeds and peers
    text_box "INFO" "Set seeds and peers..."
    sed -i "s|^seeds *=.*\|seeds = \"${SEEDS}\"|" ${HOME}/${HOME_FOLDER}/config/config.toml
    sed -i "s|^persistent_peers *=.*\|persistent_peers = \"${PEERS}\"|" ${HOME}/${HOME_FOLDER}/config/config.toml
    text_box "DONE" "Seeds and peers installed successfully."

    # Config pruning
    text_box "INFO" "Set pruning..."
    sed -i "s|^pruning *=.*|pruning = \"${PRUNING}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i "s|^pruning-keep-recent *=.*|pruning-keep-recent = \"${PRUNING_KEEP_RECENT}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i "s|^pruning-keep-every *=.*|pruning-keep-every = \"${PRUNING_KEEP_EVERY}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i "s|^pruning-interval *=.*|pruning-interval = \"${PRUNING_INTERVAL}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    text_box "DONE" "The pruning has been established successfully."

    # Set minimum gas price, enable prometheus and disable indexing
    text_box "INFO" "Set gas price, prometheus, indexer..."
    sed -i "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"${MINIMUM_GAS_PRICES}${TOKEN_M}\"|" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i "s|^prometheus = false|prometheus = true|" ${HOME}/${HOME_FOLDER}/config/config.toml
    sed -i "s|^indexer *=.*|indexer = \"${INDEXER}\"|" ${HOME}/${HOME_FOLDER}/config/config.toml
    text_box "DONE" "Gas price, prometheus, indexer set successfully."

    # Set ports
    text_box "INFO" "Set ports..."
    sed -i -e "s|^proxy_app = \"tcp://127.0.0.1:26658\"|proxy_app = \"tcp://127.0.0.1:${PORT}658\"|; \
        s|^laddr = \"tcp://127.0.0.1:26657\"|laddr = \"tcp://0.0.0.0:${PORT}657\"|; \
        s|^pprof_laddr = \"localhost:6060\"|pprof_laddr = \"localhost:${PORT}160\"|; \
        s|^laddr = \"tcp://0.0.0.0:26656\"|laddr = \"tcp://0.0.0.0:${PORT}656\"|; \
        s|^prometheus_listen_addr = \":26660\"|prometheus_listen_addr = \":${PORT}660\"|" ${HOME}/${HOME_FOLDER}/config/config.toml

    sed -i -e "s|^address = \"tcp://0.0.0.0:1317\"|address = \"tcp://0.0.0.0:${PORT}317\"|; \
        s|^address = \":8080\"|address = \":${PORT}080\"|; \
        s|^address = \"0.0.0.0:9090\"|address = \"0.0.0.0:${PORT}090\"|; \
        s|^address = \"0.0.0.0:9091\"|address = \"0.0.0.0:${PORT}191\"|; \
        s|:8545|:${PORT}545|; \
        s|:8546|:${PORT}546|; \
        s|:6065|:${PORT}065|" ${HOME}/${HOME_FOLDER}/config/app.toml
    text_box "DONE" "Ports set successfully."

    # Open API, RPC...
    text_box "INFO" "Enable access to API, RPC ports..."
    sed -i -e "\|^\[api\]|,|\|^\[| { s|^enable = false|enable = true| }" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i -e "\|^\[grpc\]|,|\|^\[| { s|^enable = false|enable = true| }" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i -e "\|^\[grpc-web\]|,|\|^\[| { s|^enable = false|enable = true| }" ${HOME}/${HOME_FOLDER}/config/app.toml
    sed -i -e "\|^\[json-rpc\]|,|\|^\[| { s|^enable = false|enable = true| }" ${HOME}/${HOME_FOLDER}/config/app.toml
    text_box "DONE" "Access to API, RPC ports granted successfully."

    # Open ports
    text_box "INFO" "Open ports..."
    for port in ${PORT}658 ${PORT}657 ${PORT}660 ${PORT}317 ${PORT}090 ${PORT}191 ${PORT}545 ${PORT}546; do
        sudo ufw allow "$port" || { text_box "ERROR" "Failed to open port $port"; exit 1; }
    done
    sudo ufw reload || { text_box "ERROR" "Failed to reload UFW"; exit 1; }

    # Create service file
    create_service_file

    # Manage snapshot (get info and install if user agrees)
    manage_snapshot "$SNAPSHOTS_DIR" "$SNAPSHOTS_PATTERN" "${HOME}/${HOME_FOLDER}/data"

    # enable and start service
    text_box "INFO" "Reloading systemd and starting the service..."
    sudo systemctl daemon-reload
    sudo systemctl enable ${BIN_NAME}
    sudo systemctl restart ${BIN_NAME}
    # sudo journalctl -fu ${BIN_NAME} -o cat

    if ! sudo systemctl is-active --quiet ${BIN_NAME}; then
        text_box "WARNING" "The ${BIN_NAME} service is not running. Check the logs with 'journalctl -fu ${BIN_NAME} -o cat'." >&2
        exit 1
    fi

    text_box "DONE" "Service started successfully."

    text_box "DONE" "Node installed successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    text_box "TITLE" "Checking node logs for ${NAME}..."
    sudo journalctl -fu ${BIN_NAME} -o cat --no-hostname
    return 0
}

# Function to check node sync status
check_node_sync() {
    text_box "TITLE" "Checking node sync status for ${NAME}..."
    ${BIN_NAME} status 2>&1 | jq .sync_info
    return 0
}

# Function to create wallet
create_wallet() {
    text_box "TITLE" "Create or Recover wallet..."

    while true; do
        echo "Choose an option for creating wallet:"
        echo "  1) Create new wallet"
        echo "  2) Recover existing wallet instead of creating"
        echo "Enter your choice (1 or 2):"
        read -r WALLET_CHOICE

        if [ "$WALLET_CHOICE" == "1" ]; then
            text_box "INFO" "Creating wallet..."
            ${BIN_NAME} keys add ${WALLET_NAME} --eth --keyring-backend ${KEYRING_BACKEND}
            text_box "WARNING" "\n!!! ===== !!! ===== !!! ===== !!! SAVE YOUR MNEMONIC PHRASE !!! ===== !!! ===== !!! ===== !!!\n"
            text_box "DONE" "Wallet created successfully."
        elif [ "$WALLET_CHOICE" == "2" ]; then
            text_box "INFO" "Recover wallet..."
            ${BIN_NAME} keys add ${WALLET_NAME} --eth --recover --keyring-backend ${KEYRING_BACKEND}
            text_box "DONE" "Wallet recover successfully."
        else
            text_box "ERROR" "Invalid choice. Please try again."
        fi
    done

    return 0
}

# Function to create validator
create_validator() {
    text_box "TITLE" "Create validator for ${NAME}..."

    prompt_validator_params

    ${BIN_NAME} tx staking create-validator \
        --amount 1000000ua0gi \
        --from ${WALLET} \
        --commission-rate "${COMMISSION_RATE}" \
        --commission-max-rate "${COMMISSION_MAX_RATE}" \
        --commission-max-change-rate "${COMMISSION_MAX_CHANGE_RATE}" \
        --min-self-delegation 1 \
        --pubkey $(${BIN_NAME} tendermint show-validator) \
        --moniker "${MONIKER}" \
        --identity "${IDENTITY}" \
        --details "${DETAILS}" \
        --chain-id ${CHAIN_ID} \
        --gas=${GAS} --gas-adjustment=${GAS_ADJUSTMENT} --gas-prices ${MINIMUM_GAS_PRICES}${TOKEN_M} \
        -y    # Execute the create-validator command with user-provided parameters

    text_box "DONE" "Validator created..."
    return 0
}

# Function to synchronization via StateSync
synchronization_statesync() {
    text_box "TITLE" "Synchronization via StateSync..."

    LATEST_HEIGHT=$(curl -s $SNAP_RPC/block | jq -r .result.block.header.height); \
    BLOCK_HEIGHT=$((LATEST_HEIGHT - 1000)); \
    TRUST_HASH=$(curl -s "$SNAP_RPC/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)

    echo $LATEST_HEIGHT $BLOCK_HEIGHT $TRUST_HASH

    sed -i.bak \
    -e "s|^enable *=.*|enable = true|" \
    -e "s|^rpc_servers *=.*|rpc_servers = \"$SNAP_RPC,$SNAP_RPC\"|" \
    -e "s|^trust_height *=.*|trust_height = $BLOCK_HEIGHT|" \
    -e "s|^trust_hash *=.*|trust_hash = \"$TRUST_HASH\"|" \
    -e "s|^persistent_peers *=.*|persistent_peers = \"$PEERS\"|" \
    $HOME/${HOME_FOLDER}/config/config.toml

    ${BIN_NAME} tendermint unsafe-reset-all --home ${HOME}/${HOME_FOLDER}

    wget -O ${HOME}/${HOME_FOLDER}/config/addrbook.json ${LINK_ADDRBOOK}
    if [ $? -ne 0 ]; then
        text_box "ERROR" "Error: Failed to download addrbook.json"
        exit 1
    fi
    text_box "DONE" "addrbook.json downloaded successfully..."

    text_box "INFO" "Restart service..."
    sudo systemctl restart ${BIN_NAME}

    if ! sudo systemctl is-active --quiet ${BIN_NAME}; then
        text_box "WARNING" "The ${BIN_NAME} service is not running. Check the logs with 'journalctl -fu ${BIN_NAME} -o cat'." >&2
        exit 1
    fi

    text_box "Done" "Service restarted successfully."

    return 0
}

# Function to synchronization via SnapShot
synchronization_snapshot() {
    text_box "TITLE" "Synchronization via SnapShot..."

    # Get information about the latest snapshot
    if ! get_latest_snapshot_info "$SNAPSHOTS_DIR" "$SNAPSHOTS_PATTERN"; then
        return 1
    fi

    # Prompt user to install the snapshot
    while true; do
        read -p "Do you want to install this snapshot? (y/n): " choice
        case "$choice" in
            y|Y )
                # Install the snapshot
                cd $HOME
                sudo systemctl stop ${BIN_NAME} 
                cp ${HOME}/${HOME_FOLDER}/data/priv_validator_state.json ${HOME}/${HOME_FOLDER}/priv_validator_state.json.backup
                rm -rf ${HOME}/${HOME_FOLDER}/data

                install_snapshot "$SNAPSHOT_URL" "${HOME}/${HOME_FOLDER}/data"

                mv ${HOME}/${HOME_FOLDER}/priv_validator_state.json.backup ${HOM}E/${HOME_FOLDER}/data/priv_validator_state.json

                text_box "INFO" "Download addrbook.json..."
                wget -O ${HOME}/${HOME_FOLDER}/config/addrbook.json ${LINK_ADDRBOOK}
                if [ $? -ne 0 ]; then
                    text_box "ERROR" "Error: Failed to download addrbook.json"
                    exit 1
                fi
                text_box "DONE" "addrbook.json downloaded successfully..."

                text_box "INFO" "Restart service..."
                sudo systemctl restart ${BIN_NAME}

                if ! sudo systemctl is-active --quiet ${BIN_NAME}; then
                    warning "The ${BIN_NAME} service is not running. Check the logs with 'journalctl -fu ${BIN_NAME} -o cat'." >&2
                    exit 1
                fi

                text_box "DONE" "Service restarted successfully."

                break
                ;;
            n|N )
                # Continue without installing the snapshot
                text_box "INFO" "Continuing without installing the snapshot."
                break
                ;;
            * )
                # Invalid input
                text_box "ERROR" "Invalid choice. Please enter 'y' or 'n'."
                ;;
        esac
    done

    return 0
}

# Function to restart node
restart_node() {
    text_box "TITLE" "Restart node ${NAME}..."
    sudo systemctl restart ${BIN_NAME}
    if ! sudo systemctl is-active --quiet ${BIN_NAME}; then
        text_box "WARNING" "The ${BIN_NAME} service is not running. Check the logs with 'journalctl -fu ${BIN_NAME} -o cat'." >&2
        exit 1
    fi

    text_box "DONE" "${NAME} restarted successfully."
    return 0
}

# Function to stop node
stop_node() {
    text_box "TITLE" "Stop node ${NAME}..."
    sudo systemctl stop ${BIN_NAME}

    text_box "DONE" "${NAME} stopped successfully."
    return 0
}

# Function to update node
update_node() {
    text_box "TITLE" "Updating node ${NAME}..."
    cd $HOME

    text_box "INFO" "Download new binary..."
    if [ -d "${HOME}/${MAIN_FOLDER}" ]; then
        sudo rm -rf ${HOME}/${MAIN_FOLDER}
    fi
    wget -O ${MAIN_FOLDER} ${LINK_BIN} || { text_box "ERROR" "Failed to download new ${BIN_NAME} binary"; exit 1; }
    text_box "DONE" "New ${BIN_NAME} binary downloaded successfully."

    text_box "INFO" "Making new binaries executable..."
    chmod +x "${HOME}/${BIN_NAME}" || { text_box "ERROR" "Failed to make binary executable"; exit 1; }
    text_box "DONE" "New ${BIN_NAME} made executable successfully."

    text_box "INFO" "Creating cosmovisor folder..."
    mkdir -p ${HOME}/${HOME_FOLDER}/cosmovisor/upgrades/v${BIN_VERSION}/bin || { text_box "ERROR" "Failed to create ${HOME}/${HOME_FOLDER}/cosmovisor/upgrades/v${BIN_VERSION}/bin folder"; exit 1; }
    text_box "DONE" "Installation folder created successfully."

    text_box "INFO" "Move binaries to cosmovisor folder..."
    sudo mv ${HOME}/${BIN_NAME} ${HOME}/${HOME_FOLDER}/cosmovisor/upgrades/v${BIN_VERSION}/bin
    text_box "DONE" "Binaries moved to cosmovisor folder successfully..."

    # enable and start service
    text_box "INFO" "Reloading systemd and starting the service..."
    sudo systemctl restart ${BIN_NAME}

    if ! sudo systemctl is-active --quiet ${BIN_NAME}; then
        text_box "WARNING" "The ${BIN_NAME} service is not running. Check the logs with 'journalctl -fu ${BIN_NAME} -o cat'." >&2
        exit 1
    fi

    text_box "DONE" "Service started successfully."

    text_box "DONE" "Node updated successfully."
    return 0
}

# Function to delete node
delete_node() {
    text_box "TITLE" "Delete node ${NAME}..."
    warning "Make sure you back up your node data before continuing. Yeah, I backed it up: (y/n)"
    read -r backup
    if [[ "$backup" =~ ^[Yy]$ ]]; then
        text_box "INFO" "It's backed up. Continued..."
    else
        text_box "ERROR" "The backup has not been saved. Back to the menu......"
        return 1
    fi

    text_box "INFO" "Stop node ${NAME}..."
    sudo systemctl stop ${BIN_NAME}
    sudo systemctl disable ${BIN_NAME}
    text_box "DONE" "${NAME} node stopped successfully."

    text_box "INFO" "Delete service for node ${NAME}..."
    sudo rm -rf /etc/systemd/system/${BIN_NAME}.service
    text_box "DONE" "Service for node deleted successfully."

    text_box "INFO" "Delete binaries for node..."
    sudo rm $(which ${BIN_NAME})
    text_box "DONE" "Binaries for node deleted successfully."

    text_box "INFO" "Remove node folders..."
    sudo rm -rf $HOME/${HOME_FOLDER}
    sudo rm -rf $HOME/${MAIN_FOLDER}
    text_box "DONE" "Node folders removed successfully."

    text_box "DONE" "${NAME} deleted successfully."
    return 0
}

#

# Menu

while true
do
    PS3="Select an action for ${NAME}: "
    options=(
        "Install node"
        "Check node logs"
        "Check node sync status"
        "Create/Recover wallet"
        "Create validator"
        "Synchronization via StateSync"
        "Synchronization via SnapShot"
        "Restart node"
        "Stop node"
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
            "Check node logs")
                check_node_logs
                break
                ;;
            "Check node sync status")
                check_node_sync
                break
                ;;
            "Create/Recover wallet")
                create_wallet
                break
                ;;
            "Create validator")
                create_validator
                break
                ;;
            "Synchronization via StateSync")
                synchronization_statesync
                break
                ;;
            "Synchronization via SnapShot")
                synchronization_snapshot
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
