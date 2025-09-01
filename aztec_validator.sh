#!/bin/bash

# Set the version variable
NAME="Aztec (testnet) validator"
BIN_VER="0.0.1"
ETHEREUM_HOSTS="http://176.9.48.61:18545"
RPC_URL="http://176.9.48.61:18545"
TELEGRAM_BOT_TOKEN="bot_token"
TELEGRAM_USER_ID="user_id"

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
  echo "❌ Failed to load utility script!"
  exit 1
fi

#

text_box "INFO" "Введите параметры подключения"

read -rp "$(echo -e "Введите VALIDATOR_PRIVATE_KEY (приватный ключ без '0x'): ")" VALIDATOR_PRIVATE_KEY
read -rp "$(echo -e "Введите ATTESTER (адрес кошелька) и PROPOSER_EOA (адрес кошелька): ")" ATTESTER

text_box "DONE" "Данные успешно получены. Продолжаем..."

# Пути
SCRIPT_DIR="$HOME/aztec-validator-script"
SCRIPT_PATH="$SCRIPT_DIR/aztec_validator.sh"
LOG_DIR="$SCRIPT_DIR/log"
LOG_FILE="$LOG_DIR/aztec_validator.log"
ENV_PATH="$SCRIPT_DIR/.env"

# Константы
MAX_ATTEMPTS=12
SLEEP_SECONDS=5
STAKING_ASSET_HANDLER="0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2"
L1_CHAIN_ID=11155111

ENR_ADDRESS=$(hostname -I | awk '{print $1}')
if [ -z "$ENR_ADDRESS" ]; then
  text_box "ERROR" "Failed to determine the public IP. Verify that the eth0.me service is available."
  exit 1
fi

text_box "INFO" "Создание директорий и файлов"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# Сохраняем переменные в .env
cat > "$ENV_PATH" << EOF
ETHEREUM_HOSTS=$ETHEREUM_HOSTS
RPC_URL=$RPC_URL
VALIDATOR_PRIVATE_KEY=$VALIDATOR_PRIVATE_KEY
ATTESTER=$ATTESTER
PROPOSER_EOA=$ATTESTER
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
TELEGRAM_USER_ID=$TELEGRAM_USER_ID
LOG_FILE=$LOG_FILE
MAX_ATTEMPTS=$MAX_ATTEMPTS
SLEEP_SECONDS=$SLEEP_SECONDS
STAKING_ASSET_HANDLER=$STAKING_ASSET_HANDLER
L1_CHAIN_ID=$L1_CHAIN_ID
ENR_ADDRESS=$ENR_ADDRESS
EOF

echo -e ".env сохранён в ${ENV_PATH}"

text_box "INFO" "Генерация исполняемого скрипта"

cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash

ENV_PATH="$(dirname "$0")/.env"
if [ -f "$ENV_PATH" ]; then
  set -o allexport
  source "$ENV_PATH"
  set +o allexport
else
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

COMMAND="/root/.aztec/bin/aztec add-l1-validator \
  --l1-rpc-urls $ETHEREUM_HOSTS \
  --private-key 0x$VALIDATOR_PRIVATE_KEY \
  --attester $ATTESTER \
  --proposer-eoa $ATTESTER \
  --staking-asset-handler $STAKING_ASSET_HANDLER \
  --l1-chain-id $L1_CHAIN_ID"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

send_telegram() {
  local MESSAGE=$1
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
       -d chat_id="$TELEGRAM_USER_ID" \
       -d text="$MESSAGE" > /dev/null
}

check_tx_status() {
  local HASH=$1
  local ATTEMPT=1

  while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    log "Checking tx status (attempt $ATTEMPT)..."
    STATUS=$(curl -s -X POST "$RPC_URL" \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc":"2.0",
        "method":"eth_getTransactionReceipt",
        "params":["'"$HASH"'"],
        "id":1
      }')

    TX_STATUS=$(echo "$STATUS" | grep -o '"status":"0x[01]"' | cut -d':' -f2 | tr -d '"')

    if [[ -z "$TX_STATUS" ]]; then
      log "Transaction is still pending..."
    elif [[ "$TX_STATUS" == "0x1" ]]; then
      log "Transaction SUCCESS"
      send_telegram "✅ AZTEC Validator - SUCCESS IP: $ENR_ADDRESS Wallet: $ATTESTER Tx: https://sepolia.ethplorer.io/tx/$HASH"
      return 0
    elif [[ "$TX_STATUS" == "0x0" ]]; then
      log "Transaction FAILED"
      send_telegram "❌ AZTEC Validator - FAILED IP: $ENR_ADDRESS Wallet: $ATTESTER Tx: https://sepolia.ethplorer.io/tx/$HASH"
      return 1
    fi

    ((ATTEMPT++))
    sleep "$SLEEP_SECONDS"
  done

  log "Transaction not confirmed after $((MAX_ATTEMPTS * SLEEP_SECONDS)) seconds"
  send_telegram "⚠️ AZTEC Validator IP: $ENR_ADDRESS Wallet: $ATTESTER TX not confirmed after timeout Tx: https://sepolia.ethplorer.io/tx/$HASH"
  return 1
}

log "Starting validator registration..."

OUTPUT=$(eval "$COMMAND" 2>&1)
log "Command output:"
echo "$OUTPUT" | tee -a "$LOG_FILE"

if echo "$OUTPUT" | grep -q "ValidatorQuotaFilledUntil"; then
  log "Quota filled. Stopping script."
  send_telegram "⚠️ AZTEC Validator IP: $ENR_ADDRESS Wallet: $ATTESTER Quota filled. Try later."
  exit 0
fi

TX_HASH=$(echo "$OUTPUT" | grep -oE 'Transaction hash: 0x[a-fA-F0-9]{64}' | awk '{print $3}')

if [[ -z "$TX_HASH" ]]; then
  log "Transaction hash not found. Aborting."
  send_telegram "❌ AZTEC Validator IP: $ENR_ADDRESS Wallet: $ATTESTER Transaction hash not found."
  exit 1
fi

log "Transaction hash found: $TX_HASH"
send_telegram "📤 AZTEC Validator IP: $ENR_ADDRESS Wallet: $ATTESTER TX sent Hash: $TX_HASH https://sepolia.ethplorer.io/tx/$TX_HASH"

if check_tx_status "$TX_HASH"; then
  exit 0
else
  log "Retrying registration..."
  exec "$0"
fi
EOF

chmod +x "$SCRIPT_PATH"
chmod +x "$LOG_FILE"

text_box "DONE" "Скрипт создан и сделан исполняемым: $SCRIPT_PATH"

text_box "INFO" "Добавление cron-задачи"

CRON_JOB="49 23 * * * $SCRIPT_PATH >> $LOG_FILE 2>&1"
(
  crontab -l 2> /dev/null | grep -v "$SCRIPT_PATH"
  echo "$CRON_JOB"
) | crontab -

echo -e "Cron задача добавлена: $CRON_JOB"
echo -e "⚠️ Скрипт будет выполняться каждый день в 23:49 CEST."

text_box "INFO" "Тестовый запуск через 10 секунд"

sleep 10

"$SCRIPT_PATH"
