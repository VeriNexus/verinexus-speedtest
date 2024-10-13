#!/bin/bash

# Main script version
SCRIPT_VERSION="1.1.2"

# Define remote server credentials and file path
REMOTE_USER='root'             # Your remote SSH username
REMOTE_HOST='88.208.225.250'   # Your remote server IP or hostname
REMOTE_PATH='/speedtest/results/speedtest_results.csv'  # Path to the CSV file on the remote server
REMOTE_PASS='**@p3F_1$t'       # SSH password with single quotes

# Function to download files if needed
download_file_if_needed() {
    local file_name=$1
    local latest_version_var=$2

    echo "Checking for updates for $file_name..."
    if [[ ! -f "./$file_name" ]] || [[ $(grep "$latest_version_var" "./$file_name" | cut -d'=' -f2 | tr -d '"') != "${!latest_version_var}" ]]; then
        echo "Updating $file_name to the latest version..."
        curl -s -o "./$file_name" "https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/$file_name"
        chmod +x "./$file_name"
    else
        echo "$file_name is already up to date."
    fi
}

# Define latest versions for components
LATEST_ERROR_HANDLER_VERSION="1.0.6"
LATEST_UPDATE_CHECK_VERSION="1.0.6"
LATEST_RUN_SPEEDTEST_VERSION="1.1.1"
LATEST_UTILS_VERSION="1.0.6"

# Debug: print version variables before downloading updates
echo "DEBUG: Main Script Version: $SCRIPT_VERSION"
echo "DEBUG: LATEST_ERROR_HANDLER_VERSION: $LATEST_ERROR_HANDLER_VERSION"
echo "DEBUG: LATEST_UPDATE_CHECK_VERSION: $LATEST_UPDATE_CHECK_VERSION"
echo "DEBUG: LATEST_RUN_SPEEDTEST_VERSION: $LATEST_RUN_SPEEDTEST_VERSION"
echo "DEBUG: LATEST_UTILS_VERSION: $LATEST_UTILS_VERSION"

# Download and load the latest scripts
download_file_if_needed "error_handler.sh" LATEST_ERROR_HANDLER_VERSION
download_file_if_needed "update_check.sh" LATEST_UPDATE_CHECK_VERSION
download_file_if_needed "run_speedtest.sh" LATEST_RUN_SPEEDTEST_VERSION
download_file_if_needed "utils.sh" LATEST_UTILS_VERSION

# Debug: Verify that each script was downloaded and is executable
if [[ ! -x "./error_handler.sh" ]]; then
    echo "ERROR: error_handler.sh is not executable!"
    exit 1
fi

if [[ ! -x "./update_check.sh" ]]; then
    echo "ERROR: update_check.sh is not executable!"
    exit 1
fi

if [[ ! -x "./run_speedtest.sh" ]]; then
    echo "ERROR: run_speedtest.sh is not executable!"
    exit 1
fi

if [[ ! -x "./utils.sh" ]]; then
    echo "ERROR: utils.sh is not executable!"
    exit 1
fi

# Source the updated scripts
source ./error_handler.sh
source ./update_check.sh
source ./run_speedtest.sh
source ./utils.sh

# ANSI Color Codes and Symbols
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color
CHECKMARK="${GREEN}✔${NC}"
CROSS="${RED}✖${NC}"
BOLD='\033[1m'

# Fancy Progress Bar Function
progress_bar() {
    echo -n -e "["
    for i in {1..50}; do
        echo -n -e "${CYAN}#${NC}"
        sleep 0.02
    done
    echo -e "]"
}

# Check for script updates
echo "Checking for updates for the main script..."
check_for_updates

# Debug: print component versions after update check
echo "DEBUG: Main Script Version after update check: $SCRIPT_VERSION"

# Display versions for all components
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Component Versions${NC}"
echo -e "Main Script: ${YELLOW}${SCRIPT_VERSION}${NC} (Current) | ${YELLOW}${LATEST_MAIN_VERSION}${NC} (Latest)"
echo -e "Error Handler: ${YELLOW}${ERROR_HANDLER_VERSION}${NC} (Current) | ${YELLOW}${LATEST_ERROR_HANDLER_VERSION}${NC} (Latest)"
echo -e "Update Check: ${YELLOW}${UPDATE_CHECK_VERSION}${NC} (Current) | ${YELLOW}${LATEST_UPDATE_CHECK_VERSION}${NC} (Latest)"
echo -e "Run Speed Test: ${YELLOW}${RUN_SPEEDTEST_VERSION}${NC} (Current) | ${YELLOW}${LATEST_RUN_SPEEDTEST_VERSION}${NC} (Latest)"
echo -e "Utilities: ${YELLOW}${UTILS_VERSION}${NC} (Current) | ${YELLOW}${LATEST_UTILS_VERSION}${NC} (Latest)"
echo -e "${CYAN}====================================================${NC}"

# Apply any forced errors
apply_forced_errors

# Start the progress with a header
echo -e "${BLUE}${BOLD}Starting VeriNexus Speed Test...${NC}"
progress_bar

# Start the speed test process
run_speed_test

# Log any errors if they occur
if [ -n "$ERROR_LOG" ]; then
    echo "Uploading error log..."
    upload_error_log
fi

# Main script footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
