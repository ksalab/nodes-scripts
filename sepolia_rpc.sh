#!/bin/bash

# Set the version variable
NAME="Sepolia (testnet) RPC & Beacon Chain"
BIN_VER="0.0.1"
NODE_DIR="/root/sepolia"
DOCKER_COMPOSE_FILE="$NODE_DIR/docker-compose.yml"
JWT_FILE="$NODE_DIR/jwt.hex"
CLIENT_FILE="$NODE_DIR/client"
AGENT_SCRIPT="$NODE_DIR/cron_agent_sepolia.sh"
GRPC_PORT=18545
AUTHRPC_PORT=18551
P2P_PORT=30303
BEACON_PORT=15052
LIGHTHOUSE_PORT=19000
CHECKPOINT_SYNC_URL=https://sepolia.checkpoint-sync.ethpandaops.io

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
  echo "❌ Failed to load utility script!"
  exit 1
fi

#

function generate_jwt {
  text_box "INFO" "Generating JWT secret..."
  mkdir -p "$NODE_DIR"
  head -c 32 /dev/urandom | xxd -p -c 32 > "$JWT_FILE"
}

function choose_consensus_client {
  mkdir -p "$NODE_DIR"
  text_box "INFO" "Choosing consensus client:"
  select client in "Lighthouse" "Prysm" "Teku"; do
    case $client in
      Lighthouse | Prysm | Teku)
        echo "${client,,}" > "$CLIENT_FILE"
        text_box "DONE" "Consensus client set to $client"
        return
        ;;
      *) text_box "ERROR" "Invalid choice. Please try again." ;;
    esac
  done
}

function create_docker_compose {
  local client=$(cat "$CLIENT_FILE" 2> /dev/null || echo "")
  if [[ -z "$client" ]]; then
    text_box "ERROR" "Unknown client: $client"
    exit 1
  fi

  text_box "INFO" "Creating Docker Compose file for $client..."
  cat > "$DOCKER_COMPOSE_FILE" << EOF
version: '3.8'

services:
  geth:
    image: ethereum/client-go:stable
    container_name: geth
    restart: unless-stopped
    volumes:
      - $NODE_DIR/geth:/data
      - $JWT_FILE:/jwt.hex
    ports:
      - "$GRPC_PORT:8545"
      - "$P2P_PORT:30303"
      - "$AUTHRPC_PORT:8551"
    command: >
      --sepolia
      --datadir /data
      --http --http.addr 0.0.0.0 --http.api eth,web3,net,engine
      --authrpc.addr 0.0.0.0 --authrpc.port $AUTHRPC_PORT
      --authrpc.jwtsecret /jwt.hex
      --authrpc.vhosts=*
      --http.corsdomain="*"
      --syncmode=snap
      --cache=4096
EOF

  case $client in
    lighthouse)
      cat >> "$DOCKER_COMPOSE_FILE" << EOF

  lighthouse:
    image: sigp/lighthouse:latest
    container_name: lighthouse
    restart: unless-stopped
    volumes:
      - $NODE_DIR/lighthouse:/root/.lighthouse
      - $JWT_FILE:/root/jwt.hex
    depends_on:
      - geth
    ports:
      - "$BEACON_PORT:5052"
      - "$LIGHTHOUSE_PORT:9000/tcp"
      - "$LIGHTHOUSE_PORT:9000/udp"
    command: >
      lighthouse bn
      --network sepolia
      --execution-endpoint http://geth:$AUTHRPC_PORT
      --execution-jwt /root/jwt.hex
      --checkpoint-sync-url=$CHECKPOINT_SYNC_URL
      --http
      --http-address 0.0.0.0
EOF
      ;;
    prysm)
      cat >> "$DOCKER_COMPOSE_FILE" << EOF

  prysm:
    image: gcr.io/prysmaticlabs/prysm/beacon-chain:stable
    container_name: prysm
    restart: unless-stopped
    volumes:
      - $NODE_DIR/prysm:/data
      - $JWT_FILE:/jwt.hex
    depends_on:
      - geth
    ports:
      - "$BEACON_PORT:5052"
    command: >
      --sepolia
      --datadir=/data
      --execution-endpoint=http://geth:$AUTHRPC_PORT
      --jwt-secret=/jwt.hex
      --accept-terms-of-use
      --checkpoint-sync-url=$CHECKPOINT_SYNC_URL
	    --grpc-gateway-port=$BEACON_PORT
	    --grpc-gateway-host=0.0.0.0
