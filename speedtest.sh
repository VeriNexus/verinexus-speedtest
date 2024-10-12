#!/bin/bash

# Version number of the script
SCRIPT_VERSION="1.3.6"

# GitHub repository raw URL for the script
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"

# Temporary file to store the latest version for comparison
TEMP_SCRIPT="/tmp/latest_speedtest.sh"

# SSH connection details (No password shown in the output)
REMOTE_USER="root"                 
REMOTE_HOST="88.208.225.250"       
REMOTE_PATH="/speedtest/results/speedtest_results.csv"  
REMOTE_PASS='**@p3F_1$t'           

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' 
BOLD='\033[1m'

# Symbols
CHECKMARK="${GREEN}✔${NC}"
CROSS="${RED}✖${NC}"

# Function to check for updates
check_for_updates() {
    echo "Checking for updates..."
    curl -s -o "$TEMP_SCRIPT" "$REPO_RAW_URL"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to download the script."
        exit 1
    fi

    if [ ! -s "$TEMP_SCRIPT" ]; then
        echo "Error: Downloaded file is empty."
        exit 1
    fi

    LATEST_VERSION=$(grep -oP 'SCRIPT_VERSION="\K[0-9.]+' "$TEMP_SCRIPT")

    if [ -z "$LATEST_VERSION" ]; then
        echo "Error: Failed to fetch the latest version."
        exit 1
    fi

    if [ "$LATEST_VERSION" != "$SCRIPT_VERSION" ]; then
        cp "$TEMP_SCRIPT" "$0"
        chmod +x "$0"
        echo "Update downloaded. Please re-run the script."
        exit 0
    fi
}

# Call the update check function
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

echo -e "${BLUE}${BOLD}Starting VeriNexus Speed Test...${NC}"
progress_bar

# Step 1: Running Speed Test
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│  Step 1: Running Speed Test  │${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
SPEEDTEST_OUTPUT=$(speedtest-cli --csv --secure --share)
if [ $? -eq 0 ]; then
    echo -e "${CHECKMARK} Speed Test completed successfully."
else
    echo -e "${CROSS} Error: Speed Test failed."
    exit 1
fi

# Step 2: Fetching Date and Time
TIMESTAMP=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $4}')
DATE=$(echo "$TIMESTAMP" | cut -d'T' -f1)
TIME=$(echo "$TIMESTAMP" | cut -d'T' -f2 | cut -d'.' -f1)
echo -e "${CHECKMARK} Date: ${YELLOW}$DATE${NC}, Time: ${YELLOW}$TIME${NC}"

# Step 3: Fetching Private/Public IPs
PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.co)
echo -e "${CHECKMARK} Private IP: ${YELLOW}$PRIVATE_IP${NC}, Public IP: ${YELLOW}$PUBLIC_IP${NC}"

# Step 4: Fetching MAC Address
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│  Step 4: Fetching MAC Address  │${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
ACTIVE_IFACE=$(ip route | grep default | awk '{print $5}')
if [ -n "$ACTIVE_IFACE" ]; then
    MAC_ADDRESS=$(cat /sys/class/net/$ACTIVE_IFACE/address)
    echo -e "${CHECKMARK} Active Interface: ${YELLOW}$ACTIVE_IFACE${NC}, MAC Address: ${YELLOW}$MAC_ADDRESS${NC}"
else
    echo -e "${CROSS} Error: Could not determine active interface."
fi

# Step 5: Converting Speed Results
DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $7 / 1000000}')
UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $8 / 1000000}')
echo -e "${CHECKMARK} Download Speed: ${GREEN}$DOWNLOAD_SPEED Mbps${NC}, Upload Speed: ${GREEN}$UPLOAD_SPEED Mbps${NC}"

# Step 6: Extracting Shareable ID
SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $9}')
SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')
echo -e "${CHECKMARK} Shareable ID: ${YELLOW}$SHARE_ID${NC}"

# Step 7: Saving Results
SPEEDTEST_OUTPUT=$(echo "$SPEEDTEST_OUTPUT" | awk -F, -v date="$DATE" -v time="$TIME" -v down="$DOWNLOAD_SPEED" -v up="$UPLOAD_SPEED" -v host="$HOSTNAME" -v mac="$MAC_ADDRESS" -v priv_ip="$PRIVATE_IP" -v pub_ip="$PUBLIC_IP" -v version="$SCRIPT_VERSION" -v share_id="$SHARE_ID" '{OFS=","; print $1, $2, $3, date, time, $6, down, up, share_id, priv_ip, pub_ip, host, mac, version}')

# Run the SSH command (Password not shown in output)
echo "Running SSH command..."
echo "$SPEEDTEST_OUTPUT" | sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "cat >> $REMOTE_PATH"

if [ $? -eq 0 ]; then
    echo -e "${CHECKMARK} Results saved to the remote server."
else
    echo -e "${CROSS} Error: Failed to save results to the remote server."
fi

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
