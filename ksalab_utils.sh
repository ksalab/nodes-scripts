#!/bin/bash

# Define colors
RESET=$'\e[0m'               # Reset to default
GRAY=$'\e[38;5;244m'         # Gray
LIGHT_GRAY=$'\e[38;5;250m'   # Light gray
GREEN=$'\e[38;5;34m'         # Green
LIGHT_GREEN=$'\e[38;5;46m'   # Light green
RED=$'\e[38;5;196m'          # Red
LIGHT_RED=$'\e[38;5;203m'    # Light red
BLUE=$'\e[38;5;39m'          # Blue
LIGHT_BLUE=$'\e[38;5;51m'    # Light blue
PURPLE=$'\e[38;5;141m'       # Purple
LIGHT_PURPLE=$'\e[38;5;183m' # Light purple
ORANGE=$'\e[38;5;214m'       # Orange
YELLOW=$'\e[38;5;226m'       # Yellow
CYAN=$'\e[38;5;44m'          # Cyan
LIGHT_CYAN=$'\e[38;5;87m'    # Light cyan
PINK=$'\e[38;5;213m'         # Pink
BROWN=$'\e[38;5;94m'         # Brown
WHITE=$'\e[38;5;231m'        # White
BLACK=$'\e[38;5;16m'         # Black

# -------------------------------------------------------------------
# System settings
# -------------------------------------------------------------------

function text_box() {
  local header_text="${1^^}"
  local message=$(echo "$2" | fold -sw $(($(tput cols) - 4))) # Maximum text size, determined by terminal size - 4
  local color="$3"

  # Check input parameters
  if [[ -z "$header_text" || -z "$message" ]]; then
    echo "Error: Missing required parameters (header_text or message)."
    return 1
  fi

  # Set the frame color
  local reset=$'\e[0m'
  local frame_color=$(get_frame_color "$header_text")

  # If no text color is specified, use the frame color
  local text_color
  if [[ -n $color ]]; then
    text_color=$"\e[38;5;"$color"m"
  else
    text_color=$frame_color
  fi

  # Split the message into lines
  local IFS=$'\n'
  local lines=($message)
  local max_length=0

  # Find the maximum length of the string
  for line in "${lines[@]}"; do
    local len=${#line}
    if ((len > max_length)); then
      max_length=$len
    fi
  done

  ((max_length++))

  if [[ "$header_text" == "MAINTITLE" ]]; then
    local border=$(printf "%${max_length}s" "")
    echo -e "${frame_color}╔═${border//?/═}═╗"
    for line in "${lines[@]}"; do
      local padding=$((max_length - ${#line}))
      local padded_line="${text_color}${line}${text_color}$(printf "%${padding}s" " ")$frame_color"
      echo -e "║ ${padded_line} ║"
    done
    echo -e "${frame_color}╚═${border//?/═}═╝${reset}"
  else
    # Form the upper boundary
    local header_padding=$((max_length - ${#header_text}))
    local header=${message:0:header_padding}
    echo -e "${frame_color}╭─${text_color}${header_text}${frame_color}${header//?/─}╮"
    # Form the message lines
    for line in "${lines[@]}"; do
      local padding=$((max_length - ${#line}))
      local padded_line="${text_color}${line}${text_color}$(printf "%${padding}s" " ")$frame_color"
      echo -e "│ ${padded_line}│"
    done
    # Form the lower boundary
    local border=$(printf "%${max_length}s" "")
    echo -e "╰─${border//?/─}╯${reset}"
  fi

  unset border line padding padded_line
}

function get_frame_color() {
  case "$1" in
    DEBUG) echo "$GRAY" ;;            # Gray
    DONE) echo "$GREEN" ;;            # Green
    ERROR) echo "$RED" ;;             # Red
    INFO) echo "$BLUE" ;;             # Blue
    MAINTITLE) echo "$LIGHT_GREEN" ;; # Light green
    NOTE) echo "$LIGHT_BLUE" ;;       # Light blue
    TASK) echo "$PURPLE" ;;           # Purple
    TITLE) echo "$LIGHT_GREEN" ;;     # Light green
    WARNING) echo "$ORANGE" ;;        # Orange
    *) echo "$GRAY" ;;                # Default: Gray
  esac
}

#

# -------------------------------------------------------------------
# Ports
# -------------------------------------------------------------------

