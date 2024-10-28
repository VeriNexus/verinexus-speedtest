#!/bin/bash
# File: installer.sh
# Version: 1.8.0
# Date: 28/10/2024

# Description:
# This installer script sets up the VeriNexus Speed Test environment on a new machine.
# It installs necessary dependencies, downloads required scripts, sets up the virtual environment,
# installs Python dependencies, and sets up the mqtt_speedtest.py script as a service.
# It includes improved error handling and ensures correct permissions.

# Version number of the installer script
INSTALLER_VERSION="1.8.0"

# Base directory for the script
BASE_DIR="/home/verinexus/VeriNexus"  # Ensure this is set to your home directory

# URLs to download scripts
SPEEDTEST_SCRIPT_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
WRAPPER_SCRIPT_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest_wrapper.sh"
UPDATE_CRONTAB_SCRIPT_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/update_crontab.sh"
MQTT_SPEEDTEST_SCRIPT_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/mqtt_speedtest.py"

# Paths to scripts
SPEEDTEST_SCRIPT_PATH="$BASE_DIR/speedtest.sh"
WRAPPER_SCRIPT_PATH="$BASE_DIR/speedtest_wrapper.sh"
UPDATE_CRONTAB_SCRIPT_PATH="$BASE_DIR/update_crontab.sh"
MQTT_SPEEDTEST_SCRIPT_PATH="$BASE_DIR/mqtt_speedtest.py"

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Symbols
CHECKMARK="${GREEN}✔${NC}"
CROSS="${RED}✖${NC}"

# Function to print error messages
print_error() {
    echo -e "${CROSS} ${RED}Error: $1${NC}"
    exit 1
}

# Function to install dependencies
install_dependencies() {
    echo -e "${BLUE}Installing necessary dependencies...${NC}"

    # Update package list with lock handling
    wait_for_lock
    sudo apt-get update -y || print_error "Failed to update package list"

    # List of dependencies with actual package names
    dependencies=(
        "python3-venv"
        "python3-pip"
        "gawk"           # GNU awk implementation
        "curl"
        "jq"
        "dnsutils"       # Provides dig
        "speedtest-cli"
        "iputils-ping"
        "iproute2"       # Provides ip command
        "ncurses-bin"    # Provides tput
        "grep"
        "sed"
        "hostname"
        "coreutils"      # Provides date, sleep, and other core utilities
    )

    for dep in "${dependencies[@]}"; do
        echo -e "${BLUE}Installing $dep...${NC}"
        wait_for_lock
        sudo apt-get install -y "$dep" || print_error "Failed to install $dep"
    done
    echo -e "${CHECKMARK}${GREEN} All dependencies installed.${NC}"
}

# Function to wait for package manager lock to be released
wait_for_lock() {
    local max_attempts=30
    local attempt=1
    local lock_file="/var/lib/dpkg/lock-frontend"
    while sudo fuser $lock_file >/dev/null 2>&1; do
        if [ $attempt -eq 1 ]; then
            echo -e "${YELLOW}Package manager is locked by another process. Waiting for it to be released...${NC}"
        fi
        if [ $attempt -ge $max_attempts ]; then
            echo -e "${CROSS}${RED} Timeout reached while waiting for package manager lock. Exiting.${NC}"
            exit 1
        fi
        sleep 5
        attempt=$((attempt + 1))
    done
}

# Ensure the base directory exists and has correct permissions
echo -e "${BLUE}Ensuring base directory exists...${NC}"
if [ ! -d "$BASE_DIR" ]; then
    mkdir -p "$BASE_DIR" || print_error "Failed to create directory $BASE_DIR"
    echo -e "${CHECKMARK}${GREEN} Base directory created at $BASE_DIR${NC}"
else
    echo -e "${CHECKMARK}${GREEN} Base directory already exists at $BASE_DIR${NC}"
fi

# Ensure the current user owns the base directory
sudo chown -R "$USER":"$USER" "$BASE_DIR" || print_error "Failed to set ownership of $BASE_DIR"

# Change to the base directory
cd "$BASE_DIR" || print_error "Failed to change directory to $BASE_DIR"

# Install dependencies
install_dependencies

# Download the latest version of mqtt_speedtest.py
echo -e "${BLUE}Downloading mqtt_speedtest.py...${NC}"
curl -s -o "$MQTT_SPEEDTEST_SCRIPT_PATH" "$MQTT_SPEEDTEST_SCRIPT_URL" || print_error "Failed to download mqtt_speedtest.py"
chmod +x "$MQTT_SPEEDTEST_SCRIPT_PATH" || print_error "Failed to make mqtt_speedtest.py executable"
echo -e "${CHECKMARK}${GREEN} mqtt_speedtest.py downloaded and made executable.${NC}"

