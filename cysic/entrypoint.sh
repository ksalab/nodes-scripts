#!/bin/sh

if [ -z "${EVM_ADDR}" ]; then
    echo "Error: EVM_ADDR environment variable is not set or is empty"
    exit 1
fi

# Определяем путь к ключу
KEY_PATH="/root/.cysic/keys/${EVM_ADDR}/"


sed -i "s|__EVM_ADDRESS__|$EVM_ADDR|g" ./config.yaml

if [ $? -ne 0 ]; then
    echo "Error: Failed to replace __EVM_ADDRESS__ in config.yaml"
    exit 1
fi

echo "Replacing __EVM_ADDRESS__ with $EVM_ADDR in config.yaml"

echo
echo
echo "[Testnet Phase 2] EVM_ADDR: \`$EVM_ADDR\`, CHAIN_ID: $CHAIN_ID"
echo
echo "- Telegram: https://t.me/blockchain_minter"
echo "- Github: https://github.com/whoami39/blockchain-tools/tree/main/cysic/verifier"
echo
echo "* modified by ksalab (c) 2024"
echo

exec /app/verifier -key "$KEY_PATH"
