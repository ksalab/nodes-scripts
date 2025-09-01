#!/bin/bash

# Set the version variable
NAME="Gaia"
BIN_VER="0.5.0"
PORT_INFO=8080

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER

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

source ~/.bashrc

# Function to install node
install_node() {
    cd $HOME
    text_box "TITLE" "Installing node ${NAME}..."

    text_box "INFO" "Update system..."
    # sudo apt update && sudo apt upgrade -y
    sudo apt install -y python3-pip python3-dev python3-venv python3-aiohttp curl git
    sudo apt install -y build-essential

    # Open ports
    text_box "INFO" "Opening necessary ports..."
    for port in "${PORT_INFO}"; do
        sudo ufw allow "$port" || { error "Failed to open port $port"; exit 1; }
    done
    sudo ufw reload || { error "Failed to reload UFW"; exit 1; }
    text_box "DONE" "Ports opened successfully."

    text_box "INFO" "Downloading and setup node..."
    curl -sSfL --progress-bar 'https://github.com/GaiaNet-AI/gaianet-node/releases/latest/download/install.sh' | bash
    text_box "DONE" "Node setup successfully."

    text_box "INFO" "Setting environment variables..."
    export PATH="$HOME/gaianet/bin:$PATH"
    echo "export PATH=\"$HOME/gaianet/bin:\$PATH\"" >> "$HOME/.bashrc"
    text_box "DONE" "Setting environment variables successfully."

    sleep 10

    if ! command -v gaianet &> /dev/null; then
        text_box "ERROR" "Error: gaianet not found! The path $HOME/gaianet/bin is not added to PATH or gaianet is missing."
        exit 1
    else
        text_box "INFO" "Gaianet found successfully!"
    fi

    text_box "INFO" "Node initialization..."
    gaianet init --config https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/qwen2-0.5b-instruct/config.json
    text_box "DONE" "Node initialization successfully."

    text_box "INFO" "Run node..."
    gaianet start
    text_box "DONE" "Node has been successfully launched."

    text_box "DONE" "${NAME} installed successfully."
    return 0
}

# Function to install talk bot for Gaia
install_talk_bot() {
    text_box "TITLE" "Updating node ${NAME}..."

    text_box "INFO" "Configuration..."
    cd
    mkdir -p ~/gaia-bot
    cd ~/gaia-bot

    # Questions...
    text_box "INFO" "Upload the first 1000 questions (or more) and choose 100 random ones..."
    SOURCE_FILE="https://ksalab.xyz/dl/gaia_questions.txt"
    DEST_FILE="${HOME}/gaia-bot/phrases.txt"
    touch $DEST_FILE

    curl -s --progress-bar "$SOURCE_FILE" | head -n 1000 | shuf -n 100 > "${DEST_FILE}"
    text_box "DONE" "Selected 100 random questions and stored in the ${DEST_FILE}"

    # Adding roles to roles.txt
    echo -e "system\nuser\nassistant\ntool" > roles.txt

    text_box "INFO" "Download talk bot script..."
    curl -L --progress-bar https://ksalab.xyz/dl/gaia_bot.py -o gaia_bot.py

    text_box "INFO" "Bot customization..."
    echo -e "Enter the address of your node:\n"
    read -p "> " NODE_ID
    
    sed -i "s|\$NODE_ID|$NODE_ID|g" gaia_bot.py

    USERNAME=$(whoami)
    HOME_DIR=$(eval echo ~$USERNAME)

    text_box "INFO" "Setting up and launching the service..."

    # Service for launching a bot
    text_box "INFO" "Creating systemd service for ${NAME} talk bot..."
sudo tee /etc/systemd/system/gaia-bot.service > /dev/null <<EOF
[Unit]
Description=gaia-bot Daemon
After=network-online.target

[Service]
User=$USER
Environment=NODE_ID=$NODE_ID
Environment=RETRY_COUNT=3
Environment=RETRY_DELAY=5
Environment=TIMEOUT=60
WorkingDirectory=$HOME_DIR/gaia-bot
ExecStart=/usr/bin/python3 $HOME_DIR/gaia-bot/gaia_bot.py
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        text_box "ERROR" "Error when creating service file!"
        exit 1
    fi

    text_box "DONE" "Service file created successfully."

    # enable and start service
    text_box "INFO" "Reloading systemd and starting the service..."
    sudo systemctl daemon-reload
    sudo systemctl enable gaia-bot
    sudo systemctl restart gaia-bot
    text_box "DONE" "Bot started successfully!${NC}"

    text_box "INFO" "View bot log..."
    sudo journalctl -fu gaia-bot -o cat --no-hostname

    return 0
}

# Function to check talk bot logs
check_logs_talk_bot() {
    text_box "TITLE" "Checking talk bot logs for ${NAME}..."

    journalctl -fu gaia-bot -o cat

    return 0
}