EOF
      ;;
    teku)
      cat >> "$DOCKER_COMPOSE_FILE" << EOF

  teku:
    image: consensys/teku:latest
    container_name: teku
    restart: unless-stopped
    volumes:
      - $NODE_DIR/teku:/data
      - $JWT_FILE:/jwt.hex
    depends_on:
      - geth
    ports:
      - "$BEACON_PORT:5052"
    command: >
      --network=sepolia
      --data-path=/data
      --ee-endpoint=http://geth:$AUTHRPC_PORT
      --ee-jwt-secret-file=/jwt.hex
      --checkpoint-sync-url=$CHECKPOINT_SYNC_URL
      --rest-api-enabled=true
      --rest-api-interface=0.0.0.0
EOF
      ;;
    *)
      text_box "ERROR" "Unknown client: $client"
      exit 1
      ;;
  esac
}

function install_node {
  mkdir -p "$NODE_DIR"
  text_box "TITLE" "Installing Sepolia node..."
  choose_consensus_client
  generate_jwt
  create_docker_compose
  docker compose -f "$DOCKER_COMPOSE_FILE" up -d
  text_box "DONE" "Node installed and running successfully."
  echo -e "${BLUE}RPC:${RESET}      http://localhost:$GRPC_PORT"
  echo -e "${BLUE}BEACON:${RESET}   http://localhost:$BEACON_PORT"
}

function update_node {
  text_box "TITLE" "Updating Sepolia node..."
  docker compose -f "$DOCKER_COMPOSE_FILE" pull
  docker compose -f "$DOCKER_COMPOSE_FILE" up -d
  text_box "DONE" "Node updated successfully."
}

function view_logs {
  local client=$(cat "$CLIENT_FILE" 2> /dev/null || echo "lighthouse")
  text_box "INFO" "Select logs:"
  select opt in "Geth" "$client" "$(t "back")"; do
    case $REPLY in
      1)
        docker logs -f geth
        break
        ;;
      2)
        docker logs -f "$client"
        break
        ;;
      3) break ;;
      *) text_box "ERROR" "Invalid choice, try again." ;;
    esac
  done
}

function hex_to_dec() {
  printf "%d\n" "$((16#${1#0x}))"
}

function format_time() {
  local seconds=$1
  local h=$((seconds / 3600))
  local m=$(((seconds % 3600) / 60))
  local s=$((seconds % 60))
  printf "%02dh %02dm %02ds" $h $m $s
}

