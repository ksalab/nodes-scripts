#!/bin/bash

# Set the version variable
NAME="0g (ZeroGravity) Node V3"
BIN_VER="1.1.1"

# Export the version variable to make it available in the sourced script
VER="${NAME} v${BIN_VER}"
export VER

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh) "$VER"; then
  echo "❌ Failed to load utility script!"
  exit 1
fi

#

install_node() {
  # Prompt user for MONIKER value
  read -p "Enter your MONIKER value: " MONIKER

  echo "export MONIKER="$MONIKER"" >> $HOME/.bash_profile
  echo "export OG_PORT="47"" >> $HOME/.bash_profile
  source $HOME/.bash_profile
  export MONIKER="$MONIKER"
  export OG_PORT="47"

  # Get the server's public IP address
  SERVER_IP=$(hostname -I | awk '{print $1}')

  # Change to home directory
  cd $HOME

  # Remove existing galileo and .0gchaind directories if they exist
  sudo systemctl stop 0ggeth
  sudo systemctl stop 0gchaind
  rm -rf galileo
  rm -rf .0gchaind
  sudo rm /usr/local/bin/0gchaind

  # Download and extract Galileo node package
  wget -O galileo.tar.gz https://github.com/0glabs/0gchain-NG/releases/download/v1.1.1/galileo-v1.1.1.tar.gz
  tar -xzvf galileo.tar.gz -C $HOME
  rm -rf $HOME/galileo.tar.gz
  cd galileo

  # Set permissions for geth and 0gchaind binaries
  chmod +x $HOME/galileo/bin/geth
  chmod +x $HOME/galileo/bin/0gchaind

  # Copy files to galileo/0g-home directory
  cp $HOME/galileo/bin/geth $HOME/go/bin/geth
  cp $HOME/galileo/bin/0gchaind $HOME/go/bin/0gchaind

  #Create and copy directory
  mkdir -p $HOME/.0gchaind
  cp -r $HOME/galileo/0g-home $HOME/.0gchaind

  # Initialize Geth with genesis file
  geth init --datadir $HOME/.0gchaind/0g-home/geth-home $HOME/galileo/genesis.json
  geth init --datadir $HOME/.0gchaind/0g-home/geth-home $HOME/galileo/genesis.json

  # Initialize 0gchaind with user-provided MONIKER value
  0gchaind init $MONIKER --home $HOME/.0gchaind/tmp

  # Copy node files to 0gchaind home directory
  cp $HOME/.0gchaind/tmp/data/priv_validator_state.json $HOME/.0gchaind/0g-home/0gchaind-home/data/
  cp $HOME/.0gchaind/tmp/config/node_key.json $HOME/.0gchaind/0g-home/0gchaind-home/config/
  cp $HOME/.0gchaind/tmp/config/priv_validator_key.json $HOME/.0gchaind/0g-home/0gchaind-home/config/
  rm -rf $HOME/.0gchaind/tmp

  # Set moniker in config.toml file
  sed -i -e "s/^moniker *=.*/moniker = \"$MONIKER\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
  sed -i -e "s/^seeds *=.*/seeds = \"bac83a636b003495b2aa6bb123d1450c2ab1a364@og-testnet-seed.itrocket.net:47656\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
  sed -i -e "s/^persistent_peers *=.*/persistent_peers = \"e9e323712e5a2e376449d81664fe71c46e23847a@47.76.92.126:26656,063da5b0a82c22422c6e810aaca8d99897818469@207.180.216.122:26656,6eb4f59d48ef9e6f807eae3d0f3dcc76ba371db6@57.129.2.130:26656,08a2cf407a32be9622104eecac7311c64e1899f5@194.195.87.87:26656,fa39045c86125962fbd359e3de62ea6f8fcce70b@5.196.92.143:26656,6255a894b94fc1099fc22ef5a37f74d383d2a63f@171.247.186.203:26656,f7c7ba6c732ab47d053a65cb8721a83049096b80@37.187.145.113:26656,1037317e7cfaa5600e0a36c91b3fea8f957074b0@134.122.109.208:26656,44a4607f780e4496d3761865faf8dd31723b5d8c@149.50.116.116:14656,24710b2d8beb91cba84b6cf3abe7cfb232ef0270@144.76.70.103:26656,9adf51fde498327cbde4455240e1800472c68e63@65.109.16.218:56656,a4f2aaf24dbd5786852bcf6a2d5c7159c44e6381@8.218.241.139:26656,6a55c5712a23bddfeca6c56545fa62effa8d742c@46.101.226.91:26656,d6e77fbaa0ae9244b86fb5fcb1be399db2e7cb0f@47.76.238.253:26656,dca9f13455bc86c5fc96fd79f3371477c3cc2f33@65.108.140.220:26656,d58e4923150b18edf88b8bd52ee258c71de7f867@207.180.194.201:26656,725e70d2a4e4db89089e05ec9cb1994339adfdc9@62.171.189.242:26656\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml

  # set custom ports in geth-config.toml file
  sed -i "s/HTTPPort = .*/HTTPPort = ${OG_PORT}545/" $HOME/galileo/geth-config.toml
  sed -i "s/WSPort = .*/WSPort = ${OG_PORT}546/" $HOME/galileo/geth-config.toml
  sed -i "s/AuthPort = .*/AuthPort = ${OG_PORT}551/" $HOME/galileo/geth-config.toml
  sed -i "s/ListenAddr = .*/ListenAddr = \":${OG_PORT}303\"/" $HOME/galileo/geth-config.toml
  sed -i "s/^# *Port = .*/# Port = ${OG_PORT}901/" $HOME/galileo/geth-config.toml
  sed -i "s/^# *InfluxDBEndpoint = .*/# InfluxDBEndpoint = \"http:\/\/localhost:${OG_PORT}086\"/" $HOME/galileo/geth-config.toml

  # set custom ports in config.toml file
  sed -i "s/laddr = \"tcp:\/\/0\.0\.0\.0:26656\"/laddr = \"tcp:\/\/0\.0\.0\.0:${OG_PORT}656\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
  sed -i "s/laddr = \"tcp:\/\/127\.0\.0\.1:26657\"/laddr = \"tcp:\/\/0\.0\.0\.0:${OG_PORT}657\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
  sed -i "s/^proxy_app = .*/proxy_app = \"tcp:\/\/127\.0\.0\.1:${OG_PORT}658\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
  sed -i "s/^pprof_laddr = .*/pprof_laddr = \"0\.0\.0\.0:${OG_PORT}060\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
  sed -i "s/prometheus_listen_addr = \".*\"/prometheus_listen_addr = \"0\.0\.0\.0:${OG_PORT}660\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml

  # set custom ports in app.toml file
  sed -i "s/address = \".*:3500\"/address = \"127\.0\.0\.1:${OG_PORT}500\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml
  sed -i "s/^rpc-dial-url *=.*/rpc-dial-url = \"http:\/\/localhost:${OG_PORT}551\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml

  # disable indexer
  sed -i -e "s/^indexer *=.*/indexer = \"null\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml

  # Create 0ggeth systemd file
  sudo tee /etc/systemd/system/0ggeth.service > /dev/null << EOF
[Unit]
Description=0g Geth Node Service
After=network-online.target

[Service]
User=root
WorkingDirectory=/root/galileo
ExecStart=/root/go/bin/geth \
    --config /root/galileo/geth-config.toml \
    --datadir /root/.0gchaind/0g-home/geth-home \
    --networkid 16601 \
    --http.port 47545 \
    --ws.port 47546 \
    --authrpc.port 47551 \
    --bootnodes enode://de7b86d8ac452b1413983049c20eafa2ea0851a3219c2cc12649b971c1677bd83fe24c5331e078471e52a94d95e8cde84cb9d866574fec957124e57ac6056699@8.218.88.60:30303 \
    --port 47303
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  # Create 0gchaind systemd file
  sudo tee /etc/systemd/system/0gchaind.service > /dev/null << EOF
[Unit]
Description=0gchaind Node Service
After=network-online.target

[Service]
User=root
Environment=CHAIN_SPEC=devnet
WorkingDirectory=/root/galileo
ExecStart=/root/go/bin/0gchaind start \
--rpc.laddr tcp://0.0.0.0:47657 \
--chain-spec devnet \
--kzg.trusted-setup-path /root/galileo/kzg-trusted-setup.json \
--engine.jwt-secret-path /root/galileo/jwt-secret.hex \
--kzg.implementation=crate-crypto/go-kzg-4844 \
--block-store-service.enabled \
--node-api.enabled \
--node-api.logging \
--node-api.address 0.0.0.0:47500 \
--pruning=nothing \
--p2p.seeds 85a9b9a1b7fa0969704db2bc37f7c100855a75d9@8.218.88.60:26656 \
--p2p.external_address $(wget -qO- eth0.me):47656 \
--home /root/.0gchaind/0g-home/0gchaind-home
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  echo "0G Snapshot Height: $(curl -s https://files.mictonode.com/0g/snapshot/block-height.txt)"

  cp $HOME/.0gchaind/0g-home/0gchaind-home/data/priv_validator_state.json $HOME/.0gchaind/0g-home/0gchaind-home/priv_validator_state.json.backup
  rm -rf $HOME/.0gchaind/0g-home/0gchaind-home/data
  rm -rf $HOME/.0gchaind/0g-home/geth-home/geth/chaindata
  mkdir -p $HOME/.0gchaind/0g-home/geth-home/geth

  SNAPSHOT_URL="https://files.mictonode.com/0g/snapshot/"
  LATEST_COSMOS=$(curl -s $SNAPSHOT_URL | grep -oP '0g_\d{8}-\d{4}_\d+_cosmos\.tar\.lz4' | sort | tail -n 1)
  LATEST_GETH=$(curl -s $SNAPSHOT_URL | grep -oP '0g_\d{8}-\d{4}_\d+_geth\.tar\.lz4' | sort | tail -n 1)

  if [ -n "$LATEST_COSMOS" ] && [ -n "$LATEST_GETH" ]; then
    COSMOS_URL="${SNAPSHOT_URL}${LATEST_COSMOS}"
    GETH_URL="${SNAPSHOT_URL}${LATEST_GETH}"

    echo "Downloading Cosmos snapshot: $LATEST_COSMOS"
    curl "$COSMOS_URL" | lz4 -dc - | tar -xf - -C $HOME/.0gchaind/0g-home/0gchaind-home

    echo "Downloading Geth snapshot: $LATEST_GETH"
    curl "$GETH_URL" | lz4 -dc - | tar -xf - -C $HOME/.0gchaind/0g-home/geth-home/geth

    mv $HOME/.0gchaind/0g-home/0gchaind-home/priv_validator_state.json.backup $HOME/.0gchaind/0g-home/0gchaind-home/data/priv_validator_state.json
  else
    echo "Snapshot not found."
  fi

  curl https://files.mictonode.com/0g/addrbook/addrbook.json -o $HOME/.0gchaind/0g-home/0gchaind-home/config/addrbook.json

  # Reload systemd, enable, and start services
  sudo systemctl daemon-reload
  # sudo systemctl enable 0ggeth.service
  sudo systemctl restart 0ggeth.service
  # sudo systemctl enable 0gchaind.service
  sudo systemctl restart 0gchaind.service
}

