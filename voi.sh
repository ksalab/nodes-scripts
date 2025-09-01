#!/bin/bash

account_addr=""
docker_swarm_started=0
voi_home="${HOME}/voi"
headless_install=0
is_root=0
skip_account_setup=0
migrate_host_based_setup=0
wallet_password=""
new_user_setup=0
new_network=0
network_status_url=""
network_identifier=""
staking_url=""
container_id=""
latest_key_end_block=""
previous_network_addresses=""

bold=$(tput bold)
normal=$(tput sgr0)

execute_sudo() {
  if sudo -v &> /dev/null; then
    if [[ $(id -u) -eq 0 ]]; then
      bash -c "$1"
    else
      sudo bash -c "$1"
    fi
  else
    abort "Your user does not have sudo privileges. Exiting the program."
  fi
}

abort() {
  if [[ -z "$2" || "$2" != "true" ]]; then
    if [[ ${docker_swarm_started} -eq 1 ]]; then
      echo "Shutting down docker swarm"
      echo ""
      execute_sudo 'docker swarm leave --force'
    fi
  fi
  echo "$1"
  exit 1
}

execute_docker_command_internal() {
  local interactive=$1
  local command=$2
  local options=""

  if [[ $interactive = "yes" ]]; then
    options="-it"
  fi

  execute_sudo "docker exec -e account_addr=${account_addr} ${options} \"${container_id}\" bash -c \"${command}\""
}

execute_interactive_docker_command() {
  local retries=0
  while [[ $retries -lt 10 ]]; do
    execute_docker_command_internal "yes" "$1"
    local exit_code=$?
    if [[ ${exit_code} -eq 130 ]]; then
      exit ${exit_code} >&2
    fi
    if [[ ${exit_code} -ne 0 ]]; then
      echo "Error executing command. Please try again or press CTRL-C to exit."
      ((retries++))
    else
      break
    fi
  done

  if [[ $retries -eq 10 ]]; then
    abort "Command failed after 10 attempts. Exiting the program."
  fi
}

execute_docker_command() {
  execute_docker_command_internal "no" "$1"
}

cleanup_deprecated_files_and_folders() {
  if [[ -d ${voi_home}/docker-swarm ]]; then
    rm -rf "${voi_home}/docker-swarm" 2>/dev/null || echo "Failed to delete deprecated folder: ${voi_home}/docker-swarm"
  fi
  if [[ -f ${voi_home}/profile ]]; then
    rm -rf "${voi_home}/profile" 2>/dev/null || echo "Failed to delete deprecated file: ${voi_home}/profile"
  fi

  if [[ -f ${voi_home}/.profile ]]; then
    if grep -q "^export VOINETWORK_IMPORT_ACCOUNT=" "${voi_home}/.profile"; then
      sed -i '/^export VOINETWORK_IMPORT_ACCOUNT=/d' "${voi_home}/.profile"
      unset VOINETWORK_IMPORT_ACCOUNT
    fi
  fi
}

start_docker_swarm() {
  local docker_swarm
  docker_swarm=$(execute_sudo 'docker info | grep Swarm | cut -d\  -f3')
  if [[ ${docker_swarm} != "active" ]]; then
    command="docker swarm init"

    if [[ -n ${VOINETWORK_DOCKER_SWARM_INIT_SETTINGS} ]]; then
      command+=" ${VOINETWORK_DOCKER_SWARM_INIT_SETTINGS}"
    else
      command+=" --listen-addr lo --advertise-addr lo"
    fi

    execute_sudo "$command"

    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
      docker_swarm_instructions
    fi

    docker_swarm_started=1
  fi
}

start_stack() {
  case ${VOINETWORK_PROFILE} in
    "relay")
      docker_file="${voi_home}/docker/relay.yml"
      ;;
    "archiver")
      docker_file="${voi_home}/docker/archiver.yml"
      ;;
    "developer")
      docker_file="${voi_home}/docker/developer.yml"
      ;;
    "participation")
      docker_file="${voi_home}/docker/compose.yml"
      ;;
    *)
      abort "Invalid profile. Exiting the program."
      ;;
  esac
  command="source ${voi_home}/.profile && docker stack deploy -c ${docker_file}"

  if [[ -f "${voi_home}/docker/notification.yml" ]]; then
      command+=" -c ${voi_home}/docker/notification.yml"
  fi

  command+=" voinetwork"
  execute_sudo "$command"

  # shellcheck disable=SC2181
  if [[ $? -ne 0 ]]; then
    abort "Error starting stack. Exiting the program."
  fi
}

# shellcheck disable=SC2120
wait_for_stack_to_be_ready() {
  while true; do
    service_info=$(execute_sudo 'docker stack ps voinetwork --format json')
    stack_ready=true

    while read -r line; do
      current_state=$(echo "${line}" | jq -r '.CurrentState')
      desired_state=$(echo "${line}" | jq -r '.DesiredState')

      service_error=$(echo "${line}" | jq -r '.Error')

      if [[ (${desired_state} == "Ready" || ${desired_state} == "Running") && ${current_state} != Running* ]]; then
        stack_ready=false
        break
      fi
    done < <(echo "${service_info}")

    if [[ ${stack_ready} == false && -n ${service_error} ]]; then
      local number_of_interfaces
      number_of_interfaces=$(execute_sudo "ip -d link show | grep vx | wc -l")
      if [[ number_of_interfaces -le 2 ]]; then
        echo "Docker has a network interface that is lingering and preventing startup. We'll attempt to auto-delete it."
        execute_sudo "ip -d link show | grep vx | grep DOWN | awk '{print $2}' | tr -d ':' | xargs -rn1 ip link delete"
        # shellcheck disable=SC2181
        if [[ $? -ne 0 ]]; then
          echo "Docker swarm is unable to start services. https://github.com/moby/libnetwork/issues/1765"
          abort "Exiting the program."
        fi
      elif [[ number_of_interfaces -ge 3 ]]; then
        echo "Docker swarm is unable to start services. https://github.com/moby/libnetwork/issues/1765"
        abort "Multiple vx interfaces found. Please delete all vx interfaces or reboot the server"
      fi
    fi

    echo "Waiting for stack to be ready..."
    sleep 2

    if [[ ${stack_ready} == true ]]; then
      break
    fi
  done

  display_banner "Stack is ready!"
}

function get_container_id() {
  case ${VOINETWORK_PROFILE} in
    "relay")
      container_id=$(docker ps -q -f name=voinetwork_relay)
      ;;
    "developer")
      container_id=$(docker ps -q -f name=voinetwork_developer)
      ;;
    "archiver")
      container_id=$(docker ps -q -f name=voinetwork_archiver)
      ;;
    "participation")
      container_id=$(docker ps -q -f name=voinetwork_algod)
      ;;
    *)
      abort "Invalid profile. Exiting the program."
      ;;
  esac
}

verify_node_is_running() {
  local retries=0
  local max_retries=5

  while [[ $retries -lt $max_retries ]]; do
    if [[ -n "$container_id" ]]; then
      execute_sudo "docker exec ${container_id} bash -c \"curl -sS http://localhost:8080/health > /dev/null\""
      local exit_code=$?
      if [[ $exit_code -eq 0 ]]; then
        break
      fi
    fi

    echo "Error connecting to node. Retrying in 10 seconds..."
    sleep 10
    ((retries++))
  done

  if [[ $retries -eq $max_retries ]]; then
    abort "Error connecting to node after $max_retries attempts. Exiting the program."
  fi
}

