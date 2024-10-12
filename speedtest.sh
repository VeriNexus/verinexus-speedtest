#!/bin/bash

# Version number of the script
SCRIPT_VERSION="1.5.0"

# GitHub repository raw URL for the script
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"

# Temporary file to store the latest version for comparison
TEMP_SCRIPT="/tmp/latest_speedtest.sh"

# SSH connection details (No password shown in the output)
REMOTE_USER="root"                 
REMOTE_HOST="88.208.225.250"       
REMOTE_PATH="/speedtest/results/speedtest_results.csv"  
ERROR_LOG_PATH="/speedtest/results/error.txt"
REMOTE_PASS='**@p3F_1$t'           

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

# Function to log errors and upload to the remote server
log_error() {
    local error_message="$1"

    # Get machine details
    HOSTNAME=$(hostname)
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
    PUBLIC_IP=$(curl -s ifconfig.co)

    # Get timestamp
    ERROR_TIMESTAMP=$(TZ="Europe/London" date +"%Y-%m-%d %H:%M:%S")

    # Construct the error log entry
    ERROR_LOG="===============================\n"
    ERROR_LOG+="Timestamp: $ERROR_TIMESTAMP\n"
    ERROR_LOG+="Script Version: $SCRIPT_VERSION\n"
    ERROR_LOG+="Hostname: $HOSTNAME\n"
    ERROR_LOG+="Private IP: $PRIVATE_IP\n"
    ERROR_LOG+="Public IP: $PUBLIC_IP\n"
    ERROR_LOG+="Error: $error_message\n"
    ERROR_LOG+="===============================\n"

    # Append error to a local file for reference
    echo -e "$ERROR_LOG" >> error_local.log

    # Send the error log to the remote server
    echo -e "$ERROR_LOG" | sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "cat >> $ERROR_LOG_PATH"

    echo -e "${CROSS} ${RED}Error logged and sent to remote server.${NC}"
}

# Function to compare versions
version_gt() { 
    [ "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1" ] 
}

# Function to check for updates with cache control and version check
check_for_updates() {
    echo -e "${CYAN}====================================================${NC}"
    echo -e "           ${BOLD}Checking for Script Updates...${NC}"
    echo -e "${CYAN}====================================================${NC}"

    # Clear any previous version of the file
    rm -f "$TEMP_SCRIPT"

    # Download the latest version of the script with cache control headers
    curl -H 'Cache-Control: no-cache, no-store, must-revalidate' \
         -H 'Pragma: no-cache' \
         -H 'Expires: 0' \
         -s -o "$TEMP_SCRIPT" "$REPO_RAW_URL"

    if [ $? -ne 0 ]; then
        log_error "Failed to download the script from GitHub."
        exit 1
    fi

    # Ensure the downloaded file is valid
    if [ ! -s "$TEMP_SCRIPT" ]; then
        log_error "Downloaded script is empty."
        exit 1
    fi

    # Extract version from the downloaded script
    LATEST_VERSION=$(grep -oP 'SCRIPT_VERSION="\K[0-9.]+' "$TEMP_SCRIPT")
    if [ -z "$LATEST_VERSION" ]; then
        log_error "Failed to extract version from the downloaded script."
        exit 1
    fi

    echo -e "${CHECKMARK} Current version: $SCRIPT_VERSION, Latest version: $LATEST_VERSION"

    # Compare versions to check if we should upgrade
    if version_gt "$LATEST_VERSION" "$SCRIPT_VERSION"; then
        echo -e "${YELLOW}New version available: $LATEST_VERSION${NC}"
        cp "$TEMP_SCRIPT" "$0"
        chmod +x "$0"
        echo -e "${CHECKMARK} Update downloaded to version $LATEST_VERSION. Please re-run the script."
        exit 0
    else
        echo -e "${CHECKMARK} No update needed. You are using the latest version or a higher one."
    fi

    echo -e "${CYAN}====================================================${NC}"
}

