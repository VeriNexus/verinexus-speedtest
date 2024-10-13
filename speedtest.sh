#!/bin/bash

# Version number of the script
SCRIPT_VERSION="2.2.3"

# GitHub repository raw URLs for the script and forced error file
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
FORCED_ERROR_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/force_error.txt"

# Temporary files for comparison, forced error, and force update
TEMP_SCRIPT="/tmp/latest_speedtest.sh"
FORCED_ERROR_FILE="/tmp/force_error.txt"
FORCE_UPDATE_FILE="/tmp/force_update.txt"
FORCE_UPDATE_TRACKER="/tmp/force_update_tracker.txt"

# SSH connection details
REMOTE_USER="root"
REMOTE_HOST="88.208.225.250"
REMOTE_PATH="/speedtest/results/speedtest_results.csv"
ERROR_LOG_PATH="/speedtest/results/error.txt"
REMOTE_PASS='**@p3F_1$t'  # Password included as per your request

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Symbols
CHECKMARK="${GREEN}✔${NC}"
CROSS="${RED}✖${NC}"

# Function to log errors without stopping the script
log_error() {
    local error_message="$1"
    local timestamp_ms=$(($(date +%s%N)/1000000))  # Unix timestamp in milliseconds
    local timestamp="$(TZ='Europe/London' date +"%Y-%m-%d %H:%M:%S")"
    local error_id="$timestamp_ms"
    local hostname="$(hostname)"
    local private_ip="$(hostname -I | awk '{print $1}')"
    local public_ip="$(curl -s ifconfig.co)"
    local script_version="$SCRIPT_VERSION"

    # Format the error log entry as a single line in CSV format
    local error_entry="$error_id,$timestamp,$script_version,$hostname,$private_ip,$public_ip,\"$error_message\""
    ERROR_LOG+="$error_entry\n"

    echo -e "${CROSS} ${RED}Error: $error_message${NC}"
}

# Function to check if forced update has been applied for the current version
check_force_update_tracker() {
    if [ -f "$FORCE_UPDATE_TRACKER" ]; then
        APPLIED_VERSION=$(cat "$FORCE_UPDATE_TRACKER")
        if [ "$APPLIED_VERSION" == "$SCRIPT_VERSION" ]; then
            echo -e "${GREEN}✔ Force update already applied for version $SCRIPT_VERSION.${NC}"
            return 1
        fi
    fi
    return 0
}

# Function to apply forced errors if forced error file exists
apply_forced_errors() {
    curl -H 'Cache-Control: no-cache, no-store, must-revalidate' \
         -H 'Pragma: no-cache' \
         -H 'Expires: 0' \
         -s -o "$FORCED_ERROR_FILE" "$FORCED_ERROR_URL"

    if [ -s "$FORCED_ERROR_FILE" ]; then
        echo -e "${RED}Forced error file found. Applying forced errors...${NC}"
        source "$FORCED_ERROR_FILE"
        echo -e "${YELLOW}Applied Forced Errors:${NC}"
        echo "FORCE_FAIL_PRIVATE_IP=$FORCE_FAIL_PRIVATE_IP"
        echo "FORCE_FAIL_PUBLIC_IP=$FORCE_FAIL_PUBLIC_IP"
        echo "FORCE_FAIL_MAC=$FORCE_FAIL_MAC"
    else
        if [ -f "$FORCED_ERROR_FILE" ]; then
            echo -e "${YELLOW}Forced error file removed from GitHub. Deleting local copy...${NC}"
            rm -f "$FORCED_ERROR_FILE"
        fi
    fi
}

# Function to compare versions using awk
version_gt() {
    awk -v v1="$1" -v v2="$2" '
    BEGIN {
        split(v1, a, ".")
        split(v2, b, ".")
        for (i = 1; i <= length(a) || i <= length(b); i++) {
            a_i = (i in a) ? a[i] : 0
            b_i = (i in b) ? b[i] : 0
            if (a_i > b_i) {
                exit 0  # v1 > v2
            } else if (a_i < b_i) {
                exit 1  # v1 < v2
            }
        }
        exit 1  # v1 == v2
    }'
}

