#!/bin/bash

# Version number of the script
SCRIPT_VERSION="1.3.1"

# GitHub repository raw URL for the script
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"

# Temporary file to store the latest version for comparison
TEMP_SCRIPT="/tmp/latest_speedtest.sh"

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

# Function to check for updates
check_for_updates() {
    echo "Checking for updates..."
    
    # Download the latest version of the script from GitHub
    curl -s -o "$TEMP_SCRIPT" "$REPO_RAW_URL"

    # Check if the download succeeded
    if [ $? -ne 0 ] || [ ! -s "$TEMP_SCRIPT" ]; then
        echo "Error: Unable to check for updates or file not found."
        exit 1
    fi

    # Extract the version number from the downloaded script
    LATEST_VERSION=$(grep -oP 'SCRIPT_VERSION="\K[0-9.]+' "$TEMP_SCRIPT")
    if [ -z "$LATEST_VERSION" ]; then
        echo "Error: Failed to fetch the latest version."
        exit 1
    fi

    echo "Latest version: $LATEST_VERSION, Current version: $SCRIPT_VERSION"

    # Compare versions
    if [ "$LATEST_VERSION" != "$SCRIPT_VERSION" ]; then
        echo "New version available: $LATEST_VERSION"
        
        # Overwrite the current script with the new version
        cp "$TEMP_SCRIPT" "$0"
        chmod +x "$0"
        
        echo "Update downloaded. Please re-run the script to apply changes."
        exit 0
    else
        echo "You're using the latest version."
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

# Start the progress with a header
echo -e "${BLUE}${BOLD}Starting VeriNexus Speed Test...${NC}"
progress_bar

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

# Extract timestamp
TIMESTAMP=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $4}')
DATE=$(echo "$TIMESTAMP" | cut -d'T' -f1)
TIME=$(echo "$TIMESTAMP" | cut -d'T' -f2 | cut -d'.' -f1)

echo -e "${CHECKMARK} Date: ${YELLOW}$DATE${NC}, Time: ${YELLOW}$TIME${NC}"

# Step: Fetch Private/Public IPs with loading animation
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 3: ${BOLD}Fetching Private/Public IPs${NC}  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
echo -e "${BLUE}Fetching Private and Public IP addresses...${NC}"

# Simulating a short wait
for i in {1..3}; do
    echo -n "."
    sleep 0.5
done
echo ""

# Get the private IP address of the machine
PRIVATE_IP=$(hostname -I | awk '{print $1}')
# Get the public IP address using a web service
PUBLIC_IP=$(curl -s ifconfig.co)

echo -e "${CHECKMARK} Private IP: ${YELLOW}$PRIVATE_IP${NC}, Public IP: ${YELLOW}$PUBLIC_IP${NC}"

# Conversion to Mbps (simplified to one step for cleaner display)
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 4: ${BOLD}Converting Speed Results${NC}  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $7 / 1000000}')
UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $8 / 1000000}')
echo -e "${CHECKMARK} Download Speed: ${GREEN}$DOWNLOAD_SPEED Mbps${NC}, Upload Speed: ${GREEN}$UPLOAD_SPEED Mbps${NC}"

# Fetch the shareable ID
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 5: ${BOLD}Extracting Shareable ID${NC}  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $9}')
SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')

echo -e "${CHECKMARK} Shareable ID: ${YELLOW}$SHARE_ID${NC}"

# Final step - Store results with header
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 6: ${BOLD}Saving Results${NC}  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

# Save the results
SPEEDTEST_OUTPUT=$(echo "$SPEEDTEST_OUTPUT" | awk -F, -v date="$DATE" -v time="$TIME" -v down="$DOWNLOAD_SPEED" -v up="$UPLOAD_SPEED" -v host="$HOSTNAME" -v mac="$MAC_ADDRESS" -v priv_ip="$PRIVATE_IP" -v pub_ip="$PUBLIC_IP" -v version="$SCRIPT_VERSION" -v share_id="$SHARE_ID" '{OFS=","; print $1, $2, $3, date, time, $6, down, up, share_id, priv_ip, pub_ip, host, mac, version}')
echo "$SPEEDTEST_OUTPUT" | sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "cat >> $REMOTE_PATH"

echo -e "${CHECKMARK} ${GREEN}Results saved to the remote server.${NC}"

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
