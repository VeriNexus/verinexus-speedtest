#!/bin/bash

# Main script version
SCRIPT_VERSION="1.0.1"

# Load other scripts
source ./error_handler.sh
source ./update_check.sh
source ./run_speedtest.sh
source ./utils.sh

# ANSI Color Codes and Symbols
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
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