# Retry function to retry the speed test in case of failure
run_speed_test() {
    local attempts=0
    local max_attempts=3
    while [ $attempts -lt $max_attempts ]; do
        echo -e "${BLUE}Attempting speed test (Attempt $((attempts+1)) of $max_attempts)...${NC}"
        SPEEDTEST_OUTPUT=$(speedtest-cli --csv --secure --share)
        if [ $? -eq 0 ]; then
            echo -e "${CHECKMARK} Speed Test completed successfully."
            return 0
        else
            echo -e "${CROSS} ${RED}Speed Test failed.${NC}"
            attempts=$((attempts+1))
            sleep 5  # Wait before retrying
        fi
    done
    log_error "Speed Test failed after $max_attempts attempts."
    return 1  # Fail if all attempts failed
}

# Call the update check function
check_for_updates

# Display Title with a Frame
echo -e "${CYAN}====================================================${NC}"
echo -e "     ${BOLD}Welcome to VeriNexus Speed Test 2024${NC}"
echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}(C) 2024 VeriNexus. All Rights Reserved.${NC}"
echo -e "${YELLOW}Script Version: $SCRIPT_VERSION${NC}"

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

# Step 1: Running Speed Test with retry logic
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 1: Running Speed Test  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

if ! run_speed_test; then
    echo -e "${CROSS} ${RED}Error: Speed Test failed after multiple attempts. Please check your internet connection and try again later.${NC}"
    exit 1
fi

# Step 2: Fetching Date and Time (UK Time - GMT/BST)
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 2: Fetching Date and Time (UK Time)  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

# Use TZ environment variable to fetch time in Europe/London timezone
UK_DATE=$(TZ="Europe/London" date +"%Y-%m-%d")
UK_TIME=$(TZ="Europe/London" date +"%H:%M:%S")
echo -e "${CHECKMARK} Date (UK): ${YELLOW}$UK_DATE${NC}, Time (UK): ${YELLOW}$UK_TIME${NC}"

# Step 3: Fetching Private/Public IPs
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 3: Fetching Private/Public IPs  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.co)
echo -e "${CHECKMARK} Private IP: ${YELLOW}$PRIVATE_IP${NC}, Public IP: ${YELLOW}$PUBLIC_IP${NC}"

# Step 4: Fetching MAC Address
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 4: Fetching MAC Address  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
ACTIVE_IFACE=$(ip route | grep default | awk '{print $5}')
if [ -n "$ACTIVE_IFACE" ]; then
    MAC_ADDRESS=$(cat /sys/class/net/$ACTIVE_IFACE/address)
    echo -e "${CHECKMARK} Active Interface: ${YELLOW}$ACTIVE_IFACE${NC}, MAC Address: ${YELLOW}$MAC_ADDRESS${NC}"
else
    log_error "Could not determine active network interface."
    exit 1
fi

# Step 5: Converting Speed Results
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 5: Converting Speed Results  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $7 / 1000000}')
UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $8 / 1000000}')
echo -e "${CHECKMARK} Download Speed: ${GREEN}$DOWNLOAD_SPEED Mbps${NC}, Upload Speed: ${GREEN}$UPLOAD_SPEED Mbps${NC}"

# Step 6: Extracting Shareable ID
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 6: Extracting Shareable ID  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $9}')
SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')
echo -e "${CHECKMARK} Shareable ID: ${YELLOW}$SHARE_ID${NC}"

# Step 7: Saving Results
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 7: Saving Results  ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

SPEEDTEST_OUTPUT=$(echo "$SPEEDTEST_OUTPUT" | awk -F, -v date="$UK_DATE" -v time="$UK_TIME" -v down="$DOWNLOAD_SPEED" -v up="$UPLOAD_SPEED" -v host="$HOSTNAME" -v mac="$MAC_ADDRESS" -v priv_ip="$PRIVATE_IP" -v pub_ip="$PUBLIC_IP" -v version="$SCRIPT_VERSION" -v share_id="$SHARE_ID" '{OFS=","; print $1, $2, $3, date, time, $6, down, up, share_id, priv_ip, pub_ip, host, mac, version}')

# Run the SSH command (Password not shown in output)
echo -e "${BLUE}Running SSH command...${NC}"
echo "$SPEEDTEST_OUTPUT" | sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "cat >> $REMOTE_PATH"

if [ $? -eq 0 ]; then
    echo -e "${CHECKMARK} Results saved to the remote server."
else
    log_error "Failed to save results to the remote server."
fi

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