check_port_usage() {
  local port=$1
  if lsof -i -P -n | grep -q ":$port"; then
    return 0 # Port is in use
  else
    return 1 # Port is free
  fi
}

# -------------------------------------------------------------------
# GO
# -------------------------------------------------------------------

# Function to check Go versions
check_go_versions() {
  if [[ "$REQUIRED_GO" == "true" ]]; then
    if check_go_installed; then
      get_latest_go_version
      compare_go_versions
    else
      exit 1
    fi
  fi
}

# Checking to install Go and get the current version
check_go_installed() {
  if command -v go &> /dev/null; then
    CURRENT_GO_VERSION=$(go version | awk '{print $3}' | tr -d 'go')
    title "The current installed version of Go: $CURRENT_GO_VERSION"
    return 0
  else
    warning "${YELLOW}" "Go is not installed."
    prompt_for_go_update
    # return 1
  fi
}

# Get the latest available version of Go from the website
get_latest_go_version() {
  title "Get latest available version of Go..."
  LATEST_GO_VERSION=$(curl -s https://go.dev/dl/ | grep -oP '(?<=<a class="download" href="/dl/go)[^"]+' | grep -oP '^\d+\.\d+\.\d+' | sort -V | tail -n 1)
  info "The latest available version of Go: $LATEST_GO_VERSION"
}

# Function to prompt the user for an update
prompt_for_go_update() {
  read -p "Do you want to upgrade Go to a version$LATEST_GO_VERSION? (y/n): " choice
  case "$choice" in
    y | Y)
      title "Beginning Go update..."
      update_go
      ;;
    n | N)
      warning "The update Go has been canceled.\n"
      ;;
    *)
      error "Wrong choice. Update Go canceled.\n"
      ;;
  esac
}

# Function to update Go
update_go() {
  title "Upgrading Go to the $LATEST_GO_VERSION version has begun..."
  if [ -d "/usr/local/go" ]; then
    sudo rm -rf /usr/local/go
  fi
  curl -Ls https://go.dev/dl/go$LATEST_GO_VERSION.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
  rm go$LATEST_GO_VERSION.linux-amd64.tar.gz

  [ ! -f ~/.bash_profile ] && touch ~/.bash_profile
  echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
  source $HOME/.bash_profile
  [ ! -d ~/go/bin ] && mkdir -p ~/go/bin || {
    error "Failed to create ~/go/bin directory"
    exit 1
  }

  info "Go has been successfully updated to version $LATEST_GO_VERSION."
}

# Comparing versions of Go
compare_go_versions() {
  if [[ "$CURRENT_GO_VERSION" == "$LATEST_GO_VERSION" ]]; then
    info "Your version of Go is up to date."
  else
    warning "A new version of Go is available: $LATEST_GO_VERSION. It is recommended to upgrade.\n"
    prompt_for_go_update
  fi
}

# -------------------------------------------------------------------
# Cosmovisor
# -------------------------------------------------------------------

# Function to check Cosmovisor versions
check_cosmovisor_versions() {
  if [[ "$REQUIRED_COSMOVISOR" == "true" ]]; then
    if check_cosmovisor_installed; then
      get_latest_cosmovisor_version
      compare_cosmovisor_versions
    else
      exit 1
    fi
  fi
}

# Function to check if cosmovisor is installed and get the current version
check_cosmovisor_installed() {
  if command -v cosmovisor &> /dev/null; then
    # Redirect errors to /dev/null to hide them
    CURRENT_COSMOVISOR_VERSION=$(cosmovisor version 2>&1 | sed -n 's/^cosmovisor version: v//p')

    if [ -z "$CURRENT_COSMOVISOR_VERSION" ]; then
      warning "Failed to retrieve cosmovisor version."
    else
      title "Current installed cosmovisor version: $CURRENT_COSMOVISOR_VERSION"
    fi
    return 0
  else
    warning "Cosmovisor is not installed."
    prompt_for_cosmovisor_update
    # return 1
  fi
}

