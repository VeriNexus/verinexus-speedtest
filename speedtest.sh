#!/bin/bash

# Main script version
SCRIPT_VERSION="1.1.1"

# Define remote server credentials and file path
REMOTE_USER='root'             # Your remote SSH username
REMOTE_HOST='88.208.225.250'   # Your remote server IP or hostname
REMOTE_PATH='/speedtest/results/speedtest_results.csv'  # Path to the CSV file on the remote server
REMOTE_PASS='**@p3F_1$t'       # SSH password with single quotes

# Function to download files if needed
download_file_if_needed() {
    local file_name=$1
    local latest_version_var=$2

    if [[ ! -f "./$file_name" ]] || [[ $(grep "$latest_version_var" "./$file_name" | cut -d'=' -f2 | tr -d '"') != "${!latest_version_var}" ]]; then
        echo "Updating $file_name to the latest version..."
        curl -s -o "./$file_name" "https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/$file_name"
        chmod +x "./$file_name"
    fi
}

# Define latest versions for components
LATEST_ERROR_HANDLER_VERSION="1.0.6"
LATEST_UPDATE_CHECK_VERSION="1.0.6"
LATEST_RUN_SPEEDTEST_VERSION="1.1.1"
LATEST_UTILS_VERSION="1.0.6"

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

# Check for script updates
check_for_updates

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
    upload_error_log
fi

# Main script footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
#!/bin/bash

# Main script version
SCRIPT_VERSION="1.0.10"

# Define remote server credentials and file path
REMOTE_USER='root'             # Your remote SSH username
REMOTE_HOST='88.208.225.250'   # Your remote server IP or hostname
REMOTE_PATH='/speedtest/results/speedtest_results.csv'  # Path to the CSV file on the remote server
REMOTE_PASS='**@p3F_1$t'       # SSH password with single quotes

# Function to download files if needed
download_file_if_needed() {
    local file_name=$1
    local latest_version_var=$2

    if [[ ! -f "./$file_name" ]] || [[ $(grep "$latest_version_var" "./$file_name" | cut -d'=' -f2 | tr -d '"') != "${!latest_version_var}" ]]; then
        echo "Updating $file_name to the latest version..."
        curl -s -o "./$file_name" "https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/$file_name"
        chmod +x "./$file_name"
    fi
}

# Define latest versions for components
LATEST_ERROR_HANDLER_VERSION="1.0.6"
LATEST_UPDATE_CHECK_VERSION="1.0.6"
LATEST_RUN_SPEEDTEST_VERSION="1.0.8"
LATEST_UTILS_VERSION="1.0.6"

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

# Check for script updates
check_for_updates

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
    upload_error_log
fi

# Main script footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
