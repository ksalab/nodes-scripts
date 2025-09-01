#!/bin/bash

# Set the version variable
NAME="Pipe CDN PoP Cache Node"
BIN_VER="0.3.0"

# Allowed characters for password generation
PASSWORD_CHARS='A-Za-z0-9!@#$%^_=+?.,'

# Variables (default values are empty)
SERVICE_FILE="/etc/systemd/system/popcache.service"
POP_URL="https://ksalab.xyz/dl/pop"
INFO_PORT=8002
GRPC_PORT=8003
HTTP_PORT=80
HTTPS_PORT=443
IP_ADDRESS="$(hostname -I | awk '{print $1}')"
CONFIG_FILE="/opt/popcache/config.json"

VER="${NAME} v${BIN_VER} (TESTNET)"

# Export the version variable to make it available in the sourced script
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

# Ensure the script is run as root

if [ "$EUID" -ne 0 ]; then
    text_box "ERROR" "Please run this script as root (sudo)."
    exit 1
fi

#

#

create_popcache_conf(){
    text_box "INFO" "Creating popcache.conf file..."
    sudo cat > "/etc/sysctl.d/99-popcache.conf" << EOL
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 65535
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.core.wmem_max = 16777216
net.core.rmem_max = 16777216
EOL
    text_box "DONE" "File popcache.conf created successfully."

    text_box "INFO" "Apply the settings from popcache.conf file..."
    sudo sysctl --system
    text_box "DONE" "Settings from popcache.conf applied successfully."
}

increase_file_limits() {
    text_box "INFO" "Increasing file limits for POP Cache Node..."
    # POP Cache Node file limits
    sudo cat > "/etc/security/limits.d/popcache.conf" << EOL
*    hard nofile 65535
*    soft nofile 65535
EOL
    ulimit -n 65535
    text_box "DONE" "File limits for POP Cache Node increased successfully."
}

get_country_by_ip() {
    local IP="$1"
    local API_URL="http://ip-api.com/json/${IP}"

    # Making an HTTP request
    local RESPONSE=$(curl -s "$API_URL")

    # Checking for an empty answer
    if [ -z "$RESPONSE" ]; then
        echo "Error: Empty response from API"
        return 1
    fi

    # Retrieving the status
    local STATUS=$(echo "$RESPONSE" | jq -r '.status')

    if [ "$STATUS" == "success" ]; then
        local COUNTRY=$(echo "$RESPONSE" | jq -r '.country')
        local REGION=$(echo "$RESPONSE" | jq -r '.regionName')
        local CITY=$(echo "$RESPONSE" | jq -r '.city')
        local ADDRESS="$CITY, $REGION, $COUNTRY"
        echo "$ADDRESS"
        return 0
    else
        local MESSAGE=$(echo "$RESPONSE" | jq -r '.message')
        text_box "ERROR" "Invalid IP or API error: $MESSAGE"
        return 1
    fi
}

create_config_json(){
    text_box "INFO" "Creating config.json file..."
    # Request values from the user
    POP_LOCATION=$(get_country_by_ip "$IP_ADDRESS")
    text_box "INFO" "IP: $IP_ADDRESS, Location: POP_LOCATION"

    # Get the amount of RAM in GB
    ram_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    ram_total_mb=$((ram_total_kb / 1024))
    ram_50_70=$(echo "$ram_total_mb * 0.6" | bc | awk '{printf "%.0f", $0}')

    # Get free space on SSD/NVMe (main partition /)
    ssd_free_kb=$(df -k / | tail -1 | awk '{print $4}')
    ssd_free_gb=$((ssd_free_kb / 1024 / 1024))
    ssd_50_70=$(echo "$ssd_free_gb * 0.6" | bc | awk '{printf "%.0f", $0}')

    # Get the number of CPU cores
    cpu_cores=$(nproc)

    read -p "Enter invite code (from email): " INVITE_CODE
    read -p "Enter POP name: " POP_NAME
    read -p "Enter node name: " NODE_NAME
    read -p "Enter your name: " USER_NAME
    read -p "Enter your email: " EMAIL
    read -p "Enter your Discord username: " DISCORD
    read -p "Enter your Solana wallet address: " SOLANA_PUBKEY
    read -p "Enter workers count (CPU total: $cpu_cores): " WORKERS_COUNT
    read -p "Enter RAM limit (RAM total: $ram_total_mb MB (50-70%: $ram_50_70 MB)): " RAM_LIMIT
    read -p "Enter disk cache size (SSD free space: $ssd_free_gb GB (50-70%: $ssd_50_70 GB)): " DISK_CACHE_SIZE
    read -p "Enter your website (include https://): " WEBSITE
    read -p "Enter your Telegram handle: " TELEGRAM

    # JSON generation
    cat > "$CONFIG_FILE" <<EOF
{
  "pop_name": "$POP_NAME",
  "pop_location": "$POP_LOCATION",
  "invite_code": "$INVITE_CODE",
  "server": {
    "host": "0.0.0.0",
    "port": 443,
    "http_port": 80,
    "workers": $WORKERS_COUNT
  },
  "cache_config": {
    "memory_cache_size_mb": $RAM_LIMIT,
    "disk_cache_path": "./cache",
    "disk_cache_size_gb": $DISK_CACHE_SIZE,
    "default_ttl_seconds": 86400,
    "respect_origin_headers": true,
    "max_cacheable_size_mb": 1024
  },
  "api_endpoints": {
    "base_url": "https://dataplane.pipenetwork.com"
  },
  "identity_config": {
    "node_name": "$NODE_NAME",
    "name": "$USER_NAME",
    "email": "$EMAIL",
    "website": "$WEBSITE",
    "discord": "$DISCORD",
    "telegram": "$TELEGRAM",
    "solana_pubkey": "$SOLANA_PUBKEY"
  }
}
EOF
    text_box "DONE" "JSON config saved to $CONFIG_FILE"
}

