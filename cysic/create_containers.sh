#!/bin/bash

# File with keys
KEYS_FILE="keys.json"

# Number of containers and starting index
NUM_CONTAINERS=$1
START_INDEX=$2

# Base folder for all containers
BASE_FOLDER="containers"
mkdir -p "$BASE_FOLDER"

# Check if the number of containers is provided
if [ -z "$NUM_CONTAINERS" ] || [ -z "$START_INDEX" ]; then
  echo "************************************************************************************"
  echo ""
  echo "Usage:   ./create_containers.sh <number_of_containers> <start_index>"
  echo ""
  echo "<number_of_containers>: The number of containers to create"
  echo "<start_index>: (Optional) The starting index for container numbering"
  echo ""
  echo "Example: ./create_containers.sh 5 0"
  echo "This will create 5 containers starting from index 0."
  echo ""
  echo "************************************************************************************"
  exit 1
fi

# Check if Dockerfile exists in the current directory
if [ ! -f "Dockerfile" ]; then
  echo "Error: Dockerfile not found in the current directory."
  exit 1
fi

# Check if keys.json exists
if [ ! -f "$KEYS_FILE" ]; then
  echo "Error: $KEYS_FILE not found. Please ensure the file exists."
  exit 1
fi

# Creating containers
echo "Creating $NUM_CONTAINERS containers starting from index $START_INDEX..."

for i in $(seq 0 $((NUM_CONTAINERS-1))); do
  CONTAINER_INDEX=$((START_INDEX + i))
  CONFIG_FOLDER="$BASE_FOLDER/verifier$CONTAINER_INDEX"
  mkdir -p "$CONFIG_FOLDER"

  # Extract the corresponding address from keys.json
  ADDRESS=$(jq -r ".[$CONTAINER_INDEX].address" "$KEYS_FILE")
  if [ -z "$ADDRESS" ] || [ "$ADDRESS" == "null" ]; then
    echo "Address for container verifier$CONTAINER_INDEX not found in $KEYS_FILE. Please check the file."
    continue
  fi

  mkdir -p "$CONFIG_FOLDER/cysic"
  mkdir -p "$CONFIG_FOLDER/data"

  # Create config.yaml
  cat > "$CONFIG_FOLDER/config.yaml" <<EOL
# Not Change
chain:
  endpoint: "grpc-testnet.prover.xyz:80"
  chain_id: "cysicmint_9001-1"
  gas_coin: "CYS"
  gas_price: 10
  claim_reward_address: "$ADDRESS"

server:
  cysic_endpoint: "https://api-testnet.prover.xyz"
EOL

  # Create .env
  cat > "$CONFIG_FOLDER/.env" <<EOL
EVM_ADDR=$ADDRESS
CHAIN_ID=534352
EOL

  # Create docker-compose.yml
  cat > "$CONFIG_FOLDER/docker-compose.yml" <<EOL
version: '3.8'
services:
  verifier:
    build:
      context: ../../
      dockerfile: Dockerfile
    volumes:
      - ./data:/app/data
      - ./cysic:/root/.cysic
    env_file:
      - .env
    network_mode: "host"
#    network_mode: "bridge"
    restart: unless-stopped
EOL

  echo "Configured container verifier$CONTAINER_INDEX with address $ADDRESS"
done

echo "Containers have been created."