get_current_net_round() {
  local retries=0
  local max_retries=5

  while [[ $retries -lt $max_retries ]]; do
    current_net_round=$(curl -s ${network_status_url} | jq -r '.["last-round"]' )
    exit_code=$?

    if [[ $exit_code -eq 0 ]] && [[ -n $current_net_round ]]; then
      break
    fi

    echo "Error fetching network status. Retrying in 5 seconds..."
    sleep 5
    ((retries++))
  done

  if [[ $retries -eq $max_retries ]]; then
    abort "Error fetching network status after $max_retries attempts. Please check your internet connection and try again."
  fi
}

get_node_status() {
    current_node_round=$(execute_docker_command '/node/bin/goal node lastround | head -n 1')
    if [[ ${network_status_url} != "" ]]; then
      get_current_net_round
      current_node_round=${current_node_round//[!0-9]/}
    fi
}

set_network_status_url() {
  case ${VOINETWORK_NETWORK} in
    "mainnet")
      network_status_url="https://mainnet-api.voi.nodely.dev/v2/status"
      ;;
    "betanet")
      network_status_url="https://betanet-api.voi.nodely.dev/v2/status"
      ;;
    "testnet")
      network_status_url="https://testnet-api.voi.nodely.dev/v2/status"
      ;;
    "testnet-v1.1")
      network_status_url="https://testnet-api.voi.nodely.dev/v2/status"
      ;;
    *)
      abort "Unable to find status URL. Swarm is running in the background." true
      ;;
  esac
}

set_staking_url() {
  case ${VOINETWORK_NETWORK} in
  "mainnet")
    staking_url="https://mainnet-idx.nautilus.sh/v1/scs/accounts"
    ;;
  "betanet")
    staking_url="https://betanet-idx.nautilus.sh/v1/scs/accounts"
    ;;
  "testnet")
    staking_url="https://arc72-idx.nautilus.sh/v1/scs/accounts"
    ;;
  "testnet-v1.1")
    staking_url="https://arc72-idx.nautilus.sh/v1/scs/accounts"
    ;;
  *)
    abort "Unable to find staking URL. Exiting the program."
    ;;
  esac
}

set_network_identifier() {
  case ${VOINETWORK_NETWORK} in
    "mainnet")
      network_identifier="voimain-v1.0"
      ;;
    "betanet")
      network_identifier="voibeta-v1.0"
      ;;
    "testnet")
      network_identifier="voitest-v1.1"
      ;;
    "testnet-v1.1")
      network_identifier="voitest-v1.1"
      ;;
    *)
      network_identifier="voimain-v1.0"
      ;;
  esac
}

set_docker_image() {
  if [[ -z ${VOINETWORK_DOCKER_IMAGE} ]]; then
    case ${VOINETWORK_PROFILE} in
      "relay")
        VOINETWORK_DOCKER_IMAGE="ghcr.io/voinetwork/voi-node-${VOINETWORK_NETWORK}:latest"
        ;;
      "developer")
        VOINETWORK_DOCKER_IMAGE="ghcr.io/voinetwork/voi-node-${VOINETWORK_NETWORK}:latest"
        ;;
      "archiver")
        VOINETWORK_DOCKER_IMAGE="ghcr.io/voinetwork/voi-node-${VOINETWORK_NETWORK}:latest"
        ;;
      "participation")
        VOINETWORK_DOCKER_IMAGE="ghcr.io/voinetwork/voi-node-participation-${VOINETWORK_NETWORK}:latest"
        ;;
      *)
        abort "Invalid profile. Exiting the program."
        ;;
    esac
  fi

  update_profile_setting "VOINETWORK_DOCKER_IMAGE" "${VOINETWORK_DOCKER_IMAGE}"
}

get_network_identifier() {
    case $1 in
      "mainnet")
        echo "voimain-v1.0"
        ;;
      "betanet")
        echo "voibeta-v1.0"
        ;;
      "testnet")
        echo "voitest-v1.1"
        ;;
      "testnet-v1.1")
        echo "voitest-v1.1"
        ;;
      *)
        echo "voitest-v1.1"
        ;;
    esac
}

catchup_node() {
  display_banner "Catching up with the network... This might take some time, and numbers might briefly increase"
  set_network_status_url

  get_node_status

  while [[ ${current_node_round} -lt ${current_net_round} ]]; do
    rounds_to_go=$((current_net_round - current_node_round))
    if [[ ${rounds_to_go} -gt 1 ]]; then
      printf "\rWaiting for catchup: %d blocks to go                     " "${rounds_to_go}"
    else
      printf "\rWaiting for catchup: One more block to go!                                           "
    fi
    get_node_status
    sleep 5
  done
  echo ""
  display_banner "Caught up with the network!"
}

ask_for_password() {
  local password
  local password_repeat
  while true; do
    # shellcheck disable=SC2162
    read -sp "Password: " password
    echo
    # shellcheck disable=SC2162
    read -sp "Repeat password: " password_repeat
    echo
    if [[ ${password} == "${password_repeat}" ]]; then
      wallet_password=${password}
      break
    else
      # shellcheck disable=SC2028
      echo -e "\n"
      echo "Passwords do not match. Please try again."
    fi
  done
}