function check_sync {
  local client=$(cat "$CLIENT_FILE" 2> /dev/null || echo "lighthouse")
  text_box "INFO" "Checking synchronization..."

  text_box "INFO" "Execution (geth):"
  local sync_data=$(curl -s -X POST http://localhost:$GRPC_PORT -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')
  local is_syncing=$(echo "$sync_data" | jq -r '.result')

  if [[ "$is_syncing" == "false" ]]; then
    text_box "DONE" "Execution client is synced."
  else
    local current=$(echo "$sync_data" | jq -r '.result.currentBlock')
    local highest=$(echo "$sync_data" | jq -r '.result.highestBlock')

    if [[ -z "$current" || -z "$highest" || "$current" == "null" || "$highest" == "null" ]]; then
      text_box "ERROR" "Failed to retrieve sync data from Geth."
    else
      local current_dec=$(hex_to_dec "$current")
      local highest_dec=$(hex_to_dec "$highest")

      if [[ $highest_dec -eq 0 ]]; then
        text_box "ERROR" "Geth is not synced or invalid data received."
      else
        local remaining=$((highest_dec - current_dec))
        local progress=$((100 * current_dec / highest_dec))
        text_box "WARNING" "Geth is syncing..."
        echo "   Current block:     $current_dec"
        echo "   Target block:      $highest_dec"
        echo "   Blocks remaining:  $remaining"
        echo "   Progress:          $progress"

        text_box "INFO" "Calculating sync speed..."
        sleep 5
        local sync_data2=$(curl -s -X POST http://localhost:$GRPC_PORT -H 'Content-Type: application/json' \
          --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')
        local current2=$(echo "$sync_data2" | jq -r '.result.currentBlock')
        local current2_dec=$(hex_to_dec "$current2")

        local delta_blocks=$((current2_dec - current_dec))
        local speed_bps=0
        if [[ $delta_blocks -gt 0 ]]; then
          speed_bps=$((delta_blocks / 5))
        fi

        echo "   Speed:         $speed_bps  blocks/sec"

        if [[ $speed_bps -gt 0 ]]; then
          local est_sec=$((remaining / speed_bps))
          echo "   Estimated time:   $(format_time $est_sec)"
        else
          echo "   Speed too low to estimate"
        fi
      fi
    fi
  fi

  echo ""
  echo "Consensus ($client):"

  case "$client" in
    prysm | teku)
      local syncing_resp=$(curl -s http://localhost:$BEACON_PORT/eth/v1/node/syncing)
      if [[ "$syncing_resp" == "{}" || -z "$syncing_resp" ]]; then
        text_box "WARNING" "${client} No /eth/v1/node/syncing data, trying finality..."
        local fin_resp=$(curl -s http://localhost:$BEACON_PORT/eth/v1/node/finality)
        if [[ -z "$fin_resp" ]]; then
          fin_resp=$(curl -s http://localhost:$BEACON_PORT/eth/v1/beacon/states/head/finality_checkpoints)
        fi
        if [[ -n "$fin_resp" ]]; then
          text_box "INFO" "${client} Beacon chain active (finality data received)"
          echo "$fin_resp" | jq
        else
          text_box "ERROR" "${client} Failed to get finality data"
        fi
      else
        echo "$syncing_resp" | jq
        local is_syncing=$(echo "$syncing_resp" | jq -r '.data.is_syncing')
        if [[ "$is_syncing" == "false" ]]; then
          text_box "INFO" "${client} synchronized"
        else
          text_box "WARNING" "${client}  is syncing..."
        fi
      fi

      echo ""
      echo "$(t "${client}_health")"
      curl -s http://localhost:$BEACON_PORT/eth/v1/node/health | jq
      ;;

    lighthouse)
      local syncing_resp=$(curl -s http://localhost:$BEACON_PORT/eth/v1/node/syncing)
      if [[ "$syncing_resp" == "{}" || -z "$syncing_resp" ]]; then
        text_box "WARNING" "Lighthouse No /eth/v1/node/syncing data, trying finality..."
      else
        echo "$syncing_resp" | jq
        local is_syncing=$(echo "$syncing_resp" | jq -r '.data.is_syncing')
        if [[ "$is_syncing" == "false" ]]; then
          text_box "INFO" "Lighthouse synchronized"
        else
          text_box "WARNING" "Lighthouse is syncing..."
        fi
      fi

      echo ""
      text_box "INFO" "Lighthouse Beacon chain health:"
      curl -s http://localhost:$BEACON_PORT/eth/v1/node/health | jq
      ;;

    *)
      text_box "ERROR" "Unknown consensus client: $client"
      ;;
  esac
}

function setup_cron_agent {
  local client=$(cat "$CLIENT_FILE" 2> /dev/null || echo "")
  read -p "Enter Telegram token: " tg_token
  read -p "Enter Telegram chat_id: " tg_chat_id

  echo "Select cron agent interval:"
  echo $'1) Every 5 minutes\n2) Every 10 minutes\n3) Every 15 minutes\n4) Every 30 minutes\n5) Every hour'
  read -p "Select option: " interval_choice

  case $interval_choice in
    1) cron_schedule="*/5 * * * *" ;;
    2) cron_schedule="*/10 * * * *" ;;
    3) cron_schedule="*/15 * * * *" ;;
    4) cron_schedule="*/30 * * * *" ;;
    5) cron_schedule="0 * * * *" ;;
    *)
      echo "Invalid choice. Setting default interval: every 10 minutes."
      cron_schedule="*/10 * * * *"
      ;;
  esac

  touch "$AGENT_SCRIPT"
  chmod +x "$AGENT_SCRIPT"

  cat << EOF > "$AGENT_SCRIPT"
#!/bin/bash
CLIENT="$client"
TG_TOKEN="$tg_token"
TG_CHAT_ID="$tg_chat_id"

