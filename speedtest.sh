#!/bin/bash

# Version number of the script
SCRIPT_VERSION="2.0.5"

# Define variables
REMOTE_USER="root"                  # Remote server username
REMOTE_HOST="88.208.225.250"        # Remote server address
REMOTE_PATH="/speedtest/results/speedtest_results.csv"  # Full path to the CSV file on the remote server
REMOTE_PASS='**@p3F_1$t'            # Remote server password (single quotes to handle special characters)

# GitHub raw URL for the latest script version
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"

# Temporary file to store the latest version for comparison
TEMP_SCRIPT="/tmp/latest_speedtest.sh"

# Function to check for updates
check_for_updates() {
    echo -e "${CYAN}===================================================="
    echo -e "           Checking for Script Updates..."
    echo -e "====================================================${NC}"

    # Fetch the latest version of the script from GitHub
    curl -s -o "$TEMP_SCRIPT" "$REPO_RAW_URL"
    LATEST_VERSION=$(grep "SCRIPT_VERSION=" "$TEMP_SCRIPT" | cut -d'"' -f2)

    echo -e "DEBUG: Fetched Latest Version: $LATEST_VERSION"
    echo -e "DEBUG: Current Version: $SCRIPT_VERSION"

    if [ "$LATEST_VERSION" != "$SCRIPT_VERSION" ]; then
        echo -e "${YELLOW}Update available: $LATEST_VERSION${NC}"
        echo -e "Downloading the latest version..."

        # Replace the current script with the new one
        mv "$TEMP_SCRIPT" "$0"
        chmod +x "$0"
        echo -e "${GREEN}✔ Update downloaded to version $LATEST_VERSION. Please re-run the script.${NC}"
        exit 0
    else
        echo -e "${GREEN}✔ You are using the latest version: $SCRIPT_VERSION${NC}"
        rm "$TEMP_SCRIPT"
    fi
}

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Symbols
CHECKMARK="${GREEN}✔${NC}"
CROSS="${RED}✖${NC}"

# Perform the update check
check_for_updates

# Display Title with a Frame
echo -e "${CYAN}================================================"
echo -e "     ${BOLD}Welcome to VeriNexus Speed Test 2024${NC}"
echo -e "================================================${NC}"
echo -e "${YELLOW}(C) 2024 VeriNexus. All Rights Reserved.${NC}"
echo -e "${YELLOW}Script Version: $SCRIPT_VERSION${NC}"
echo

# Fancy Progress Bar Function
progress_bar() {
    echo -n -e "["
    for i in {1..50}; do
        echo -n -e "${CYAN}#${NC}"
        sleep 0.02
    done
    echo -e "]"
}

# Step headers with ASCII art
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 1: ${BOLD}Running Speed Test${NC}  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
echo -e "${BLUE}Running VeriNexus Speed Test with secure connection and shareable ID...${NC}"

# Run the speed test with the --secure and --share option and get the result in CSV format
SPEEDTEST_OUTPUT=$(speedtest-cli --csv --secure --share)
if [ $? -eq 0 ]; then
    echo -e "${CHECKMARK} ${GREEN}Speed Test completed successfully.${NC}"
else
    echo -e "${CROSS} ${RED}Error: VeriNexus Speed Test failed.${NC}"
    exit 1
fi

# Display Step with Separator and Animation
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 2: ${BOLD}Fetching Date and Time${NC}  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
echo -e "${BLUE}Fetching Date and Time...${NC}"

# Extract timestamp and convert to UK time
TIMESTAMP=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $4}')
DATE=$(date -d "$TIMESTAMP" +"%Y-%m-%d")
TIME=$(date -d "$TIMESTAMP" +"%H:%M:%S")

echo -e "${CHECKMARK} Date: ${YELLOW}$DATE${NC}, Time (UK): ${YELLOW}$TIME${NC}"

# Fetch Private/Public IPs
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 3: ${BOLD}Fetching Private/Public IPs${NC}  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
echo -e "${BLUE}Fetching Private and Public IP addresses...${NC}"

# Get the private IP address of the machine
PRIVATE_IP=$(hostname -I | awk '{print $1}')
# Get the public IP address using a web service
PUBLIC_IP=$(curl -s ifconfig.co)

echo -e "${CHECKMARK} Private IP: ${YELLOW}$PRIVATE_IP${NC}, Public IP: ${YELLOW}$PUBLIC_IP${NC}"

# Fetch MAC Address
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 4: ${BOLD}Fetching MAC Address${NC}  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

ACTIVE_INTERFACE=$(ip route | grep default | awk '{print $5}')
MAC_ADDRESS=$(cat /sys/class/net/$ACTIVE_INTERFACE/address)
echo -e "${CHECKMARK} Active Interface: ${YELLOW}$ACTIVE_INTERFACE${NC}, MAC Address: ${YELLOW}$MAC_ADDRESS${NC}"

# Conversion to Mbps (simplified to one step for cleaner display)
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 5: ${BOLD}Converting Speed Results${NC}  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $7 / 1000000}')
UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $8 / 1000000}')
echo -e "${CHECKMARK} Download Speed: ${GREEN}$DOWNLOAD_SPEED Mbps${NC}, Upload Speed: ${GREEN}$UPLOAD_SPEED Mbps${NC}"

# Fetch the shareable ID
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 6: ${BOLD}Extracting Shareable ID${NC}  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $9}')
SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')

echo -e "${CHECKMARK} Shareable ID: ${YELLOW}$SHARE_ID${NC}"

# Final step - Store results with header
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 7: ${BOLD}Saving Results${NC}  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

# Prepare the result data with the format you want
CLIENT_ID=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $1}')
SERVER_NAME=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $2}')
LOCATION=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $3}')
LATENCY=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $5}')
JITTER=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $6}')

RESULT="$CLIENT_ID,$SERVER_NAME,$LOCATION,$LATENCY,$JITTER,$DOWNLOAD_SPEED,$UPLOAD_SPEED,$SHARE_ID,$PRIVATE_IP,$PUBLIC_IP,$HOSTNAME,$DATE,$TIME,$MAC_ADDRESS"

# Save the results to the remote server
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "echo '$RESULT' >> $REMOTE_PATH"

# Debugging info in case of any failure
if [[ $? -ne 0 ]]; then
    echo "✖ Error: Failed to save results to the remote server."
else
    echo "✔ Results saved to the remote server."
fi

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