restart_node() {
  text_box "TITLE" "Restart node ${NAME}..."
  sudo systemctl restart 0gchaind.service
  sudo systemctl restart 0ggeth.service
}

stop_node() {
  text_box "TITLE" "Stop node ${NAME}..."
  sudo systemctl stop 0gchaind.service
  sudo systemctl stop 0ggeth.service
}

check_node_logs() {
  text_box "TITLE" "Check node logs ${NAME}..."
  sudo journalctl -fu 0gchaind.service -o cat
}

check_geth_logs() {
  text_box "TITLE" "Check geth logs ${NAME}..."
  sudo journalctl -fu 0ggeth.service -o cat
}

#

# Menu

# Menu options mapping
declare -A ACTIONS=(
  [1]=install_node
  [2]=restart_node
  [3]=stop_node
  [4]=check_node_logs
  [5]=check_geth_logs
  [6]=update_node
  [7]=delete_node
  [8]=exit
)

while true; do
  PS3="Select an action for ${NAME}: "
  options=(
    "Install node"
    "Restart node"
    "Stop node"
    "Check node logs"
    "Check geth logs"
    "Update node"
    "Delete node"
    "Exit"
  )

  select opt in "${options[@]}"; do
    case $REPLY in
      1 | 2 | 3 | 4 | 5 | 6 | 7 | 8)
        "${ACTIONS[$REPLY]}"
        break
        ;;
      *) text_box "ERROR" "Invalid option $REPLY" ;;
    esac
  done
done