# Function to check for script updates
check_for_updates() {
    echo -e "${CYAN}====================================================${NC}"
    echo -e "           ${BOLD}Checking for Script Updates...${NC}"
    echo -e "${CYAN}====================================================${NC}"

    rm -f "$TEMP_SCRIPT"

    curl -H 'Cache-Control: no-cache, no-store, must-revalidate' \
         -H 'Pragma: no-cache' \
         -H 'Expires: 0' \
         -s -o "$TEMP_SCRIPT" "$REPO_RAW_URL"

    if [ $? -ne 0 ]; then
        log_error "Failed to download the script from GitHub."
        return 1
    fi

    if [ ! -s "$TEMP_SCRIPT" ]; then
        log_error "Downloaded script is empty."
        return 1
    fi

    LATEST_VERSION=$(grep -oP 'SCRIPT_VERSION="\K[0-9.]+' "$TEMP_SCRIPT")
    if [ -z "$LATEST_VERSION" ]; then
        log_error "Failed to extract version from the downloaded script."
        return 1
    fi

    echo -e "${CHECKMARK} Current version: ${YELLOW}$SCRIPT_VERSION${NC}"
    echo -e "${CHECKMARK} Latest version: ${YELLOW}$LATEST_VERSION${NC}"

    if version_gt "$LATEST_VERSION" "$SCRIPT_VERSION"; then
        echo -e "${YELLOW}New version available: $LATEST_VERSION${NC}"
        cp "$TEMP_SCRIPT" "$0"
        chmod +x "$0"
        echo -e "${CHECKMARK} Update downloaded to version $LATEST_VERSION. Please re-run the script."
        exit 0
    else
        echo -e "${GREEN}✔ No update needed. You are using the latest version.${NC}"
    fi

    echo -e "${CYAN}====================================================${NC}"
}

# Function to check for force update
check_force_update() {
    echo -e "${BLUE}Checking for force update...${NC}"

    if [[ "$1" == "--force-update" ]]; then
        echo -e "${RED}Forcing update...${NC}"
        check_for_updates
        echo "$SCRIPT_VERSION" > "$FORCE_UPDATE_TRACKER"
        return
    fi

    check_force_update_tracker
    if [ $? -eq 1 ]; then
        return
    fi

    sshpass -p "$REMOTE_PASS" scp -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST:/speedtest/update_files/force_update.txt" "$FORCE_UPDATE_FILE"

    if [ -s "$FORCE_UPDATE_FILE" ]; then
        FORCE_UPDATE_CONTENT=$(cat "$FORCE_UPDATE_FILE")
        if [[ "$FORCE_UPDATE_CONTENT" == "true" ]]; then
            echo -e "${RED}Force update required. Proceeding with update...${NC}"
            check_for_updates
            echo "$SCRIPT_VERSION" > "$FORCE_UPDATE_TRACKER"
        else
            echo -e "${GREEN}✔ No force update required.${NC}"
        fi
        rm -f "$FORCE_UPDATE_FILE"
    else
        echo -e "${CROSS} Error: Failed to download force update file. Treating as no update required.${NC}"
    fi
}

# Apply any forced errors
apply_forced_errors

# Call the force update check
check_force_update "$1"

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
printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 1: Running Speed Test" "Speed Test completed successfully."

# Step 2: Fetching Date and Time (UK Time - GMT/BST)
UK_DATE=$(TZ="Europe/London" date +"%Y-%m-%d")
UK_TIME=$(TZ="Europe/London" date +"%H:%M:%S")
printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 2: Fetching Date and Time (UK Time)" "Date (UK): $UK_DATE, Time (UK): $UK_TIME"

# Step 3: Fetching Private/Public IPs
PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.co)
printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 3: Fetching Private/Public IPs" "Private IP: $PRIVATE_IP, Public IP: $PUBLIC_IP"

# Step 4: Fetching MAC Address
ACTIVE_IFACE=$(ip route | grep default | awk '{print $5}')
MAC_ADDRESS=$(cat /sys/class/net/$ACTIVE_IFACE/address)
printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 4: Fetching MAC Address" "MAC Address: $MAC_ADDRESS"

# Step 5: Converting Speed Results
DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $7 / 1000000}')
UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $8 / 1000000}')
printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 5: Converting Speed Results" "Download Speed: $DOWNLOAD_SPEED Mbps, Upload Speed: $UPLOAD_SPEED Mbps"

# Step 6: Extracting Shareable ID
SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $9}')
SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')
printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 6: Extracting Shareable ID" "Shareable ID: $SHARE_ID"

# Step 7: Saving Results
RESULT_LINE="$CLIENT_ID,$SERVER_NAME,$LOCATION,$LATENCY,$JITTER,$DOWNLOAD_SPEED,$UPLOAD_SPEED,$SHARE_ID,$PRIVATE_IP,$PUBLIC_IP,$HOSTNAME,$UK_DATE,$UK_TIME,$MAC_ADDRESS"
echo -e "${BLUE}Running SSH command to save results...${NC}"
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
"echo '$RESULT_LINE' >> '$REMOTE_PATH'"
if [ $? -eq 0 ]; then
    printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 7: Saving Results" "Results saved to the remote server."
else
    log_error "Failed to save results to the remote server."
fi

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
