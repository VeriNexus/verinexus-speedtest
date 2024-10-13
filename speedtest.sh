#!/bin/bash

# Main script version
SCRIPT_VERSION="2.0.3"

# Define remote server credentials and file path
REMOTE_USER='root'
REMOTE_HOST='88.208.225.250'
REMOTE_PATH='/speedtest/results/speedtest_results.csv'
REMOTE_PASS='**@p3F_1$t'

# Flag to allow forced downgrade
FORCE_DOWNGRADE=false

# Parse arguments for forced downgrade
for arg in "$@"
do
    if [[ "$arg" == "--forcedowngrade" ]]; then
        FORCE_DOWNGRADE=true
    fi
done

# Function to download files with cache flush and forced downgrade handling
download_file_if_needed() {
    local file_name=$1
    local latest_version_var=$2

    echo "Checking for updates for $file_name..."
    local current_version=$(grep "_VERSION" "./$file_name" | grep -o '[0-9.]\+')

    # Version comparison logic
    if [[ ! -f "./$file_name" ]] || [[ "$FORCE_DOWNGRADE" == "true" ]] || [[ "$current_version" < "${!latest_version_var}" ]]; then
        echo "Updating $file_name to the latest version ($current_version -> ${!latest_version_var})..."
        curl -H 'Cache-Control: no-cache, no-store, must-revalidate' \
             -H 'Pragma: no-cache' \
             -H 'Expires: 0' \
             -o "./$file_name" \
             "https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/$file_name?t=$(date +%s)"

        if [[ $? -eq 0 ]]; then
            echo "$file_name downloaded successfully."
            chmod +x "./$file_name"
        else
            echo "Failed to download $file_name. Please check the URL or network connection."
        fi
    else
        echo "$file_name is already up to date."
    fi
}

# Fetch the latest version by reading the version from the script itself
fetch_latest_version() {
    echo "Fetching the latest script version from GitHub..."
    LATEST_MAIN_VERSION=$(curl -s https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh | grep "SCRIPT_VERSION=" | head -1 | cut -d'"' -f2)
    if [[ -z "$LATEST_MAIN_VERSION" ]]; then
        echo "Error: Failed to retrieve the latest version."
        exit 1
    fi
    echo "DEBUG: Fetched Latest Version: $LATEST_MAIN_VERSION"
}

# Ensure proper version upgrade handling
check_and_update_script() {
    fetch_latest_version

    # Debug: Print current version and latest version variables
    echo "DEBUG: Current Version: $SCRIPT_VERSION"
    echo "DEBUG: Latest Version: $LATEST_MAIN_VERSION"
    echo "DEBUG: Force Downgrade: $FORCE_DOWNGRADE"

    if [[ "$FORCE_DOWNGRADE" == "false" && "$LATEST_MAIN_VERSION" < "$SCRIPT_VERSION" ]]; then
        echo "Error: Downgrade detected! Use --forcedowngrade flag to allow downgrade."
        exit 1
    fi
    
    if [[ "$LATEST_MAIN_VERSION" != "$SCRIPT_VERSION" ]]; then
        echo "Update available for main script: $LATEST_MAIN_VERSION"
        echo "Downloading the latest version..."
        curl -H 'Cache-Control: no-cache, no-store, must-revalidate' \
             -H 'Pragma: no-cache' \
             -H 'Expires: 0' \
             -o "./speedtest.sh" \
             "https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh?t=$(date +%s)"

        if [[ $? -eq 0 ]]; then
            echo "Update downloaded to version $LATEST_MAIN_VERSION. Please re-run the script."
            chmod +x "./speedtest.sh"
            exit 0
        else
            echo "Failed to download the main script update. Continuing with the current version."
        fi
    else
        echo "You are using the latest version: $SCRIPT_VERSION"
    fi
}

# Define the latest versions for each component
LATEST_ERROR_HANDLER_VERSION="1.0.6"
LATEST_UPDATE_CHECK_VERSION="1.1.3"
LATEST_RUN_SPEEDTEST_VERSION="1.1.1"
LATEST_UTILS_VERSION="1.0.6"

# Check for updates and only download if there is a new version or force flag
check_and_update_script

# Download and load the latest scripts
download_file_if_needed "error_handler.sh" LATEST_ERROR_HANDLER_VERSION
download_file_if_needed "update_check.sh" LATEST_UPDATE_CHECK_VERSION
download_file_if_needed "run_speedtest.sh" LATEST_RUN_SPEEDTEST_VERSION
download_file_if_needed "utils.sh" LATEST_UTILS_VERSION

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

# Display versions for all components
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Component Versions${NC}"
echo -e "Main Script: ${YELLOW}${SCRIPT_VERSION}${NC} (Current) | ${YELLOW}${LATEST_MAIN_VERSION}${NC} (Latest)"
echo -e "Error Handler: ${YELLOW}${ERROR_HANDLER_VERSION}${NC} (Current) | ${YELLOW}${LATEST_ERROR_HANDLER_VERSION}${NC} (Latest)"
echo -e "Update Check: ${YELLOW}${UPDATE_CHECK_VERSION}${NC} (Current) | ${YELLOW}${LATEST_UPDATE_CHECK_VERSION}${NC} (Latest)"
echo -e "Run Speed Test: ${YELLOW}${RUN_SPEEDTEST_VERSION}${NC} (Current) | ${YELLOW}${LATEST_RUN_SPEEDTEST_VERSION}${NC} (Latest)"
echo -e "Utilities: ${YELLOW}${UTILS_VERSION}${NC} (Current) | ${YELLOW}${LATEST_UTILS_VERSION}${NC} (Latest)"
echo -e "${CYAN}====================================================${NC}"

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
