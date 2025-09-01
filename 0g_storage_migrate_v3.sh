#!/bin/bash

# Set the version variable
NAME="0g storage migrate"
BIN_VER="v2 -> v3"

# Export the version variable to make it available in the sourced script
VER="${NAME} ${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
    echo "Failed to load utility script!"
    exit 1
fi

#

# Processing a command line parameter
case "$1" in
    user) BASE_PATH="/home/ritual" ;;
    root | "") BASE_PATH="/root" ;;
    *)
        echo "Invalid parameter. Use 'user' or 'root'."
        exit 1
        ;;
esac

# Checking if the directory exists
if [[ ! -d "${BASE_PATH}/0g-storage-node" ]]; then
    text_box "ERROR" "Directory ${BASE_PATH}/0g-storage-node does not exist."
    exit 1
fi

# Check if the config-testnet-turbo.toml file exists
CONFIG_FILE="${BASE_PATH}/0g-storage-node/run/config-testnet-turbo.toml"
if [[ ! -f "$CONFIG_FILE" ]]; then
    text_box "ERROR" "Config file $CONFIG_FILE not found."
    exit 1
fi

# 1. Stopping a node
text_box "INFO" "Stopping the storage node..."
if systemctl list-unit-files | grep -E "zgs.service"; then
    systemctl stop zgs
elif systemctl list-unit-files | grep -E "zgstorage.service"; then
    systemctl stop zgstorage
else
    text_box "ERROR" "Neither zgs nor zgstorage service found."
    exit 1
fi

# 2. Backup config-testnet-turbo.toml
text_box "INFO" "Backing up config-testnet-turbo.toml..."
cp "${CONFIG_FILE}" "${BASE_PATH}/config-testnet-turbo.toml.backup"
if [[ $? -ne 0 ]]; then
    text_box "ERROR" "Failed to back up config-testnet-turbo.toml."
    exit 1
fi

# 3. Setting new contract variables
text_box "INFO" "Setting new contract variables..."
RPC_ENDPOINT="https://evmrpc-testnet.0g.ai"
ZGS_LOG_DIR="${BASE_PATH}/0g-storage-node/run/log"
ZGS_LOG_CONFIG_FILE="${BASE_PATH}/0g-storage-node/run/log_config"
LOG_CONTRACT_ADDRESS="0x56A565685C9992BF5ACafb940ff68922980DBBC5"
MINE_CONTRACT="0xB87E0e5657C25b4e132CB6c34134C0cB8A962AD6"
REWARD_CONTRACT="0x233B2768332e4Bae542824c93cc5c8ad5d44517E"
ZGS_LOG_SYNC_BLOCK=1

# 4. Editing config-testnet-turbo.toml
text_box "INFO" "Editing config-testnet-turbo.toml..."
sed -i '
s|^blockchain_rpc_endpoint = .*|blockchain_rpc_endpoint = "'"$RPC_ENDPOINT"'"|g
s|^log_sync_start_block_number = .*|log_sync_start_block_number = '"$ZGS_LOG_SYNC_BLOCK"'|g
s|^log_config_file = .*|log_config_file = "'"$ZGS_LOG_CONFIG_FILE"'"|g
s|^log_directory = .*|log_directory = "'"$ZGS_LOG_DIR"'"|g
s|^mine_contract_address = .*|mine_contract_address = "'"$MINE_CONTRACT"'"|g
s|^log_contract_address = .*|log_contract_address = "'"$LOG_CONTRACT_ADDRESS"'"|g
s|^reward_contract_address = .*|reward_contract_address = "'"$REWARD_CONTRACT"'"|g
' "$CONFIG_FILE"
if [[ $? -ne 0 ]]; then
    text_box "ERROR" "Failed to edit config-testnet-turbo.toml."
    exit 1
fi

# 5. Deleting the old database
text_box "INFO" "Deleting old database..."
rm -rf "${BASE_PATH}/0g-storage-node/run/db/"
if [[ $? -ne 0 ]]; then
    text_box "ERROR" "Failed to delete old database."
    exit 1
fi

# Add a pause before restarting the node
sleep 5

# 6. Restarting the node
SYSTEM_SERVICE=""
text_box "INFO" "Restarting the storage node..."
if systemctl list-unit-files | grep -E "zgs.service"; then
    SYSTEM_SERVICE="zgs"
elif systemctl list-unit-files | grep -E "zgstorage.service"; then
    SYSTEM_SERVICE="zgstorage"
else
    text_box "ERROR" "Neither zgs nor zgstorage service found."
    exit 1
fi
systemctl start $SY
sleep 5

text_box "DONE" "Migration to v3 completed successfully!"