create_wallet() {
  if [[ $(execute_docker_command "/node/bin/goal wallet list | wc -l") -eq 1 ]]; then
    local kmd_token
    echo "Let's create a new wallet for you. Please provide a password for security."

    kmd_token=$(get_kmd_token)

    ask_for_password

read -r -d '' json_data <<EOF
{\"wallet_name\": \"voi\",\"wallet_driver_name\": \"sqlite\", \"wallet_password\": \"${wallet_password}\"}
EOF

    response_code=$(execute_docker_command "curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H 'X-KMD-API-Token: ${kmd_token}' -d '${json_data}' http://localhost:7833/v1/wallet")
    if [[ response_code -ne 200 ]]; then
      abort "Error creating wallet. Exiting the program."
    fi
  else
    echo "Wallet already exists. Skipping wallet creation."
  fi
}

get_account_balance() {
  local balance
  balance=$(execute_docker_command "/node/bin/goal account balance -a $1")
  balance=${balance//[!0-9]/}
  echo "$balance"
}

busy_wait_until_balance_is_sufficient() {
  local balance
  display_banner "Waiting for balance (account: ${account_addr}) to be 0.001 Voi"
  balance=$(get_account_balance "${account_addr}")
  while [[ ${balance} -lt "1000" ]]; do
    echo "Waiting for balance to be 0.001 Voi at minimum"
    balance=$(get_account_balance "${account_addr}")
    sleep 10
  done
  display_banner "Account has balance of 0.001 Voi or greater!"
}

get_account_info() {
  allow_one_account=$1

  if execute_sudo "test ! -f \"/var/lib/voi/algod/data/${network_identifier}/accountList.json\""; then
    return 0
  fi

  accounts_json=$(execute_sudo "cat /var/lib/voi/algod/data/${network_identifier}/accountList.json")
  number_of_accounts=$(echo "${accounts_json}" | jq '.Accounts | length')

  if [[ $number_of_accounts -gt 1 ]]; then
    skip_account_setup=1
    return 1
  elif [[ $number_of_accounts -eq 1 ]] && [[ $allow_one_account != "true" ]]; then
    get_account_address
    skip_account_setup=1
    return 1
  fi

  account_address=$(echo "$accounts_json" | jq '.Accounts | keys[0]')
  echo "${account_address}"
}

check_if_account_exists() {
  allow_one_account_override="$1"

  get_account_info "$allow_one_account_override"
}

get_account_address() {
  local account_address
  account_address=$(get_account_info true)
  account_address=${account_address//\"/}

  if [[ ! "${account_address}" =~ ^[A-Za-z0-9]{58}$ ]]; then
    abort "Invalid account address: \"${account_address}\""
  fi

  account_addr=$account_address
}

get_participation_expiration_eta() {
  local active_key_last_valid_round=$1
  local last_committed_block=$2
  local current_key_blocks_remaining=$((active_key_last_valid_round - last_committed_block))
  local remaining_seconds
  local current_timestamp
  local expiration_timestamp
  local expiration_date

  remaining_seconds=$(echo "${current_key_blocks_remaining}*2.9" | bc)
  current_timestamp=$(date +%s)
  expiration_timestamp=$(echo "${current_timestamp}+${remaining_seconds}" | bc)

  # Convert the new timestamp to a date and time
  expiration_date=$(date -d "@${expiration_timestamp}" '+%Y-%m-%d %H:%M')

  echo "${expiration_date}"
}

get_current_account_keys_info() {
  execute_docker_command "/node/bin/goal account listpartkeys -a $1"
}

get_last_committed_block() {
  execute_docker_command "/node/bin/goal node status" | grep 'Last committed block' | cut -d\  -f4 | tr -d '\r'
}

get_account_addresses() {
  local network_identifier_override
  local local_network_identifier
  network_identifier_override=$1
  local_network_identifier=${network_identifier}

  if [[ -n ${network_identifier_override} ]]; then
    local_network_identifier=${network_identifier_override}
  fi

  if execute_sudo "test ! -f \"/var/lib/voi/algod/data/${local_network_identifier}/accountList.json\""; then
    abort "Account list not found. Exiting the program."
  fi

  accounts_json=$(execute_sudo "cat /var/lib/voi/algod/data/${local_network_identifier}/accountList.json")
  number_of_accounts=$(echo "${accounts_json}" | jq '.Accounts | length')

  if [[ $number_of_accounts -eq 0 ]]; then
    return 1
  fi

  account_addresses=$(echo "$accounts_json" | jq -r '.Accounts | keys[]')
  echo "${account_addresses}"
}

generate_new_key() {
  local address
  local start_block
  local end_block
  local expiration_date

  start_block=$(get_last_committed_block)
  end_block=$((start_block + 2000000))
  expiration_date=$(get_participation_expiration_eta "${end_block}" "${start_block}")
  address=$1
  latest_key_end_block=${end_block}
  echo "Generating participation key for ${address} with start block ${start_block} and end block ${end_block}"
  echo "New key is expected to be valid until: ${expiration_date}"
  execute_interactive_docker_command "/node/bin/goal account addpartkey -a ${address} --roundFirstValid ${start_block} --roundLastValid ${end_block}"
}

ensure_accounts_are_offline() {
  local local_network_identifier
  local_network_identifier=$(get_network_identifier "$1")
  account_addresses=$(get_account_addresses "${local_network_identifier}")
  previous_network_addresses="${account_addresses}"

  if [[ -z ${account_addresses} ]]; then
    return
  fi

#  if [[ ${container_id} == "" ]]; then
#    echo "Skipping account offline check as no existing Voi Swarm container could be found."
#    return
#  fi

#  display_banner "Migrating to new network. Ensuring all accounts are offline."
#
#  echo "Checking if accounts are online and have a balance of 1,000 microVoi or more."
#  echo "Accounts with a balance of 1,000 microVoi or more will be taken offline."
#
#  for account in ${account_addresses}; do
#    local balance
#    balance=$(get_account_balance "${account}")
#    account_status=$(execute_docker_command "/node/bin/goal account dump -a ${account}" | jq -r .onl)
#
#    if [[ ${balance} -ge 1000 && ${account_status} -eq 1 ]]; then
#      echo ""
#      echo "Balance is ${balance} which is above 1,000 microVoi. Taking account ${account} offline."
#      execute_interactive_docker_command "/node/bin/goal account changeonlinestatus -a ${account} -o=false"
#      echo "Account ${account} is now offline!"
#    fi
#  done
}

get_participation_key_id_from_vote_key() {
  local vote_key
  local output
  vote_key=$1

  output=$(execute_docker_command "/node/bin/goal account partkeyinfo")
  echo "${output}" | grep -B 10 "${vote_key}" | grep 'Participation ID:' | head -n 1 | cut -d ':' -f2- | xargs
}

get_most_recent_participation_key_details() {
  local address=$1
  local output

  output=$(execute_docker_command "/node/bin/goal account partkeyinfo")

  local first_round
  first_round=$(echo "$output" | grep -A 4 -B 5 "${latest_key_end_block}" | grep 'First round:' | head -n 1 | cut -d ':' -f2- | xargs)
  local last_round
  last_round=$(echo "$output" | grep -A 4 -B 5 "${latest_key_end_block}" | grep 'Last round:' | head -n 1 | cut -d ':' -f2- | xargs)
  local key_dilution
  key_dilution=$(echo "$output" | grep -A 4 -B 5 "${latest_key_end_block}" | grep 'Key dilution:' | head -n 1 | cut -d ':' -f2- | xargs)
  local selection_key
  selection_key=$(echo "$output" | grep -A 4 -B 5 "${latest_key_end_block}" | grep 'Selection key:' | head -n 1 | cut -d ':' -f2- | xargs)
  local voting_key
  voting_key=$(echo "$output" | grep -A 4 -B 5 "${latest_key_end_block}" | grep 'Voting key:' | head -n 1 | cut -d ':' -f2- | xargs)
  local stateproof_key
  # shellcheck disable=SC2034
  stateproof_key=$(echo "$output" | grep -A 4 -B 5 "${latest_key_end_block}" | grep 'State proof key:' | head -n 1 | cut -d ':' -f2- | xargs)

  key_info_json=$(jq --null-input --arg address "$address" --arg first_round "$first_round" --arg last_round "$last_round" --arg key_dilution "$key_dilution" --arg selection_key "$selection_key" --arg voting_key "$voting_key" --arg stateproof_key "$stateproof_key" '{
    "address": $address,
    "first_round": $first_round,
    "last_valid": $last_round,
    "key_dilution": $key_dilution,
    "selection_key": $selection_key,
    "voting_key": $voting_key,
    "stateproof_key": $stateproof_key
  }')

  echo "${key_info_json}"
}

generate_participation_key() {
  display_banner "Generating/Updating participation key"

  if [[ ${new_network} -eq 1 ]]; then
    display_banner "New network detected: ${VOINETWORK_NETWORK}. Regenerating participation keys for all accounts."

    output=$(execute_docker_command "/node/bin/goal account partkeyinfo")
    participation_ids=$(echo "$output" | grep "Participation ID:" | awk '{print $3}')
    for id in $participation_ids; do
      execute_interactive_docker_command "/node/bin/goal account deletepartkey --partkeyid ${id}"
    done
  fi

  account_addresses=$(get_account_addresses)
  account_addresses_length=$(echo "${account_addresses}" | wc -w)

  for account in ${account_addresses}; do
    local active_key_last_valid_round
    local last_committed_block

    active_key_last_valid_round=$(docker exec -it "${container_id}" bash -c '/node/bin/goal account listpartkeys' | awk -v addr="${account}" '$1=="yes" && substr($2, 1, 4) == substr(addr, 1, 4) && substr($2, length($2)-3) == substr(addr, length(addr)-3) {print $6}' | tr -cd '[:digit:]')

    last_committed_block=$(get_last_committed_block)

    if [[ -z ${active_key_last_valid_round} ]]; then
      if [[ ${new_user_setup} -eq 0 && account_addresses_length -le 1 ]]; then
        return 1
      fi

      if [[ ${account_addresses_length} -eq 1 ]]; then
        generate_new_key "${account}"
      else
        local balance
        balance=$(get_account_balance "${account}")

        if [[ ${balance} -ge 1000 ]]; then
          echo "Balance is equal/above 1,000 microVoi. Generating participation key for account ${account}"
          generate_new_key "${account}"

          change_account_online_status "${account}"
          account_status=$(execute_docker_command "/node/bin/goal account dump -a ${account}" | jq -r .onl)
          if [[ ${account_status} -eq 1 ]]; then
            echo "Account ${account} is now online!"
          else
            echo "Account ${account} is currently offline."
          fi
        else
          echo "Balance is below 1,000 microVoi. Skipping participation key generation for account ${account}"
        fi
        echo ""
      fi
    elif [[ $((active_key_last_valid_round-last_committed_block)) -le 417104 ]]; then
      local existing_expiration_date
      local new_expiration_date
      local current_key_prefix
      local current_key_id
      local end_block

      end_block=$((last_committed_block + 2000000))
      existing_expiration_date=$(get_participation_expiration_eta "${active_key_last_valid_round}" "${last_committed_block}")
      new_expiration_date=$(get_participation_expiration_eta "${end_block}" "${last_committed_block}")

      current_key_prefix=$(docker exec -it "${container_id}" bash -c '/node/bin/goal account listpartkeys' | awk -v addr="${account_address}" '$1=="yes" && substr($2, 1, 4) == substr(addr, 1, 4) && substr($2, length($2)-3) == substr(addr, length(addr)-3) {print $3}' | tr -cd '[:digit:]')
      current_key_id=$(execute_docker_command "/node/bin/goal account partkeyinfo" | grep "${current_key_prefix}" | awk '{print $3}')

      echo "Current participation key for account ${account} is expected to expire at: ${existing_expiration_date}"
      echo "Currently the network is at block: ${last_committed_block}"
      echo "Current participation key expires at block: ${active_key_last_valid_round}"
      echo ""
      echo "This is below the required threshold of 417,104 blocks / ~14 days."
      echo "Generating participation key for account ${account} with end block ${end_block}."

      echo "New key is expected to be valid until: ${new_expiration_date}"
      echo ""
      echo "You will be asked to enter your password to activate the new key."

      execute_interactive_docker_command "/node/bin/goal account renewpartkey -a ${account} --roundLastValid ${end_block}"
      if [[ -n ${current_key_id} ]]; then
        execute_interactive_docker_command "/node/bin/goal account deletepartkey --partkeyid ${current_key_id}"
      fi
    else
      local existing_expiration_date
      existing_expiration_date=$(get_participation_expiration_eta "${active_key_last_valid_round}" "${last_committed_block}")

      echo "Current participation key for account ${account} is expected to expire at: ${existing_expiration_date}"
      echo "This is above the required threshold of 417,104 blocks / ~14 days."
      echo "No new participation key will be generated."
      echo ""
    fi
  done
}

start_kmd() {
  execute_docker_command "/node/bin/goal kmd start -t 600"
}

get_kmd_token() {
  local kmd_token
  kmd_token=$(execute_docker_command "cat /algod/data/kmd-v0.5/kmd.token")
  echo "${kmd_token}"
}

get_algod_token() {
  local algod_token
  algod_token=$(execute_sudo 'cat /var/lib/voi/algod/data/algod.token')
  echo "${algod_token}"
}

display_banner() {
  echo
  echo "********************************************************************************"
  echo "* ${bold}$1${normal}"
  echo "********************************************************************************"
  echo
}

docker_swarm_instructions() {
  echo ""
  echo "Error initializing Docker Swarm."
  echo ""
  echo "To fix this, set VOINETWORK_DOCKER_SWARM_INIT_SETTINGS to the settings you want to use to initialize Docker Swarm and try again."
  echo "Parameters that can be passed to the swarm can be found at: https://docs.docker.com/engine/reference/commandline/swarm_init/"
  echo ""
  if [[ ${VOINETWORK_PROFILE} == "relay" ]]; then
    echo "If you encounter issues, please troubleshoot on your own first."
    echo "If you need further assistance, join #relay-runners on Discord (https://discord.com/invite/vnFbrJrHeW) to engage with the community and get help after describing all troubleshooting steps performed."
    echo "Having a strong grasp of technical details, including the ability to execute commands directly on the server, and understanding cloud resources and logs, is required for managing this setup."
    echo "If you prefer other ways to engage with the community and contribute, consider exploring different options."
  else
    echo "Join #node-resources on Discord (https://discord.com/invite/vnFbrJrHeW) to engage with the community and get help by using the Discord ((https://discord.com/invite/vnFbrJrHeW))."
  fi
  abort "Exiting the program."
}

joined_network_instructions() {
  echo "You can find utility commands for managing your setup in ${voi_home}/bin"

  if [[ ${is_root} -eq 0 ]]; then
    echo ""
    echo "Ensure you restart your shell to use them, or type 'newgrp docker' in your existing shell before using."
  fi

  echo ""
  echo "For useful information, check out:"
  echo " - Voi Swarm documentation: https://voinetwork.github.io/voi-swarm/"
  echo " - Get notified when to renew participation keys: https://voinetwork.github.io/voi-swarm/operating/setup-notifications/"
  echo " - Voi Swarm CLI Tools: https://voinetwork.github.io/voi-swarm/cli-tools/"
  echo ""
  if [[ ${skip_account_setup} -eq 1 ]]; then
    if [[ -z ${account_addr} ]]; then
      echo "Account setup skipped. Multiple accounts detected in your wallet."
    else
      echo "Account setup skipped. Detected existing account with address: ${account_addr}"

      echo "To see network participation status use ${HOME}/voi/bin/get-participation-status ${account_addr}"
      echo "To go online use ${HOME}/voi/bin/go-online ${account_addr}"
    fi
  fi

  # Display information informing the user that the network will catch up in the background if used in non-interactive mode
  if [[ $1 == "true" ]]; then
    echo ""
    echo "The network is now catching up and will continue to do so in the background."
  fi

  if [[ ${VOINETWORK_PROFILE} != "participation" ]]; then
    echo ""
    display_banner "Node setup"
    echo "Due to the nature of ${VOINETWORK_PROFILE} nodes, you will not be able to participate in the consensus network on this server."
    echo ""
    echo "By running this software you acknowledge the following:"
    echo " - It is your responsibility to monitor the software and how it is performing."
    echo " - You are responsible for operating the software and server, this includes, but is not limited to security, maintenance, updates, access controls, and monitoring."
  fi

  echo ""
  echo "To easily access commands from ${voi_home}/bin, add the following to ${HOME}/.bashrc or ${HOME}/.profile:"
  echo "  export PATH=\"\$PATH:${voi_home}/bin\""
  echo ""
  echo "To add to your ~/.bashrc, run:"
  echo "  echo 'export PATH=\"\$PATH:${voi_home}/bin\"' >> ~/.bashrc && source ~/.bashrc"
  echo ""

#  if [[ ${skip_account_setup} -eq 0 && ${VOINETWORK_PROFILE} == "participation" ]]; then
#    echo "${bold}*********************************** READ THIS! ***********************************${normal}"
#    echo "After joining the network, it might take up to 2 hours for your server to appear on telemetry"
#    echo "tracking services. Initially, you can identify your server using the 12-digit short GUID shown by"
#    echo "the command ${voi_home}/bin/get-node-status."
#    echo ""
#    echo "At first, your node's health scores ${bold}will be low${normal}. ${bold}This is normal.${normal}"
#    echo "After running your node for 5-7 days, you should see the health score increase."
#    echo ""
#  fi
}

check_staking_accounts() {
  account_addresses=$(get_account_addresses)

  set_staking_url

  for account in ${account_addresses}; do
    local staking_endpoint
    local response
    local http_code
    local json_response

    staking_endpoint="${staking_url}?owner=${account}&deleted=0"
    response=$(curl -s --max-time 5 -w "%{http_code}" "${staking_endpoint}")
    http_code=$(echo "${response}" | awk '{print substr($0, length($0) - 2)}')
    json_response=$(echo "${response}" | awk '{print substr($0, 1, length($0) - 3)}')

    if [[ "${http_code}" -eq 200 ]]; then
      accounts_length=$(jq '.accounts | length' <<< "${json_response}")
      if [[ "${accounts_length}" -gt 0 ]]; then
        display_banner "Staking contract detected"

        echo "Staking contract has been detected for owner ${account}"
        echo ""

        local balance
        balance=$(get_account_balance "${account}")

        if [[ ${balance} -lt "1000" ]]; then
          echo "Balance is below 0.001 Voi. Skipping staking account setup."
          continue
        fi

        local staking_accounts
        staking_accounts=$(jq -c '.accounts[]' <<< "${json_response}")
        for staking_account in ${staking_accounts}; do
          local last_committed_block
          local contract_address
          local contract_id
          local part_vote_k
          local part_vote_lst
          local participation_key_id

          contract_id=$(jq -r '.contractId' <<< "${staking_account}")
          contract_address=$(jq -r '.contractAddress' <<< "${staking_account}")
          last_committed_block=$(get_last_committed_block)

          part_vote_k=$(jq -r '.part_vote_k' <<< "${staking_account}")
          part_vote_lst=$(jq -r '.part_vote_lst' <<< "${staking_account}")

          # shellcheck disable=SC2046
          participation_key_id=$(get_participation_key_id_from_vote_key "${part_vote_k}")

          if [[ "${part_vote_k}" == "null" || $((part_vote_lst-last_committed_block)) -le 417104 || -z "${participation_key_id}" ]]; then

            if  [[ "${part_vote_k}" == "null" ]]; then
              echo "No staking participation key detected."
            elif [[ -z ${participation_key_id} ]]; then
              echo "Registered staking participation key is not installed locally."
            else
              local existing_expiration_date
              existing_expiration_date=$(get_participation_expiration_eta "${part_vote_lst}" "${last_committed_block}")

              echo "Current participation key for account ${account} is expected to expire at: ${existing_expiration_date}"
              echo "Currently the network is at block: ${last_committed_block}"
              echo "Current participation key expires at block: ${part_vote_lst}"
              echo ""
              echo "This is below the required threshold of 417,104 blocks / ~14 days."
            fi

            echo ""
            echo "Generating new key for owner ${account} and contract address ${contract_address}"

            generate_new_key "${contract_address}"

            local partkey_info
            local voting_key
            local selection_key
            local first_round
            local last_round
            local key_dilution
            local stateproof_key

            partkey_info=$(get_most_recent_participation_key_details "${contract_address}")
            voting_key=$(jq -r '.voting_key' <<< "${partkey_info}")
            selection_key=$(jq -r '.selection_key' <<< "${partkey_info}")
            first_round=$(jq -r '.first_round' <<< "${partkey_info}")
            last_round=$(jq -r '.last_valid' <<< "${partkey_info}")
            key_dilution=$(jq -r '.key_dilution' <<< "${partkey_info}")
            stateproof_key=$(jq -r '.stateproof_key' <<< "${partkey_info}")

            echo "Sending transactions to staking contract ${contract_address} for owner ${account}"
            echo "This will update the staking contract with the new participation key info, allowing participation in the network"
            echo "You will be asked to enter your password multiple times to confirm the transactions."

            execute_interactive_docker_command "/node/bin/goal clerk send -a 1000 -f ${account} -t ${contract_address} --out=/tmp/payment.txn"
            execute_interactive_docker_command "/node/bin/goal app call --app-id ${contract_id} --from ${account} --app-arg 'b64:zSTeiA==' --app-arg 'b64:${voting_key}' --app-arg 'b64:${selection_key}' --app-arg 'int:${first_round}' --app-arg 'int:${last_round}' --app-arg 'int:${key_dilution}' --app-arg 'b64:${stateproof_key}' --out=/tmp/app_call.txn"

            execute_docker_command "cat /tmp/{payment,app_call}.txn > /tmp/combined.txn"
            execute_interactive_docker_command "/node/bin/goal clerk group -i /tmp/combined.txn -o /tmp/grouped.txn > /dev/null"
            execute_interactive_docker_command "/node/bin/goal clerk split -i /tmp/grouped.txn -o /tmp/split.txn > /dev/null"
            execute_interactive_docker_command "/node/bin/goal clerk sign -i /tmp/split-0.txn -o /tmp/signed-0.txn"
            execute_interactive_docker_command "/node/bin/goal clerk sign -i /tmp/split-1.txn -o /tmp/signed-1.txn"
            execute_docker_command "cat /tmp/signed-{0,1}.txn > /tmp/signed-combined.txn"
            execute_interactive_docker_command "/node/bin/goal clerk rawsend -f /tmp/signed-combined.txn"

            if [[ -n ${participation_key_id} ]]; then
              execute_interactive_docker_command "/node/bin/goal account deletepartkey --partkeyid ${participation_key_id}"
            fi
          else
            local existing_expiration_date
            existing_expiration_date=$(get_participation_expiration_eta "${part_vote_lst}" "${last_committed_block}")

            echo "Current staking participation key for owner ${account}, and"
            echo "contract address ${contract_address} is expected to expire at: ${existing_expiration_date}"
            echo "This is above the required threshold of 417,104 blocks / ~14 days."
            echo "No new staking participation key will be generated."
            echo ""
          fi
        done

        echo ""
        echo "${bold}To learn how to use your staking contract visit: https://staking.voi.network${normal}"
      else
        display_banner "No staking contract detected"

        echo "No staking contracts found for owner ${account}. To learn more visit: https://staking.voi.network"
      fi
    fi
  done
}

change_account_online_status() {
  local account
  account=$1
  echo "Enter your password to join the network for account ${account}."
  execute_interactive_docker_command "/node/bin/goal account changeonlinestatus -a ${account}"
}

join_as_new_user() {
  new_user_setup=1
  local account_addresses
  account_addresses=$(get_account_addresses)

  display_banner "Joining network"

  generate_participation_key

  # If there are multiple accounts, we don't want to go online automatically, unless previously done
  # as part of participation key generation.
  if [[ $(echo "$account_addresses" | wc -l) -gt 1 ]]; then
    display_banner "Welcome to Voi!"

    joined_network_instructions

    return
  fi

  busy_wait_until_balance_is_sufficient

  change_account_online_status "${account}"

  account_status=$(execute_docker_command "/node/bin/goal account dump -a ${account}" | jq -r .onl)

  check_staking_accounts

  ## This step is late in the process and does require a restart of the service to take effect.
  ## Container ID from verify_node_running will have to be re-fetched if any use of the node is to be done after this point.
  ## Intentionally not doing this here to avoid confusion.
  migrate_host_based_voi_setup

  if [[ ${account_status} -eq 1 ]]; then
    display_banner "Welcome to Voi! You are now online!"
    joined_network_instructions
  else
    display_banner "Your account ${account_addr} is currently offline."
    echo "There seems to be an issue with going online. Please seek assistance in the #node-runner channel on the Voi Network Discord."
    echo "Join us at: https://discord.com/invite/vnFbrJrHeW"
    abort "Exiting the program."
  fi

  echo "SAVE THIS INFORMATION SECURELY"
  echo "***********************************"
  echo "Your Voi address: ${account_addr}"
  echo "Enter password to get your Voi account recovery mnemonic. Store your mnemonic safely:"

  execute_interactive_docker_command "/node/bin/goal account export -a ${account_addr}"
}

add_docker_groups() {
  if [[ is_root -eq 0 ]]; then
    if [[ ! $(getent group docker)  ]]; then
      execute_sudo "groupadd docker"
    fi
    execute_sudo "usermod -aG docker ${USER}"
  fi
}

get_telemetry_name() {
  if [[ ${VOINETWORK_PROFILE} != "participation" ]] ; then
    return
  fi

  if [[ -f "/var/lib/voi/algod/data/logging.config" ]]; then
    VOINETWORK_TELEMETRY_NAME=$(execute_sudo "cat /var/lib/voi/algod/data/logging.config" | jq -r '.Name')
  fi
}

update_profile_setting() {
  local setting_name="$1"
  local new_value="$2"
  local profile_file="${voi_home}/.profile"

  if [[ -f "$profile_file" ]]; then
    if grep -q "^export ${setting_name}=" "$profile_file"; then
      escaped_value=$(printf '%s\n' "$new_value" | sed 's/[\/&]/\\&/g')
      sed -i "s/^export ${setting_name}=.*/export ${setting_name}=\"${escaped_value}\"/" "$profile_file"
    else
      echo "export ${setting_name}=\"${new_value}\"" >> "$profile_file"
    fi
  else
    touch "$profile_file"
    echo "export ${setting_name}=\"${new_value}\"" >> "$profile_file"
  fi
}

clone_environment_settings_to_profile() {
  printenv | while IFS='=' read -r name value; do
    if [[ $name == VOINETWORK_* && $name != VOINETWORK_IMPORT_ACCOUNT ]]; then
      update_profile_setting "$name" "$value"
    fi
  done
}

set_relay_name() {
  echo "If you are operating a relay node you need to set a relay name in accordance with the naming convention."
  echo "The relay name should be in the format: <two-characters-representing-you>-<provider-code>-<iso-3166-alpha2-country-code>-<supported-iata-airport-code>-<your-chosen-three-digit-identifier>"
  echo ""
  echo "Supported IATA airport codes can be found here: https://github.com/grafana/grafana/blob/main/public/gazetteer/airports.geojson"
  # shellcheck disable=SC2162
  read -p "Relay name: " VOINETWORK_TELEMETRY_NAME

  while [[ ${VOINETWORK_TELEMETRY_NAME} == "" ]]
    do
    # shellcheck disable=SC2162
      read -p "Please enter a relay name: " VOINETWORK_TELEMETRY_NAME
  done

  update_profile_setting "VOINETWORK_TELEMETRY_NAME" "${VOINETWORK_TELEMETRY_NAME}"
}

set_telemetry_name() {
  if [[ ${headless_install} -eq 1 ]]; then
    ## Allow headless install to skip telemetry name setup in case people bring their own wallets / use CI
    return
  fi

  if [[ ${VOINETWORK_PROFILE} == "relay" && -z ${VOINETWORK_TELEMETRY_NAME} ]]; then
    set_relay_name
    return
  elif [[ ${VOINETWORK_PROFILE} == "developer" || ${VOINETWORK_PROFILE} == "archiver" ]]; then
    return
  fi

#  detect_existing_host_based_setup
#
#  if [[ ${migrate_host_based_setup} -eq 1 ]]; then
#    return
#  fi

#  display_banner "Telemetry"

#  if [[ -z ${VOINETWORK_TELEMETRY_NAME} && ! -f "/var/lib/voi/algod/data/logging.config" ]]; then
#    echo "Voi uses telemetry to make the network better and reward users with Voi if participating."
#    echo ""
#    echo "If you wish to opt-in to telemetry sharing, you can provide a telemetry name below."
#    echo "We'll add 'VOI:' at the start to show you're using this package."
#    echo ""
#    echo "To skip telemetry sharing, type 'opt-out' below."
#    echo ""
#    echo "Visit https://voinetwork.github.io/voi-swarm/getting-started/telemetry/ to learn how to set your own custom name."
#    echo ""
#    echo "Enter your telemetry name below to get started."
#    # shellcheck disable=SC2162
#    read -p "Telemetry name: " VOINETWORK_TELEMETRY_NAME
#    if [[ ${VOINETWORK_TELEMETRY_NAME} == "opt-out" ]]; then
#      unset VOINETWORK_TELEMETRY_NAME
#      return
#    else
#      VOINETWORK_TELEMETRY_NAME="VOI:$VOINETWORK_TELEMETRY_NAME"
#      update_profile_setting "VOINETWORK_TELEMETRY_NAME" "${VOINETWORK_TELEMETRY_NAME}"
#    fi
#  elif [[ -n ${VOINETWORK_TELEMETRY_NAME} ]]; then
#    echo "Your telemetry name is already set to '${VOINETWORK_TELEMETRY_NAME}'. To change your telemetry settings, execute the command ${HOME}/voi/bin/set-telemetry-name"
#  else
#    echo "Telemetry is disabled. To enable telemetry, execute the command ${HOME}/voi/bin/set-telemetry-name"
#  fi
}

detect_existing_host_based_setup() {
  if [[ -f /var/lib/algorand/logging.config && ! -f /var/lib/voi/algod/data/logging.config ]]; then
    echo "An existing Voi or Algorand installation has been detected on your system."
    echo "We can migrate your existing telemetry configuration to Voi Swarm."
    echo "As part of this process, we will also stop and uninstall the existing service."
    echo "This is necessary to prevent conflicts and ensure that your node can join Voi Swarm as a healthy node."
    echo ""
    echo "Do you want to migrate your existing setup to Voi Swarm? (yes/no)"
    # shellcheck disable=SC2162
    read -p "Migrate existing setup: " prompt
    while [[ ${prompt} != "yes" && ${prompt} != "no" ]]
      do
      # shellcheck disable=SC2162
        read -p "Type either yes or no: " prompt
    done
    if [[ ${prompt} == "yes" ]]; then
      migrate_host_based_setup=1
    fi
  fi
}

migrate_host_based_voi_setup() {
    if [[ ${migrate_host_based_setup} -eq 1 ]]; then
      display_banner "Migrating from host-based setup"
      VOINETWORK_TELEMETRY_NAME=$(execute_sudo "cat /var/lib/algorand/logging.config" | jq -r '.Name')
      bash -c "env VOINETWORK_TELEMETRY_NAME=\"${VOINETWORK_TELEMETRY_NAME}\" ${voi_home}/bin/migrate-from-host-setup"
    fi
}

check_minimum_requirements() {
  if [[ ${headless_install} -eq 1 || ${VOINETWORK_PROFILE} == "developer" || ${VOINETWORK_PROFILE} == "archiver" ]]; then
    ## Allow headless install to skip telemetry name setup in case people bring their own wallets / use CI
    return
  fi

  minimum_cpus=4
  minimum_memory_bytes=6710886
  minimum_memory_gigabytes_pretty=8

  if [[ -n ${VOINETWORK_PROFILE} && ${VOINETWORK_PROFILE} == "relay" ]]; then
    minimum_cpus=8
    minimum_memory_bytes=15938355
    minimum_memory_gigabytes_pretty=16
  fi

  echo "Checking system requirements.."
  echo ""

  num_cores=$(lscpu | grep "^CPU(s):" | awk '{print $2}')

  total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')

  # Check if the number of cores is less than 4 and less (8 GB * 0.8) memory. Reported memory from
  # /proc/meminfo prints out accessible memory, not total memory. We use 80% of the total memory as an approximation,
  # intentionally going too low to allow variability from various cloud providers.
  if [[ ${num_cores} -lt ${minimum_cpus} || ${total_memory} -lt ${minimum_memory_bytes} ]]; then
    echo "*************************************************************************************"
    echo "* ${bold}WARNING: Your system does not meet the minimum requirements to run Voi Swarm effectively.${normal}"
    echo "*************************************************************************************"
    echo "*"
    echo "* Voi Swarm requires at least 4 CPU cores and 8 GB of memory to run effectively."
    echo "*"
    echo "* Your system has:"
    echo "* - CPU cores: ${bold}${num_cores}${normal} CPU cores. ${bold}${minimum_cpus}${normal} is required."
    echo "* - Memory: ${bold}$((total_memory / 1024 / 1024))${normal} GB of accessible memory. ${bold}${minimum_memory_gigabytes_pretty}${normal} GB is required."
    if [[ ${VOINETWORK_PROFILE} == "relay" ]]; then
      echo "*"
      echo "* You are running a relay node profile. Relay nodes require at least 8 CPU cores and 16 GB of memory."
      echo "*"
      echo "* Upgrade your system to meet the minimum requirements to run as a relay node."
      echo "*"
      abort "Exiting the program."
    else
      echo "*"
      echo "* You can still proceed, however, it may not be as beneficial to the network or to you,"
      echo "* as your node won't be able to contribute or earn rewards effectively."
      echo "* You should ${bold}expect poor performance${normal}, and the community may ${bold}not be able to help${normal} you with issues."
      echo "* "
      echo "* If you are running this on a cloud provider, you should consider upgrading your instance to"
      echo "* meet the requirements."
      echo "* "
      echo "* Read more about other options for running a node on:"
      echo "* - https://voinetwork.github.io/voi-swarm/getting-started/introduction/"
      echo "*"
    fi

    echo "* Find other ways to contribute to the network by joining the Voi Network Discord:"
    echo "* - https://discord.com/invite/vnFbrJrHeW"
    echo "*"
    # shellcheck disable=SC2162
    read -p "Type '${bold}acknowledged${normal}' when you're ready to continue: " prompt
    while [[ ${prompt} != "acknowledged" ]]
    do
      # shellcheck disable=SC2162
      read -p "Type 'acknowledged' to continue: " prompt
    done
  else
    echo "Your system meets the minimum requirements to run Voi Swarm effectively."
    echo ""
  fi
}

get_existing_network() {
  profile_path="${voi_home}/.profile"

  if [[ -f "${profile_path}" ]]; then
    voinetwork_network=$(grep -E '^export VOINETWORK_NETWORK=' "${profile_path}" | cut -d'=' -f2 | tr -d '"')
    if [[ -n "${voinetwork_network}" ]]; then
      echo "$voinetwork_network"
      return
    fi
  fi
  echo ""
}

set_profile() {
  if [[ -f "${voi_home}/.profile" ]]; then
      source "${voi_home}/.profile"
  fi

  if [[ -z ${VOINETWORK_PROFILE} ]]; then
    # If VOINETWORK_PROFILE is not set, use default "participation" to profile
    VOINETWORK_PROFILE="participation"
    echo "export VOINETWORK_PROFILE=${VOINETWORK_PROFILE}" >> "${voi_home}/.profile"
  fi

  if [[ -z ${VOINETWORK_NETWORK} ]]; then
    # If VOINETWORK_NETWORK is not set, use default "mainnet" to profile
    VOINETWORK_NETWORK="mainnet"
    echo "export VOINETWORK_NETWORK=${VOINETWORK_NETWORK}" >> "${voi_home}/.profile"
  fi

  display_banner "Setting up Voi Swarm using profile: ${VOINETWORK_PROFILE}, and network: ${VOINETWORK_NETWORK}"
}

get_tarball() {
  local branch
  local filename="voi-swarm.tar.gz"
  if [[ -n ${VOINETWORK_BRANCH} ]]; then
    branch=${VOINETWORK_BRANCH}
  else
    branch="main"
  fi
  curl -sSL https://api.github.com/repos/VoiNetwork/voi-swarm/tarball/"${branch}" --output "${voi_home}/${filename}"
  tar -xzf "${voi_home}/${filename}" -C "${voi_home}" --strip-components=1
  rm "${voi_home}/${filename}"
}

preserve_autoupdate() {
    if [[ ${VOINETWORK_PROFILE} == "relay" ]]; then
      docker_filename="${voi_home}/docker/relay.yml"
    elif [[ ${VOINETWORK_PROFILE} == "developer" ]]; then
      docker_filename="${voi_home}/docker/developer.yml"
    elif [[ ${VOINETWORK_PROFILE} == "archiver" ]]; then
      docker_filename="${voi_home}/docker/archiver.yml"
    else
      docker_filename="${voi_home}/docker/compose.yml"
    fi

    autoupdate_state=$(awk -F'=' '/swarm.cronjob.enable=/ {print $2}' "${docker_filename}")

    if [[ ${autoupdate_state} == "false" ]]; then
      sed -i -E "s/(swarm.cronjob.enable=).*/\1false" "${docker_filename}"
    fi
}

add_update_jitter() {
  case ${VOINETWORK_PROFILE} in
    "relay")
      schedule_filename="${voi_home}/docker/relay.yml"
      ;;
    "developer")
      schedule_filename="${voi_home}/docker/developer.yml"
      ;;
    "archiver")
      schedule_filename="${voi_home}/docker/archiver.yml"
      ;;
    "participation")
      schedule_filename="${voi_home}/docker/compose.yml"
      ;;
    *)
      schedule_filename="${voi_home}/docker/compose.yml"
      ;;
  esac

  random_minute=$(( RANDOM % 60 ))
  # Generate a random number between 0 and 2, and add +1 to shift the range to 1-3
  random_hour=$(( RANDOM % 3 + 1 ))

  new_cron_schedule="${random_minute} */${random_hour} * * *"
  sed -i -E "s|(swarm.cronjob.schedule=).*|\1${new_cron_schedule}|" "${schedule_filename}"
}

