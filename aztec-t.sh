#!/bin/bash

# Set the version variable
NAME="Aztec (testnet)"
BIN_VER=".latest"
P2P_PORT=40400
PORT_INFO=8084
AZTEC_PATH=$HOME/.aztec
ENV_FILE="$AZTEC_PATH/.env"
BIN_PATH=${BIN_PATH:-$AZTEC_PATH/bin}
NETWORK="alpha-testnet"
L1_CHAIN_ID=11155111
L1_RPC="http://176.9.48.61:18545"
BLOB_SYNC_URL="http://176.9.48.61:13500"
WALLET_ADDRESS=""
WALLET_PRIVATE_KEY=""
STAKING_ASSET_HANDLER=0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2
MAX_TXPOOL_SIZE=1000000000
GOVERNANCE_PROPOSER_PAYLOAD_ADDRESS=0x54F7fe24E349993b363A5Fa1bccdAe2589D5E5Ef

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER
export DOCKER_CLI_HINTS=false

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
  echo "❌ Failed to load utility script!"
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

export DOCKER_CLI_HINTS=false

if [ ! -t 0 ]; then
  NON_INTERACTIVE=1
else
  NON_INTERACTIVE=${NON_INTERACTIVE:-0}
fi

# Define version if specified, otherwise set to "latest".
VERSION=${VERSION:-"latest"}
INSTALL_URI=${INSTALL_URI:-https://install.aztec.network}
if [ "$VERSION" != "latest" ]; then
  INSTALL_URI+="/$VERSION"
fi

# Get public IP
text_box "INFO" "Getting public IP address..."
ENR_ADDRESS=$(hostname -I | awk '{print $1}')
if [ -z "$ENR_ADDRESS" ]; then
  text_box "ERROR" "Failed to determine the public IP. Verify that the eth0.me service is available."
  exit 1
fi
text_box "DONE" "Public IP address: $ENR_ADDRESS"

# Copy a file from the install source path to the bin path and make it executable.
function install_bin {
  local dest="$BIN_PATH/$1"
  curl -fsSL "$INSTALL_URI/$1" -o "$dest"
  chmod +x "$dest"
  echo "Installed: $dest"
}

# Updates appropriate shell script to ensure the bin path is in the PATH.
function update_path_env_var {
  TARGET_DIR="${1}"
  # Check if the target directory is in the user's PATH.
  if [[ ":$PATH:" != *":$TARGET_DIR:"* ]]; then
    # Determine the user's shell.
    SHELL_PROFILE=""
    case $SHELL in
      */bash)
        SHELL_PROFILE="$HOME/.bash_profile"
        ;;
      */zsh)
        SHELL_PROFILE="$HOME/.zshrc"
        ;;
      # Add other shells as needed
      *)
        text_box "WARNING" "Unsupported shell: $SHELL"
        return
        ;;
    esac

    if [ "$NON_INTERACTIVE" -eq 0 ]; then
      # Inform the user about the change and ask for confirmation
      text_box "WARNING" "The directory $TARGET_DIR is not in your PATH."
      read -p "Add it to $SHELL_PROFILE to make the aztec binaries accessible? (y/n)" -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        text_box "WARNING" "Skipped updating PATH. You might need to add $TARGET_DIR to your PATH manually to use the binary."
        return
      fi
    fi

    # Add the target directory to the user's PATH in their profile.
    echo "export PATH=\"\$PATH:$TARGET_DIR\"" >> "$SHELL_PROFILE"

    if [ "$NON_INTERACTIVE" -eq 0 ] && [ "${NO_NEW_SHELL:-0}" -eq 0 ]; then
      text_box "DONE" "Done! Starting fresh shell..."
      export PATH="$PATH:$TARGET_DIR"
    fi
  fi
}

# Function to install node
install_node() {
  if ! check_docker_installed; then
    return 1
  fi

  if ! check_docker_running; then
    return 1
  fi

  cd $HOME
  text_box "TITLE" "Installing node ${NAME}..."

  # Pull the aztec container.
  if [ -z "${SKIP_PULL:-}" ]; then
    text_box "INFO" "Pulling aztec version $VERSION..."
    docker pull aztecprotocol/aztec:$VERSION

    # If not latest, retag to be latest so it runs from scripts.
    if [ $VERSION != "latest" ]; then
      docker tag aztecprotocol/aztec:$VERSION aztecprotocol/aztec:latest
    fi
  fi

  text_box "INFO" "Installing scripts in $BIN_PATH..."
  rm -rf $BIN_PATH && mkdir -p $BIN_PATH
  install_bin .aztec-run
  install_bin aztec
  install_bin aztec-up
  install_bin aztec-nargo
  install_bin aztec-wallet

  text_box "INFO" "Updating PATH..."
  update_path_env_var $BIN_PATH

  text_box "INFO" "Aztec alpha-testnet preparation..."
  aztec-up alpha-testnet

  # Request info...
  text_box "INFO" "Request info..."
  # while [ -z "$L1_RPC" ]; do
  #     read -p "Enter L1 RPC url (e.g. https://sepolia.rpc.url): " L1_RPC
  # done
  # while [ -z "$BLOB_SYNC_URL" ]; do
  #     read -p "Enter L1 Consensus host url (e.g. https://beacon.rpc.url): " BLOB_SYNC_URL
  # done
  while [ -z "$WALLET_ADDRESS" ]; do
    read -p "Enter ETH wallet address (0x...): " WALLET_ADDRESS
  done
  while [ -z "$WALLET_PRIVATE_KEY" ]; do
    read -sp "Enter ETH private key (without 0x...): " WALLET_PRIVATE_KEY
  done
  echo
  text_box "INFO" "Save variables to .env file"
  echo "NETWORK=$NETWORK" > "$ENV_FILE"
  echo "L1_RPC=$L1_RPC" >> "$ENV_FILE"
  echo "BLOB_SYNC_URL=$BLOB_SYNC_URL" >> "$ENV_FILE"
  echo "WALLET_ADDRESS=$WALLET_ADDRESS" >> "$ENV_FILE"
  echo "WALLET_PRIVATE_KEY=$WALLET_PRIVATE_KEY" >> "$ENV_FILE"
  echo "ENR_ADDRESS=$ENR_ADDRESS" >> "$ENV_FILE"
  echo "MAX_TXPOOL_SIZE=$MAX_TXPOOL_SIZE" >> "$ENV_FILE"
  echo "PORT_INFO=$PORT_INFO" >> "$ENV_FILE"
  echo "GOVERNANCE_PROPOSER_PAYLOAD_ADDRESS=$GOVERNANCE_PROPOSER_PAYLOAD_ADDRESS" >> "$ENV_FILE"
  text_box "INFO" "Saved variables to $ENV_FILE"

  text_box "DONE" "${NAME} installed successfully."
  return 0
}