log_rotation_config() {
    text_box "INFO" "Creating log rotation config..."
    cat > "/etc/logrotate.d/popcache" <<EOF
/opt/popcache/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl reload popcache >/dev/null 2>&1 || true
    endscript
}
EOF
    text_box "DONE" "Log rotation config created successfully."
}

# Function to install node
install_node() {
    text_box "TITLE" "Installing ${NAME} node..."
    cd

    # Step 1: Ask for download URLs if not provided

    if [ -z "$POP_URL" ]; then
        while [ -z "$POP_URL" ]; do
            text_box "INFO" "Please enter the URL for pipe-tool (POP_URL):"
            read -r POP_URL
            if [ -z "$POP_URL" ]; then
                text_box "ERROR" "POP_URL cannot be empty. Please provide a valid URL."
            fi
        done
    fi

    # Step 2: Check and set ports

    # text_box "INFO" "Checking if default ports are available..."

    # for port_var in GRPC_PORT INFO_PORT; do
    #     while check_port_usage "${!port_var}"; do
    #         text_box "WARNING" "Port ${!port_var} is in use. Please enter a new ${port_var/:_PORT/} port:"
    #         read -r "$port_var"
    #     done
    # done

    # for port_var in HTTP_PORT HTTPS_PORT; do
    #     if check_port_usage "${!port_var}"; then
    #         text_box "ERROR" "Port ${!port_var} is already in use. It's impossible to continue. Release the ports ($HTTP_PORT, $HTTPS_PORT) and repeat the installation from the beginning...."
    #         exit 1
    #     fi
    # done

    # Step 3: Open necessary ports using UFW

    text_box "INFO" "Opening required ports..."
    for port in ${GRPC_PORT}/tcp ${INFO_PORT}/tcp ${HTTP_PORT} ${HTTPS_PORT}; do
        sudo ufw allow "$port" || { text_box "ERROR" "Failed to open port $port"; exit 1; }
    done
    sudo ufw reload || { text_box "ERROR" "Failed to reload UFW"; exit 1; }
    text_box "DONE" "Required ports opened successfully."

    # Step 4: Create the installation directory

    text_box "INFO" "Creating installation directory (/opt/popcache)..."
    sudo mkdir -p /opt/popcache || { text_box "ERROR" "Failed to create /opt/popcache directory"; exit 1; }
    sudo mkdir -p /opt/popcache/logs || { text_box "ERROR" "Failed to create /opt/popcache/logs directory"; exit 1; }
    touch /opt/popcache/logs/stdout.log || { text_box "ERROR" "Failed to create stdout.log"; exit 1; }
    touch /opt/popcache/logs/stderr.log || { text_box "ERROR" "Failed to create stderr.log"; exit 1; }
    cd /opt/popcache || { text_box "ERROR" "Failed to change directory to /opt/popcache"; exit 1; }
    text_box "DONE" "Installation directory (/opt/popcache) created successfully."

    # Step 5: Download binaries

    text_box "INFO" "Downloading pop binary..."
    sudo curl -L "$POP_URL" -o /opt/popcache/pop || { text_box "ERROR" "Failed to download pop binary"; exit 1; }
    text_box "DONE" "pop binary downloaded successfully."

    # Step 6: Make binaries executable

    text_box "INFO" "Making binaries executable..."
    sudo chmod +x /opt/popcache/pop || { text_box "ERROR" "Failed to make pop executable"; exit 1; }
    text_box "DONE" "Binaries made executable successfully."

    # Step 7: Request info for testnet and create config.json
    create_popcache_conf
    increase_file_limits
    create_config_json

    # Step 8: Create log rotation config
    log_rotation_config

    # Step 9: Create systemd service for pop

    text_box "INFO" "Creating systemd service for popcache..."
    sudo tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=Pipe POP Cache Node Service
After=network.target
Wants=network-online.target

[Service]
User=root
Group=root
WorkingDirectory=/opt/popcache
ExecStart=/opt/popcache/pop
Restart=always
RestartSec=5
LimitNOFILE=65536
StandardOutput=append:/opt/popcache/logs/stdout.log
StandardError=append:/opt/popcache/logs/stderr.log
Environment=POP_CONFIG_PATH=/opt/popcache/config.json
[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        text_box "ERROR" "Error when creating popcache service file!"
        exit 1
    fi
    text_box "DONE" "Systemd popcache service created successfully."

    # Step 10: Set config file symlink and pop alias: prevent dup configs/registrations, convenient pop commands.

    # text_box "INFO" "Create simlink..."
    # ln -sf /opt/dcdn/node_info.json ~/node_info.json
    # grep -q "alias pop='cd /opt/dcdn && /opt/dcdn/pop'" ~/.bashrc || echo "alias pop='cd /opt/dcdn && /opt/dcdn/pop'" >> ~/.bashrc && source ~/.bashrc
    # text_box "DONE" "Created simlink successfully..."

    # Step 11: Reload systemd, enable and start the service

    text_box "INFO" "Reloading systemd and starting the service..."
    sudo systemctl daemon-reload || { text_box "ERROR" "Failed to reload systemd daemon"; exit 1; }
    sudo systemctl enable popcache.service || { text_box "ERROR" "Failed to enable popcache service"; exit 1; }
    sudo systemctl start popcache.service || { text_box "ERROR" "Failed to start popcache service"; exit 1; }
    text_box "DONE" "popcache service started successfully."

    text_box "DONE" "Node ${NAME} installed successfully."
    return 0
}

restart_node() {
    text_box "TITLE" "Restarting ${NAME} node..."
    sudo systemctl restart popcache.service || { text_box "ERROR" "Failed to restart popcache service"; exit 1; }
    text_box "DONE" "${NAME} node restarted successfully."
    return 0
}

stop_node() {
    text_box "TITLE" "Stopping ${NAME} node..."
    sudo systemctl stop popcache.service || { text_box "ERROR" "Failed to stop popcache service"; exit 1; }
    text_box "DONE" "${NAME} node stopped successfully."
    return 0
}

# Function to check node logs
check_node_logs() {
    text_box "TITLE" "Checking ${NAME} node logs..."
    sudo journalctl -fu popcache -o cat --no-hostname
    return 0
}

check_app_logs() {
    text_box "TITLE" "Checking ${NAME} app logs..."
    tail -f /opt/popcache/logs/stderr.log &
    tail -f /opt/popcache/logs/stdout.log
    return 0
}

# Function to check node stats
check_node_stats() {
    text_box "TITLE" "Checking ${NAME} node stats..."
    curl http://localhost/state
    return 0
}

# Function to check node metrics
check_node_metrics() {
    text_box "TITLE" "Checking ${NAME} node metrics..."
    curl http://localhost/metrics
    return 0
}

# Function to check node the health endpoint
check_node_health() {
    text_box "TITLE" "Checking ${NAME} node health..."
    curl http://localhost/health
    return 0
}

# Function to update node
update_node() {
    text_box "TITLE" "Updating ${NAME} node..."
    # if [ -z "$POP_URL" ]; then
    #     while [ -z "$POP_URL" ]; do
    #         echo -e "\n${GREEN}- Please enter the URL for pop (POP_URL):${RESET}\n"
    #         read -r POP_URL
    #         if [ -z "$POP_URL" ]; then
    #             echo -e "${RED}! POP_URL cannot be empty. Please provide a valid URL.${RESET}\n"
    #         fi
    #     done
    # fi

    # # Step 2: Stop POP process
    # text_box "INFO" "Stopping the pop process..."
    # sudo systemctl stop pop.service || { text_box "ERROR" "Failed to stop pop service"; exit 1; }
    # text_box "DONE" "pop service stopped successfully."

    # # Step 3: Remove files pipe-tool and dcdnd
    # text_box "INFO" "Removing old files pop..."
    # sudo rm -f /opt/dcdn/pop || { text_box "ERROR" "Failed to remove pop"; exit 1; }
    # # sudo rm -f /opt/dcdn/download_cache || { error "Failed to remove /opt/dcdn/download_cache"; exit 1; }
    # text_box "DONE" "Old files removed successfully."

    # # Step 4: Edit service (only for v0.2.6 !!!)
    # text_box "INFO" "Edit service for v0.2.6..."
    # if ! grep -q -- "AmbientCapabilities=CAP_NET_BIND_SERVICE" "$SERVICE_FILE"; then
    #     # If no, added before Restart=always
    #     sed -i "/^\[Service\]/,/^\[/{s|^\(Restart=always\)|AmbientCapabilities=CAP_NET_BIND_SERVICE\n\1|}" "$SERVICE_FILE"
    #     text_box "INFO" "Added string 'AmbientCapabilities=CAP_NET_BIND_SERVICE' in $SERVICE_FILE"
    # fi

    # if ! grep -q -- "CapabilityBoundingSet=CAP_NET_BIND_SERVICE" "$SERVICE_FILE"; then
    #     # If no, added before Restart=always
    #     sed -i "/^\[Service\]/,/^\[/{s|^\(Restart=always\)|CapabilityBoundingSet=CAP_NET_BIND_SERVICE\n\1|}" "$SERVICE_FILE"
    #     text_box "INFO" "Added string 'CapabilityBoundingSet=CAP_NET_BIND_SERVICE' in $SERVICE_FILE"
    # fi

    # # Step 4a: Edit service (only for v0.2.7 v0.2.8 !!!)
    # text_box "INFO" "Edit service for v0.2.7-0.2.8..."
    # if ! grep -q -- "--enable-80-443" "$SERVICE_FILE"; then
    #     # If no, added before --cache-dir
    #     sed -i "s|--cache-dir /opt/dcdn/download_cache|--enable-80-443 --cache-dir /opt/dcdn/download_cache|" "$SERVICE_FILE"
    #     info "Added string '--enable-80-443' in $SERVICE_FILE"
    # else
    #     text_box "WARNING" "String '--enable-80-443' already exists in $SERVICE_FILE. No change."
    # fi

    # text_box "DONE" "Service edited successfully."

    # # Step 5: Download binaries
    # text_box "INFO" "Downloading new pop binary..."
    # sudo curl -L "$POP_URL" -o /opt/dcdn/pop || { text_box "ERROR" "Failed to download pop binary"; exit 1; }
    # text_box "DONE" "pop binary downloaded successfully."

    # # Step 6: Make binaries executable
    # text_box "INFO" "Making binaries executable..."
    # sudo chmod +x /opt/dcdn/pop || { text_box "ERROR" "Failed to make pop executable"; exit 1; }
    # text_box "DONE" "Binaries made executable successfully."

    # # Step 7: Open necessary ports using UFW
    # text_box "INFO" "Opening required ports..."
    # sudo ufw allow "$HTTPS_PORT"/tcp || { text_box "ERROR" "Failed to open port $HTTPS_PORT"; exit 1; }
    # sudo ufw allow "$HTTP_PORT"/tcp || { text_box "ERROR" "Failed to open port $HTTP_PORT"; exit 1; }
    # sudo ufw reload || { text_box "ERROR" "Failed to reload UFW"; exit 1; }
    # text_box "DONE" "Required ports ($HTTPS_PORT, $HTTP_PORT) opened successfully."

    # # Step 8: Reload systemd, enable and start the service
    # text_box "INFO" "Reloading systemd and starting the service..."
    # sudo systemctl daemon-reload || { text_box "ERROR" "Failed to reload systemd daemon"; exit 1; }
    # #sudo systemctl enable pop.service || { error "Failed to enable pop service"; exit 1; }
    # sudo systemctl restart pop.service || { text_box "ERROR" "Failed to restart pop service"; exit 1; }
    # text_box "DONE" "pop service started successfully."

    # /opt/dcdn/pop --version

    # # Step 9: Display the log of the pop service
    # #title "Checking the service log..."
    # #sudo journalctl -u pop -f --no-hostname -o cat || { error "Failed to check service log"; exit 1; }
    # #info "Service log checked successfully."

    # text_box "DONE" "Node updated successfully."
    exit 0
}

# Function to delete node
delete_node() {
    text_box "TITLE" "Deleting ${NAME} node..."
    # text_box "WARNING" "Make sure you back up your node data ($HOME/.permissionless folder) before continuing.\nYeah, I backed it up: (y/n)"
    # read -r backup
    # if [[ "$backup" =~ ^[Yy]$ ]]; then
    #     text_box "INFO" "It's backed up. Continued..."
    # else
    #     text_box "ERROR" "The backup has not been saved. Back to the menu......"
    #     return 1
    # fi

    # # Stop and remove Pipe Network node service
    # text_box "INFO" "Stopping and disabling the pop process..."
    # sudo systemctl stop pop.service || { text_box "ERROR" "Failed to stop pop service"; exit 1; }
    # sudo systemctl disable pop.service || { text_box "ERROR" "Failed to disable pop service"; exit 1; }
    # text_box "DONE" "pop service stopped and disabled successfully."

    # text_box "INFO" "Removing the pop process..."
    # sudo rm /etc/systemd/system/pop.service || { text_box "ERROR" "Failed to remove pop service"; exit 1; }
    # text_box "DONE" "pop service removed successfully."

    # sudo systemctl daemon-reload

    # # Stop and remove Pipe Network node dcdnd binaries
    # text_box "INFO" "Removing the pop binaries..."
    # sudo rm -r /opt/dcdn/pop || { text_box "ERROR" "Failed to remove pop binaries"; exit 1; }
    # text_box "DONE" "pop binaries removed successfully."

    # # Request user to enter node_id
    # node_id=""
    # while [ -z "$node_id" ]; do
    #     text_box "WARNING" "To continue, you need to enter the node_id of your node:"
    #     read -r node_id
    #     if [ -z "$node_id" ]; then
    #         text_box "ERROR" "Node ID cannot be empty. Please try again."
    #     fi
    # done

    # # Delete a node completely
    # text_box "WARNING" "Do you want to delete the node completely (it will be impossible to recover)? If you are migrating the node to a new server, skip this item."
    # read -r confirm
    # if [[ "$confirm" =~ ^[Yy]$ ]]; then
    #     # Check if pop is installed
    #     if [ ! -x "/opt/dcdn/pop" ]; then
    #         text_box "ERROR" "pop is not installed. Cannot decommission the node."
    #         return 1
    #     fi

    #     # Remove the folder containing the tokens
    #     text_box "WARNING" "Removing the folder containing the tokens..."
    #     sudo rm -r ~/.permissionless || { text_box "ERROR" "Failed to remove .permissionless folder"; exit 1; }
    #     text_box "DONE" "Folder containing the tokens removed successfully."
    # else
    #     text_box "WARNING" "Delete canceled."
    # fi

    # # Stop and remove Pipe Network node pop binaries
    # text_box "INFO" "Removing the pop binaries..."
    # sudo rm -r /opt/dcdn/pop || { text_box "ERROR" "Failed to remove pop binaries"; exit 1; }
    # text_box "DONE" "pop binaries removed successfully."

    # # Remove the dcdn folder from /opt
    # text_box "INFO" "Removing the dcdn folder from /opt..."
    # sudo rm -r /opt/dcdn || { text_box "ERROR" "Failed to remove dcdn folder from /opt"; exit 1; }
    # text_box "DONE" "dcdn folder removed successfully."

    # text_box "DONE" " ${NAME} node deleted successfully."
    return 0
}

#

# Menu options mapping
declare -A ACTIONS=(
    [1]=install_node
    [2]=restart_node
    [3]=stop_node
    [4]=check_node_logs
    [5]=check_app_logs
    [6]=check_node_health
    [7]=check_node_metrics
    [8]=check_node_stats
    [9]=update_node
    [10]=delete_node
    [11]=exit
)

# If the run= parameter is passed, execute the desired item
if [[ -n "$RUN_OPTION" && "$RUN_OPTION" =~ ^[1-6]$ ]]; then
    "${ACTIONS[$RUN_OPTION]}"
    exit 0
fi

#inner() {
while true
do
    PS3="Select an action for ${NAME}: "
    options=(
        "Install node"
        "Restart node"
        "Stop node"
        "Check node logs"
        "Check app logs"
        "Check node health"
        "Check node metrics"
        "Check node stats"
        "Update node"
        "Delete node"
        "Exit"
    )

    select opt in "${options[@]}"; do
        case $REPLY in
            1|2|3|4|5|6|7|8|9|10|11) "${ACTIONS[$REPLY]}"; break ;;
            *) text_box "ERROR" "Invalid option $REPLY" ;;
        esac
    done
done