# Checking Geth
geth_sync_response=\$(curl -s -X POST http://localhost:\$GRPC_PORT \\
  -H "Content-Type: application/json" \\
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')

if echo "\$geth_sync_response" | grep -q '"result":false'; then
  geth_status="✅ Geth synced"
elif echo "\$geth_sync_response" | grep -q '"result":'; then
  geth_status="⚠️ Geth syncing in progress"
else
  curl -s -X POST "https://api.telegram.org/bot\$TG_TOKEN/sendMessage" \\
    --data-urlencode "chat_id=\$TG_CHAT_ID" \\
    --data-urlencode "text=❌ Geth not responding or returned invalid data!"
  exit 1
fi

# Checking the client's Consensus
consensus_response=\$(curl -s http://localhost:\$BEACON_PORT/eth/v1/node/syncing)
is_syncing=\$(echo "\$consensus_response" | jq -r '.data.is_syncing' 2>/dev/null)

if [ "\$is_syncing" == "false" ]; then
  consensus_status="✅ \$CLIENT synced"
elif [ "\$is_syncing" == "true" ]; then
  consensus_status="⚠️ \$CLIENT syncing in progress"
else
  curl -s -X POST "https://api.telegram.org/bot\$TG_TOKEN/sendMessage" \\
    --data-urlencode "chat_id=\$TG_CHAT_ID" \\
    --data-urlencode "text=❌ \$CLIENT not responding or returned invalid data!"
  exit 1
fi

STATUS_MSG="[Sepolia Node Monitor]
Execution client: \$geth_status
Consensus client: \$consensus_status"

curl -s -X POST "https://api.telegram.org/bot\$TG_TOKEN/sendMessage" \\
  --data-urlencode "chat_id=\$TG_CHAT_ID" \\
  --data-urlencode "text=\$STATUS_MSG"
EOF

  # Remove old entry if exists
  crontab -l 2> /dev/null | grep -v "$AGENT_SCRIPT" > /tmp/current_cron

  # Add new entry with selected interval
  echo "$cron_schedule $AGENT_SCRIPT" >> /tmp/current_cron
  crontab /tmp/current_cron
  rm /tmp/current_cron

  text_box "DONE" "Cron agent installed with interval: $cron_schedule"
}

function remove_cron_agent {
  crontab -l 2> /dev/null | grep -v "$AGENT_SCRIPT" | crontab -
  rm -f "$AGENT_SCRIPT"
  text_box "DONE" "Agent and cron task removed."
}

function stop_containers {
  text_box "INFO" "Stopping containers..."
  if [[ -f "$DOCKER_COMPOSE_FILE" ]]; then
    docker compose -f "$DOCKER_COMPOSE_FILE" down
    text_box "DONE" "Containers stopped."
  else
    text_box "WARNING" "docker-compose.yml not found."
  fi
}

function start_containers {
  text_box "INFO" "Start containers..."
  docker compose -f "$DOCKER_COMPOSE_FILE" up -d
  text_box "DONE" "Containers started."
}

function check_disk_usage {
  text_box "INFO" "Disk space usage:"

  text_box "INFO" "Geth:"
  docker exec -it geth du -sh /data 2> /dev/null || text_box "WARNING" "Container geth not running or unknown data path"

  if [[ -f "$CLIENT_FILE" ]]; then
    local client=$(cat "$CLIENT_FILE")
    text_box "INFO" "$(t "client_usage" "$client")"
    docker exec -it "$client" du -sh /data 2> /dev/null \
      || docker exec -it "$client" du -sh /root/.lighthouse 2> /dev/null \
      || text_box "WARNING" "Container $client not running or unknown data path"
  else
    text_box "WARNING" "Client file not found: $CLIENT_FILE"
  fi
}

function delete_node {
  text_box "WARNING" "This will delete all node data. Continue? (y/n)"
  read -r confirm
  if [[ "$confirm" == "y" ]]; then
    stop_containers
    rm -rf "$NODE_DIR"
    text_box "DONE" "Node completely removed."
  else
    text_box "INFO" "Deletion cancelled."
  fi
}

# Main menu
function main_menu {
  while true; do
    echo -e "${GREEN}====== Sepolia Node Manager ======${RESET}"
    echo -e '1) Install node\n2) Update node\n3) Check logs\n4) Check sync status\n5) Setup cron agent with Tg notifications\n6) Remove cron agent\n7) Stop containers\n8) Start containers\n9) Delete node\n10) Check disk usage\n11) Exit'
    echo -e "${GREEN}==================================${RESET}"
    read -p "Select option: " choice
    case $choice in
      1) install_node ;;
      2) update_node ;;
      3) view_logs ;;
      4) check_sync ;;
      5) setup_cron_agent ;;
      6) remove_cron_agent ;;
      7) stop_containers ;;
      8) start_containers ;;
      9) delete_node ;;
      10) check_disk_usage ;;
      11)
        text_box "INFO" "Goodbye!"
        exit 0
        ;;
      *) text_box "ERROR" "Invalid choice, try again." ;;
    esac
  done
}

main_menu