# Function to get the latest available cosmovisor version from the website
get_latest_cosmovisor_version() {
  title "Starting curl to get the latest cosmovisor version..."
  LATEST_COSMOVISOR_VERSION=$(curl -s https://pkg.go.dev/cosmossdk.io/tools/cosmovisor?tab=versions | grep -oP '(?<=href="/cosmossdk.io/tools/cosmovisor@v)[^"]+' | grep -oP '^\d+\.\d+\.\d+' | sort -V | tail -n 1)
  info "Latest available cosmovisor version: $LATEST_COSMOVISOR_VERSION"
}

# Function to prompt the user for an update
prompt_for_cosmovisor_update() {
  read -p "Do you want to upgrade Cosmovisor to a version$LATEST_COSMOVISOR_VERSION? (y/n): " choice
  case "$choice" in
    y | Y)
      title "Beginning Cosmovisor update..."
      update_cosmovisor
      ;;
    n | N)
      warning "The update Cosmovisor has been canceled.\n"
      ;;
    *)
      error "Wrong choice. Update Cosmovisor canceled.\n"
      ;;
  esac
}

# Function to update Go
update_cosmovisor() {
  title "Upgrading Cosmovisor to the $LATEST_COSMOVISOR_VERSION version has begun..."
  go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@$LATEST_COSMOVISOR_VERSION
  info "Go has been successfully updated to version $LATEST_GO_VERSION."
}

# Function to compare cosmovisor versions and suggest an update if needed
compare_cosmovisor_versions() {
  if [[ "$CURRENT_COSMOVISOR_VERSION" == "$LATEST_COSMOVISOR_VERSION" ]]; then
    info "Your cosmovisor version is up to date."
  else
    warning "A new cosmovisor version is available: $LATEST_COSMOVISOR_VERSION. Update recommended.\n"
    prompt_for_cosmovisor_update
  fi
}

# -------------------------------------------------------------------
# Cosmos functions
# -------------------------------------------------------------------

# Function to prompt user for moniker
prompt_moniker() {
  title "Selecting a validator moniker"
  while true; do
    read -p "Enter your moniker: " MONIKER
    if [ -n "$MONIKER" ]; then
      export MONIKER
      break
    else
      error "Moniker cannot be empty. Please try again."
    fi
  done
}