if [ -z "${BASH_VERSION:-}" ]; then
  abort "Bash is required to interpret this script."
fi

if [[ $(id -u) -eq 0 ]]; then
  is_root=1
else
  echo "Checking for sudo access, you may be prompted for your password."
  if ! sudo -v &> /dev/null; then
    abort "User does not have sudo access. Please run this script as a user with sudo access."
  fi
fi

# Get Linux OS distribution
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  operating_system_distribution="${ID}"
else
  abort "This script is only meant to be run on Debian or Ubuntu."
fi

# Detect if running in a container; this method is not foolproof
# shellcheck disable=SC2143
if [[ -f /.dockerenv ]]; then
  abort "This script is not meant to be run in a container."
fi

# shellcheck disable=SC2143
if [[ $(uname -r | grep -i "microsoft") ]]; then
  abort "Windows Subsystem for Linux is not supported. Please run this script on a native Linux installation."
fi

if [[ ! (${operating_system_distribution} == "ubuntu" || ${operating_system_distribution} == "debian") ]]; then
  echo "Detected operating system: ${operating_system_distribution}"
  abort "This script is only meant to be run on Debian or Ubuntu."
fi

if [[ -n ${VOINETWORK_SKIP_WALLET_SETUP} && -n ${VOINETWORK_IMPORT_ACCOUNT} ]]; then
  echo "VOINETWORK_IMPORT_ACCOUNT and VOINETWORK_SKIP_WALLET_SETUP are both set. This is not supported at the same time."
  echo ""
  echo "To import an existing account, set VOINETWORK_IMPORT_ACCOUNT=1 and unset VOINETWORK_SKIP_WALLET_SETUP."
  echo ""
  echo "Your Voi are linked to your account. Wallets are created automatically if needed."
  echo "Voi Swarm doesn't support wallet import."
  abort "Exiting the program."
