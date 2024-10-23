#!/bin/bash
# File: installer.sh
# Version: 1.4.0
# Date: 23/10/2024

# Description:
# This installer script sets up the VeriNexus Speed Test environment on a new machine.
# It installs necessary dependencies, downloads required scripts, and sets up the crontab.
# It includes handling for package manager locks by waiting until the lock is released.

# Version number of the installer script
INSTALLER_VERSION="1.4.0"

# Base directory for the script
BASE_DIR="/VeriNexus"

# URLs to download scripts
SPEEDTEST_SCRIPT_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
WRAPPER_SCRIPT_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest_wrapper.sh"
UPDATE_CRONTAB_SCRIPT_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/update_crontab.sh"

# Paths to scripts
SPEEDTEST_SCRIPT_PATH="$BASE_DIR/speedtest.sh"
WRAPPER_SCRIPT_PATH="$BASE_DIR/speedtest_wrapper.sh"
UPDATE_CRONTAB_SCRIPT_PATH="$BASE_DIR/update_crontab.sh"

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

# Ensure the base directory exists
echo -e "${BLUE}Ensuring base directory exists...${NC}"
if [ ! -d "$BASE_DIR" ]; then
    mkdir -p "$BASE_DIR" || print_error "Failed to create directory $BASE_DIR"
    echo -e "${CHECKMARK}${GREEN} Base directory created at $BASE_DIR${NC}"
else
    echo -e "${CHECKMARK}${GREEN} Base directory already exists at $BASE_DIR${NC}"
fi

# Change to the base directory
cd "$BASE_DIR" || print_error "Failed to change directory to $BASE_DIR"

# Install dependencies
install_dependencies

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

# Run speedtest_wrapper.sh to set up and run the speed test
echo -e "${BLUE}Running speedtest_wrapper.sh...${NC}"
"$WRAPPER_SCRIPT_PATH" || print_error "Failed to execute speedtest_wrapper.sh"

echo -e "${CHECKMARK}${GREEN} VeriNexus Speed Test environment set up successfully!${NC}"