# Function to prompt user for validator parameters
prompt_validator_params() {
  # Default values for optional parameters
  local DEFAULT_COMMISSION_RATE="0.1"
  local DEFAULT_COMMISSION_MAX_RATE="0.2"
  local DEFAULT_COMMISSION_MAX_CHANGE_RATE="0.01"

  # Prompt user for commission-rate with default value
  while true; do
    info "Enter commission rate (default: $DEFAULT_COMMISSION_RATE): "
    read -r COMMISSION_RATE
    if [ -z "$COMMISSION_RATE" ]; then
      COMMISSION_RATE="$DEFAULT_COMMISSION_RATE"
      break
    elif [[ "$COMMISSION_RATE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      break
    else
      error "Invalid commission rate. Please enter a valid number."
    fi
  done

  # Prompt user for commission-max-rate with default value
  while true; do
    info "Enter commission max rate (default: $DEFAULT_COMMISSION_MAX_RATE): "
    read -r COMMISSION_MAX_RATE
    if [ -z "$COMMISSION_MAX_RATE" ]; then
      COMMISSION_MAX_RATE="$DEFAULT_COMMISSION_MAX_RATE"
      break
    elif [[ "$COMMISSION_MAX_RATE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      break
    else
      error "Invalid commission max rate. Please enter a valid number."
    fi
  done

  # Prompt user for commission-max-change-rate with default value
  while true; do
    info "Enter commission max change rate (default: $DEFAULT_COMMISSION_MAX_CHANGE_RATE): "
    read -r COMMISSION_MAX_CHANGE_RATE
    if [ -z "$COMMISSION_MAX_CHANGE_RATE" ]; then
      COMMISSION_MAX_CHANGE_RATE="$DEFAULT_COMMISSION_MAX_CHANGE_RATE"
      break
    elif [[ "$COMMISSION_MAX_CHANGE_RATE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      break
    else
      error "Invalid commission max change rate. Please enter a valid number."
    fi
  done

  # Prompt user for identity (optional)
  info "Enter your identity (optional): "
  read -r IDENTITY

  # Prompt user for details (optional)
  info "Enter your details (optional): "
  read -r DETAILS

  # Export variables for use in the main script
  export COMMISSION_RATE
  export COMMISSION_MAX_RATE
  export COMMISSION_MAX_CHANGE_RATE
  export IDENTITY
  export DETAILS
}

# Function to prompt user for port
prompt_port() {
  title "Selecting the series to install the ports"
  while true; do
    read -p "Enter your port (two digits, press Enter to use default $PORT): " USER_PORT
    if [ -z "$USER_PORT" ]; then
      export PORT="$PORT"
      info "Using default port: $PORT"
      break
    elif [[ "$USER_PORT" =~ ^[0-9]{2}$ ]]; then
      export PORT="$USER_PORT"
      info "Using port: $PORT"
      break
    else
      error "Invalid port. Please enter two digits or press Enter to use default $PORT."
    fi
  done
}

# Function to get the latest snapshot info and install it
manage_snapshot() {
  local SNAPSHOTS_DIR="$1"
  local SNAPSHOTS_PATTERN="$2"
  local INSTALL_DIR="$3"

  warning "SNAPSHOTS_DIR: ${SNAPSHOTS_DIR}"
  warning "SNAPSHOTS_PATTERN: ${SNAPSHOTS_PATTERN}"

  # Get the latest snapshot info
  local -a SNAPSHOTS=($(curl -s "$SNAPSHOTS_DIR" | grep -oE "$SNAPSHOTS_PATTERN" | sort -u))

  if [ ${#SNAPSHOTS[@]} -eq 0 ]; then
    error "No snapshots found at $SNAPSHOTS_DIR"
    return 1
  else
    info "Found snapshots: ${SNAPSHOTS[*]}"
  fi

  local LATEST_SNAPSHOT=""
  local LATEST_TIMESTAMP=0

  for SNAPSHOT in "${SNAPSHOTS[@]}"; do
    local URL="${SNAPSHOTS_DIR}${SNAPSHOT}"
    local HEADERS=$(curl -sI "$URL")

    local TIMESTAMP=$(echo "$HEADERS" | grep -i "Last-Modified" | sed 's/Last-Modified: //I; s/last-modified: //' | tr -d '\r' | xargs -I{} date -d "{}" +%s 2> /dev/null || echo 0)
    local CONTENT_LENGTH=$(echo "$HEADERS" | grep -i "Content-Length" | awk '{print $2}')

    info "Checking snapshot: ${SNAPSHOT} (TIMESTAMP: ${TIMESTAMP}, CONTENT_LENGTH: ${CONTENT_LENGTH})"

    if [ "$TIMESTAMP" -gt "$LATEST_TIMESTAMP" ]; then
      LATEST_TIMESTAMP="$TIMESTAMP"
      LATEST_SNAPSHOT="$SNAPSHOT"
    fi
  done

  if [ -z "$LATEST_SNAPSHOT" ]; then
    error "No valid snapshots found!"
    return 1
  fi

  local SNAPSHOT_URL="${SNAPSHOTS_DIR}${LATEST_SNAPSHOT}"

  # File info
  local CONTENT_LENGTH=$(curl -sI "$SNAPSHOT_URL" | grep -i "Content-Length" | awk '{printf "%.2f GB\n", $2/1024/1024/1024}')
  [ -z "$CONTENT_LENGTH" ] && CONTENT_LENGTH="Unknown size"

  local LAST_MODIFIED_DATE=$(date -d "@$LATEST_TIMESTAMP" "+%Y-%m-%d %H:%M:%S")

  title "Latest snapshot: $LATEST_SNAPSHOT"
  info "Snapshot URL: $SNAPSHOT_URL"
  info "Date: ${DATE:-$LAST_MODIFIED_DATE}"
  [ -n "$HEIGHT" ] && info "Height: $HEIGHT"

  # Prompt user to install the snapshot
  while true; do
    read -p "Do you want to install this snapshot? (y/n): " choice
    case "$choice" in
      y | Y)
        # Install the snapshot
        local SNAPSHOT_NAME=$(basename "$SNAPSHOT_URL")
        local TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR" || return 1

        info "Downloading snapshot: $SNAPSHOT_NAME"
        curl -LO "$SNAPSHOT_URL"
        if [ $? -ne 0 ]; then
          error "Failed to download snapshot."
          cd -
          rm -rf "$TEMP_DIR"
          return 1
        fi

        info "Extracting snapshot: $SNAPSHOT_NAME"
        tar -I lz4 -xvf "$SNAPSHOT_NAME" -C "$INSTALL_DIR"
        if [ $? -ne 0 ]; then
          error "Failed to extract snapshot."
          cd -
          rm -rf "$TEMP_DIR"
          return 1
        fi

        # Check if WASM_URL is provided and download/extract wasm
        if [ -n "$WASM_URL" ]; then
          local WASM_NAME=$(basename "$WASM_URL")
          info "Downloading WASM: $WASM_NAME"
          curl -LO "$WASM_URL"
          if [ $? -ne 0 ]; then
            error "Failed to download WASM."
            cd -
            rm -rf "$TEMP_DIR"
            return 1
          fi

          info "Extracting WASM: $WASM_NAME"
          tar -I lz4 -xvf "$WASM_NAME" -C "$INSTALL_DIR"
          if [ $? -ne 0 ]; then
            error "Failed to extract WASM."
            cd -
            rm -rf "$TEMP_DIR"
            return 1
          fi
        fi

        cd -
        rm -rf "$TEMP_DIR"

        info "Snapshot installed successfully."
        return 0
        ;;
      n | N)
        # Continue without installing the snapshot
        info "Continuing without installing the snapshot."
        return 0
        ;;
      *)
        # Invalid input
        error "Invalid choice. Please enter 'y' or 'n'."
        ;;
    esac
  done
}

# -------------------------------------------------------------------
# Docker
# -------------------------------------------------------------------

# Function to install Docker on Ubuntu
install_docker() {
  title "Installing Docker on Ubuntu..."

  # Update package lists and install prerequisites
  sudo apt-get update || {
    error "Failed to update system"
    exit 1
  }
  sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release || {
    error "Failed to install prerequisites"
    exit 1
  }

  # Add Docker's official GPG key
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || {
    error "Failed to add Docker GPG key"
    exit 1
  }

  # Set up the stable repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || {
    error "Failed to add Docker repository"
    exit 1
  }

  # Update package lists again
  sudo apt-get update || {
    error "Failed to update system after adding Docker repository"
    exit 1
  }

  # Install Docker Engine
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || {
    error "Failed to install Docker"
    exit 1
  }

  # Start Docker
  sudo systemctl start docker || {
    error "Failed to start Docker"
    exit 1
  }

  # Enable Docker to start on boot
  sudo systemctl enable docker || {
    error "Failed to enable Docker"
    exit 1
  }

  info "Docker installed and started successfully."
}

# Function to check if Docker is installed and running
check_docker_installed() {
  if ! command -v docker &> /dev/null; then
    warning "Docker could not be found. Do you want to install Docker? (y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      install_docker
    else
      warning "Docker installation skipped. Returning to menu."
      return 1
    fi
  fi
  return 0
}

# Function to check if Docker is running and offer to start it if not
check_docker_running() {
  if ! docker info &> /dev/null; then
    warning "Docker is not running. Do you want to start Docker? (y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      sudo systemctl start docker || {
        error "Failed to start Docker"
        return 1
      }
      # Re-check if Docker is running after attempting to start it
      if docker info &> /dev/null; then
        info "Docker started successfully."
      else
        error "Docker failed to start. Returning to menu."
        return 1
      fi
    else
      warning "Docker start skipped. Returning to menu."
      return 1
    fi
  fi
  return 0
}

# -------------------------------------------------------------------
# Logo
# -------------------------------------------------------------------

# Function to display the logo
display_logo() {
  local VER="$1"
  echo -e "${GREEN}"
  echo -e "     ██╗  ██╗███████╗ █████╗ ██╗      █████╗ ██████╗ "
  echo -e "     ██║ ██╔╝██╔════╝██╔══██╗██║     ██╔══██╗██╔══██╗"
  echo -e "     █████╔╝ ███████╗███████║██║     ███████║██████╔╝"
  echo -e "     ██╔═██╗ ╚════██║██╔══██║██║     ██╔══██║██╔══██╗"
  echo -e "     ██║  ██╗███████║██║  ██║███████╗██║  ██║██████╔╝"
  echo -e "     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝ ${RESET}"
  text_box "MAINTITLE" "${VER}"
  echo -e ""
}

# Check if the version argument is provided
if [ -z "$1" ]; then
  error "Version argument is missing!"
  exit 1
fi

# Call the display_logo function with the provided version
display_logo "$1"

# end