fi

if [[ -n ${VOINETWORK_SKIP_WALLET_SETUP} && ${VOINETWORK_SKIP_WALLET_SETUP} -eq 1 ]] || [[ -n $VOINETWORK_HEADLESS_INSTALL ]]; then
  headless_install=1
fi

display_banner "${bold}Welcome to Voi Swarm${normal}. Let's get started!"

mkdir -p "${voi_home}"
set_network_identifier

existing_network=$(get_existing_network)

clone_environment_settings_to_profile
set_profile
set_docker_image

if [[ ${VOINETWORK_NETWORK} != "${existing_network}" && -n ${existing_network} ]]; then
  new_network=1
elif [[ ${VOINETWORK_NETWORK} == "mainnet" && -z ${existing_network} ]]; then
  ## This is temporary to allow for people that have not run the installer since
  ## mid-August 2024, as there prior to this was no network profile.
  if [[ -e /var/lib/voi/algod/data/voitest-v1 ]]; then
    existing_network="testnet"
    new_network=1
  fi
fi

check_minimum_requirements

if [[ ${new_network} -eq 1 ]]; then
  get_container_id
  ensure_accounts_are_offline "${existing_network}"
fi

#get_telemetry_name
set_telemetry_name

display_banner "Installing Docker"

execute_sudo "apt-get update"
execute_sudo "apt-get install -y ca-certificates curl gnupg"
execute_sudo "install -m 0755 -d /etc/apt/keyrings"