start_node() {
  if ! check_docker_installed; then
    return 1
  fi

  if ! check_docker_running; then
    return 1
  fi

  # Load variables
  source .bash_profile
  if [ -f "$AZTEC_PATH/.env" ]; then
    export $(grep -E '^(NETWORK|L1_RPC|BLOB_SYNC_URL|WALLET_PRIVATE_KEY|WALLET_ADDRESS|ENR_ADDRESS|MAX_TXPOOL_SIZE|PORT_INFO|GOVERNANCE_PROPOSER_PAYLOAD_ADDRESS)=' "$AZTEC_PATH/.env" | xargs)
  else
    error "Missing .env file at $AZTEC_PATH"
    return 1
  fi

  text_box "TITLE" "Starting node ${NAME}..."

  aztec start --node --archiver --sequencer \
    --network $NETWORK \
    --l1-rpc-urls $L1_RPC \
    --l1-consensus-host-urls $BLOB_SYNC_URL \
    --sequencer.validatorPrivateKey 0x$WALLET_PRIVATE_KEY \
    --sequencer.governanceProposerPayload $GOVERNANCE_PROPOSER_PAYLOAD_ADDRESS \
    --sequencer.coinbase $WALLET_ADDRESS \
    --p2p.p2pIp $ENR_ADDRESS \
    --p2p.maxTxPoolSize $MAX_TXPOOL_SIZE \
    --port $PORT_INFO

  text_box "DONE" "${NAME} started successfully."
  return 0
}

restart_hard() {
  text_box "TITLE" "Restarting node ${NAME}..."
  text_box "INFO" "Deleting old DB..."
  rm -rf $AZTEC_PATH/alfa-testnet
  text_box "DONE" "DB deleted successfully."
  start_node
  text_box "DONE" "${NAME} restarted successfully."
  return 0
}

register_operator() {
  # Load variables
  source .bash_profile
  if [ -f "$AZTEC_PATH/.env" ]; then
    export $(grep -E '^(PORT_INFO|WALLET_ADDRESS)=' "$AZTEC_PATH/.env" | xargs)
  else
    text_box "ERROR" "Missing .env file at $AZTEC_PATH"
    return 1
  fi

  text_box "TITLE" "Registering operator for ${NAME}..."
  echo "Fetching Block Proof..."
  PROVEN_BLOCK=$(curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
    http://localhost:${PORT_INFO} | jq -r ".result.proven.number")

  if [[ -z "$PROVEN_BLOCK" || "$PROVEN_BLOCK" == "null" ]]; then
    text_box "ERROR" "Failed to retrieve the proven L2 block number."
  else
    text_box "INFO" "Wallet: ${WALLET_ADDRESS}"
    text_box "INFO" "Proven L2 Block Number: ${PROVEN_BLOCK}"
    echo "Fetching Sync Proof..."
    SYNC_PROOF=$(curl -s -X POST -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"node_getArchiveSiblingPath\",\"params\":[\"$PROVEN_BLOCK\",\"$PROVEN_BLOCK\"],\"id\":67}" \
      http://localhost:${PORT_INFO} | jq -r ".result")
    text_box "INFO" "Sync Proof:"
    echo "$SYNC_PROOF"
  fi

  text_box "DONE" "${NAME} operator registered successfully."
  return 0
}

get_node_id() {
  text_box "TITLE" "Getting node ID for ${NAME}..."
  NODE_ID=$(docker logs $(docker ps -q --filter ancestor=aztecprotocol/aztec:alpha-testnet \
    | head -n 1) 2>&1 \
    | grep -i "peerId" \
    | grep -o '"peerId":"[^"]*"' \
    | cut -d'"' -f4 \
    | head -n 1)
  text_box "DONE" "${NAME} node ID: ${NODE_ID}"
}
#

# Menu

# Menu options mapping
declare -A ACTIONS=(
  [1]=install_node
  [2]=start_node
  [3]=restart_hard
  [4]=register_operator
  [5]=get_node_id
  [6]=exit
)

while true; do
  PS3="Select an action for ${NAME}: "
  options=(
    "Install node"
    "Start node"
    "Hard restart (delete DB)"
    "Register operator"
    "Get node ID"
    "Exit"
  )

  select opt in "${options[@]}"; do
    case $REPLY in
      1 | 2 | 3 | 4 | 5 | 6)
        "${ACTIONS[$REPLY]}"
        break
        ;;
      *) text_box "ERROR" "Invalid option $REPLY" ;;
    esac
  done
done