# Function to restart node
restart_node() {
    text_box "TITLE" "Restart node ${NAME}..."

    source ~/.bashrc

    text_box "INFO" "Stop node..."
    gaianet stop
    text_box "DONE" "Node has been successfully stopped..."

    text_box "INFO" "Run node..."
    gaianet start
    text_box "DONE" "Node has been successfully launched..."

    text_box "DONE" "${NAME} restarted successfully."
    return 0
}

# Function to stop node
stop_node() {
    text_box "TITLE" "Stop ${NAME}..."

    gaianet stop

    text_box "DONE" "${NAME} stopped successfully."
    return 0
}

# Function to node info
node_info() {
    text_box "TITLE" "Node info..."

    source ~/.bashrc

    gaianet info

    echo -e "\n"
    return 0
}

# Function to check node logs
check_node_logs_assistant() {
    text_box "TITLE" "Checking node chat-server.log for ${NAME}..."

    tail -f ~/gaianet/log/chat-server.log

    return 0
}

check_node_logs_frp() {
    text_box "TITLE" "Checking node start-gaia-frp.log for ${NAME}..."

    tail -f ~/gaianet/log/start-gaia-frp.log

    return 0
}

check_node_logs_llama() {
    text_box "TITLE" "Checking node embedding-server.log for ${NAME}..."

    tail -f ~/gaianet/log/embedding-server.log

    return 0
}

check_node_logs_nexus() {
    text_box "TITLE" "Checking node gaia-nexus.log for ${NAME}..."

    tail -f ~/gaianet/log/gaia-nexus.log

    return 0
}

# Function to update node
update_node() {
    text_box "TITLE" "Updating node ${NAME}..."

    stop_node

    text_box "INFO" "Downloading and upgrade node..."
    curl -sSfL --progress-bar 'https://github.com/GaiaNet-AI/gaianet-node/releases/latest/download/install.sh' | bash -s -- --upgrade
    text_box "DONE" "Node upgraded successfully."

    source ~/.bashrc

    curl -LO https://github.com/GaiaNet-AI/gaia-nexus-release/releases/download/0.1.0/llama-api-server.wasm
    mv llama-api-server.wasm ~/gaianet/
    ls -lh ~/gaianet/llama-api-server.wasm

    text_box "INFO" "Run node..."
    gaianet start
    text_box "DONE" "Node has been successfully launched..."

    text_box "DONE" "${NAME} updated successfully."
    return 0
}

# Function to delete node
delete_node() {
    text_box "WARNING" "Make sure you back up your node data before continuing.\n"
    text_box "WARNING" "Yeah, I backed it up: (y/n)"
    read -r backup
    if [[ "$backup" =~ ^[Yy]$ ]]; then
        text_box "INFO" "It's backed up. Continued..."
    else
        text_box "ERROR" "The backup has not been saved. Back to the menu......"
        return 1
    fi

    text_box "INFO" "Stop node ${NAME}..."

    gaianet stop
    rm -rf ~/gaianet

    text_box "OK" "${NAME} deleted successfully."
    return 0
}

delete_talk_bot() {
    text_box "TITLE" "Delete ${NAME} talk bot..."
    text_box "INFO" "Stop talk bot ${NAME}..."

    sudo systemctl stop gaia-bot
    sudo systemctl disable gaia-bot
    # rm -rf ~/gaia-bot

    text_box "OK" "${NAME} talk bot deleted successfully."
    return 0
}
#

# Menu

# Menu options mapping
declare -A ACTIONS=(
    [1]=install_node
    [2]=install_talk_bot
    [3]=check_logs_talk_bot
    [4]=restart_node
    [5]=stop_node
    [6]=node_info
    [7]=check_node_logs_assistant
    [8]=check_node_logs_frp
    [9]=check_node_logs_llama
    [10]=check_node_logs_nexus
    [11]=update_node
    [12]=delete_node
    [13]=delete_talk_bot
    [14]=exit
)

while true
do
    PS3="Select an action for ${NAME}: "
    options=(
        "Install node"
        "Install talk bot"
        "Check talk bot logs"
        "Restart node"
        "Stop node"
        "Node info"
        "Check node logs (chat-server.log)"
        "Check node logs (start-gaia-frp.log)"
        "Check node logs (embedding-server.log)"
        "Check node logs (gaia-nexus.log)"
        "Update node"
        "Delete node"
        "Delete talk bot"
        "Exit"
    )

    select opt in "${options[@]}"; do
        case $REPLY in
            1|2|3|4|5|6|7|8|9|10|11|12|13|14) "${ACTIONS[$REPLY]}"; break ;;
            *) error "Invalid option $REPLY" ;;
        esac
    done
done