case ${operating_system_distribution} in
  "ubuntu")
    execute_sudo "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg"
    execute_sudo "chmod a+r /etc/apt/keyrings/docker.gpg"
    execute_sudo "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \""$VERSION_CODENAME\"") stable\" > /etc/apt/sources.list.d/docker.list"
    ;;
  "debian")
    execute_sudo "curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg"
    execute_sudo "chmod a+r /etc/apt/keyrings/docker.gpg"
    execute_sudo "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo \""$VERSION_CODENAME\"") stable\" > /etc/apt/sources.list.d/docker.list"
    ;;
esac

execute_sudo "apt-get update"

execute_sudo "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

add_docker_groups

if ! docker --version | grep -q 'Docker version'; then
  echo "Docker installation failed."
  abort "Exiting the program."
fi

## Install script dependencies
execute_sudo "apt-get install -y jq bc pv"

display_banner "Starting stack"

start_docker_swarm

if [[ ! -e /var/lib/voi/algod/data ]]; then
  execute_sudo "mkdir -p /var/lib/voi/algod/data"
fi

if [[ ! -e /var/lib/voi/algod/metrics ]]; then
  execute_sudo "mkdir -p /var/lib/voi/algod/metrics"
fi

if [[ ! -e /var/lib/voi/algod/data/cold-storage && ${VOINETWORK_PROFILE} == "archiver" ]]; then
  execute_sudo "mkdir -p /var/lib/voi/algod/data/cold-storage"