# Download the latest version of speedtest_wrapper.sh
echo -e "${BLUE}Downloading speedtest_wrapper.sh...${NC}"
curl -s -o "$WRAPPER_SCRIPT_PATH" "$WRAPPER_SCRIPT_URL" || print_error "Failed to download speedtest_wrapper.sh"
chmod +x "$WRAPPER_SCRIPT_PATH" || print_error "Failed to make speedtest_wrapper.sh executable"
echo -e "${CHECKMARK}${GREEN} speedtest_wrapper.sh downloaded and made executable.${NC}"

# Download the latest version of speedtest.sh
echo -e "${BLUE}Downloading speedtest.sh...${NC}"
curl -s -o "$SPEEDTEST_SCRIPT_PATH" "$SPEEDTEST_SCRIPT_URL" || print_error "Failed to download speedtest.sh"
chmod +x "$SPEEDTEST_SCRIPT_PATH" || print_error "Failed to make speedtest.sh executable"
echo -e "${CHECKMARK}${GREEN} speedtest.sh downloaded and made executable.${NC}"

# Download the latest version of update_crontab.sh
echo -e "${BLUE}Downloading update_crontab.sh...${NC}"
curl -s -o "$UPDATE_CRONTAB_SCRIPT_PATH" "$UPDATE_CRONTAB_SCRIPT_URL" || print_error "Failed to download update_crontab.sh"
chmod +x "$UPDATE_CRONTAB_SCRIPT_PATH" || print_error "Failed to make update_crontab.sh executable"
echo -e "${CHECKMARK}${GREEN} update_crontab.sh downloaded and made executable.${NC}"

# Run speedtest_wrapper.sh
echo -e "${BLUE}Running speedtest_wrapper.sh...${NC}"
"$WRAPPER_SCRIPT_PATH"
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}speedtest_wrapper.sh failed, attempting to run with sudo...${NC}"
    sudo "$WRAPPER_SCRIPT_PATH"
    if [ $? -ne 0 ]; then
        print_error "Failed to execute speedtest_wrapper.sh even with sudo"
    else
        echo -e "${CHECKMARK}${GREEN} speedtest_wrapper.sh executed successfully with sudo.${NC}"
    fi
else
    echo -e "${CHECKMARK}${GREEN} speedtest_wrapper.sh executed successfully.${NC}"
fi

# Set up Python virtual environment
echo -e "${BLUE}Setting up Python virtual environment...${NC}"
if [ ! -d "$BASE_DIR/mqtt-env" ]; then
    python3 -m venv mqtt-env || print_error "Failed to create virtual environment"
    echo -e "${CHECKMARK}${GREEN} Virtual environment created.${NC}"
else
    echo -e "${CHECKMARK}${GREEN} Virtual environment already exists.${NC}"
fi

# Activate virtual environment and install Python dependencies
echo -e "${BLUE}Installing Python dependencies in virtual environment...${NC}"
source mqtt-env/bin/activate || print_error "Failed to activate virtual environment"
# Pre-install dependencies to speed up the process
pip install --upgrade pip
pip install paho-mqtt influxdb || print_error "Failed to install Python dependencies"
deactivate
echo -e "${CHECKMARK}${GREEN} Python dependencies installed.${NC}"

# Create systemd service for mqtt_speedtest.py
echo -e "${BLUE}Setting up systemd service for mqtt_speedtest.py...${NC}"
SERVICE_FILE="/etc/systemd/system/mqtt_speedtest.service"

sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=MQTT Speedtest Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$BASE_DIR
ExecStart=/bin/bash -c 'source $BASE_DIR/mqtt-env/bin/activate && exec python3 mqtt_speedtest.py'
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload || print_error "Failed to reload systemd daemon"
sudo systemctl enable mqtt_speedtest.service || print_error "Failed to enable mqtt_speedtest.service"
sudo systemctl restart mqtt_speedtest.service || print_error "Failed to start mqtt_speedtest.service"
echo -e "${CHECKMARK}${GREEN} mqtt_speedtest.py service set up and started.${NC}"

echo -e "${CHECKMARK}${GREEN} VeriNexus Speed Test environment set up successfully!${NC}"