fi

display_banner "Fetching the latest Voi Network updates and scripts."

get_tarball

cleanup_deprecated_files_and_folders

add_update_jitter

start_stack

wait_for_stack_to_be_ready

if [[ ${VOINETWORK_PROFILE} == "participation" ]]; then
  get_container_id
  verify_node_is_running
fi

if [[ ${VOINETWORK_PROFILE} != "participation" || ( -n ${VOINETWORK_SKIP_WALLET_SETUP} && ${VOINETWORK_SKIP_WALLET_SETUP} -eq 1 ) ]]; then
  display_banner "Wallet setup will be skipped."

  joined_network_instructions true

  exit 0
fi

start_kmd

display_banner "Initiating setup for Voi wallets and accounts."

create_wallet

if [[ -n ${VOINETWORK_IMPORT_ACCOUNT} && ${VOINETWORK_IMPORT_ACCOUNT} -eq 1 ]]; then
  if ! (check_if_account_exists true); then
    echo "An account already exists. No need to import, skipping this step."
  else
    echo ""
    echo "Let's proceed to import an account using your existing account mnemonic."
    execute_interactive_docker_command "/node/bin/goal account import"
    get_account_address
  fi

else
  if [[ ${new_network} -eq 1 && -n ${previous_network_addresses} ]]; then
     echo ""
     for account in ${previous_network_addresses}; do
       echo "Let's proceed to import ${account} into ${VOINETWORK_NETWORK} using your existing account mnemonic."
       echo " This is a two-step process, first we will delete the account from the previous network, followed"
       echo " by importing the account into the new network."
       echo ""
       execute_interactive_docker_command "/node/bin/goal account delete -a ${account}"
       execute_interactive_docker_command "/node/bin/goal account import"
     done

    get_account_address
  elif check_if_account_exists; then
    execute_interactive_docker_command "/node/bin/goal account new"
    get_account_address

    if [[ ${VOINETWORK_NETWORK} == "mainnet" ]]; then
      echo "****************************************************************************************************************"
      echo "*    To join the Voi network, do one of these:"
      echo "*"
      echo "*    a) Send at least 1 Voi to your account ${account_addr} from another account"
      echo "*"
      echo "*    OR"
      echo "*"
      echo "*    b) Acquire Voi and send it to your account"
      echo "*       - Go to https://voinetwork.github.io/getting-started/setup-account/#adding-voi-to-your-account"
      echo "*       - Follow the guidance and options available to acquire Voi"
      echo "*"
      echo "* After you've done this, type 'completed' to go on"
      echo "****************************************************************************************************************"
    elif [[ ${VOINETWORK_NETWORK} == "testnet-v1.1" ]]; then
      # Get Voi from faucet
      echo "****************************************************************************************************************"
      echo "*    To join the Voi network, do one of these:"
      echo "*"
      echo "*    a) Send at least 1 testnet Voi to your account ${account_addr} from another account"
      echo "*"
      echo "*    OR"
      echo "*"
      echo "*    b) Get 10 testnet Voi for free:"
      echo "*       - Go to https://faucet.nautilus.sh/"
      echo "*       - Enter your address: ${account_addr}"
      echo "*"
      echo "* After you've done this, type 'completed' to go on"
      echo "****************************************************************************************************************"
    fi
    # shellcheck disable=SC2162
    read -p "Type 'completed' when you're ready to continue: " prompt
    while [[ ${prompt} != "completed" ]]
    do
      # shellcheck disable=SC2162
      read -p "Type 'completed' to continue: " prompt
    done
  fi
fi

# Catchup node before creating participation key and going online
catchup_node

if [[ ${skip_account_setup} -eq 0 || ${new_network} -eq 1 ]]; then
  join_as_new_user
else
  generate_participation_key
  participation_key_generation_status=$?

  ## Catch cases where an install was aborted / user didn't succeed in going online
  ## This can happen where there are no part keys present on the machine, or where there's multiple part keys but
  ## no key is active.
  if [[ ${participation_key_generation_status} -eq 1 ]]; then
    display_banner "Restarting participation key generation"
    echo "Wallet and account detected, but no active participation keys found."
    echo "This could be due to a failed setup or a previous setup that was aborted."

    join_as_new_user
  fi

  check_staking_accounts

  migrate_host_based_voi_setup

  display_banner "Welcome to Voi!"

  joined_network_instructions
fi