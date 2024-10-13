#!/bin/bash

# Version number of the script
SCRIPT_VERSION="2.2.4"

# SSH connection details
REMOTE_USER="root"
REMOTE_HOST="88.208.225.250"
REMOTE_PATH="/speedtest/results/speedtest_results.csv"
ERROR_LOG_PATH="/speedtest/results/error.txt"
REMOTE_PASS='**@p3F_1$t'  # Password included as per your request

# File paths and URLs
FORCE_UPDATE_FILE="/tmp/force_update.txt"
FORCE_UPDATE_TRACK="/tmp/force_update_track.txt"  # To track applied updates
FORCED_ERROR_FILE="/tmp/force_error.txt"
SPEEDTEST_RESULTS_CSV="/tmp/speedtest_results.csv"

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
    local hostname="$(hostname)"
    local private_ip="$(hostname -I | awk '{print $1}')"
    local public_ip="$(curl -s ifconfig.co)"
    
    local error_entry="$timestamp,$SCRIPT_VERSION,$hostname,$private_ip,$public_ip,\"$error_message\""
    echo "$error_entry" >> "$ERROR_LOG_PATH"
    
    echo -e "${CROSS} ${RED}Error: $error_message${NC}"
}

# Function to check for forced error file and apply its effects
apply_forced_errors() {
    echo -e "${CYAN}Checking for forced errors...${NC}"
    curl -s -o "$FORCED_ERROR_FILE" "https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/force_error.txt"
    
    if [ -s "$FORCED_ERROR_FILE" ]; then
        echo -e "${RED}Forced error file found. Applying forced errors...${NC}"
        source "$FORCED_ERROR_FILE"
        echo "FORCE_FAIL_PRIVATE_IP=$FORCE_FAIL_PRIVATE_IP"
        echo "FORCE_FAIL_PUBLIC_IP=$FORCE_FAIL_PUBLIC_IP"
        echo "FORCE_FAIL_MAC=$FORCE_FAIL_MAC"
    else
        echo -e "${YELLOW}No forced error file found.${NC}"
    fi
}

# Function to check and apply force update
check_force_update() {
    echo -e "${CYAN}Checking for force update...${NC}"
    
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
    "test -f /speedtest/update_files/force_update.txt && cat /speedtest/update_files/force_update.txt" > "$FORCE_UPDATE_FILE"

    if [ $? -ne 0 ]; then
        log_error "Failed to download force update file."
        return
    fi

    # Check if the force update file contains 'true' and update hasn't been applied yet
    if [[ $(cat "$FORCE_UPDATE_FILE") == "true" ]]; then
        if grep -Fxq "$SCRIPT_VERSION" "$FORCE_UPDATE_TRACK"; then
            echo -e "${YELLOW}✔ Force update already applied for version $SCRIPT_VERSION.${NC}"
        else
            echo -e "${RED}Force update required. Proceeding with update...${NC}"
            check_for_updates
            echo "$SCRIPT_VERSION" >> "$FORCE_UPDATE_TRACK"
        fi
    else
        echo -e "${GREEN}✔ No force update required.${NC}"
    fi
}

# Function to check for updates from GitHub
check_for_updates() {
    echo -e "${CYAN}====================================================${NC}"
    echo -e "           ${CYAN}Checking for Script Updates...${NC}"
    echo -e "${CYAN}====================================================${NC}"

    TEMP_SCRIPT="/tmp/latest_speedtest.sh"
    
    curl -s -o "$TEMP_SCRIPT" "https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
    if [ $? -ne 0 ]; then
        log_error "Failed to download the script from GitHub."
        return 1
    fi

    LATEST_VERSION=$(grep -oP 'SCRIPT_VERSION="\K[0-9.]+' "$TEMP_SCRIPT")
    if [ -z "$LATEST_VERSION" ]; then
        log_error "Failed to extract version from the downloaded script."
        return 1
    fi

    echo -e "${CHECKMARK} Current version: ${YELLOW}$SCRIPT_VERSION${NC}"
    echo -e "${CHECKMARK} Latest version: ${YELLOW}$LATEST_VERSION${NC}"

    if [[ "$LATEST_VERSION" != "$SCRIPT_VERSION" ]]; then
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

# Function to run the speed test
run_speed_test() {
    local attempts=0
    local max_attempts=3
    local SPEEDTEST_OUTPUT=""
    
    while [ $attempts -lt $max_attempts ]; do
        echo -e "${CYAN}Running Speed Test (Attempt $((attempts+1)) of $max_attempts)...${NC}"
        SPEEDTEST_OUTPUT=$(speedtest-cli --csv --secure --share 2>&1)
        
        if [[ $? -eq 0 && -n "$SPEEDTEST_OUTPUT" ]]; then
            echo -e "${CHECKMARK} Speed Test completed successfully."
            break
        else
            log_error "Speed Test failed on attempt $((attempts+1))."
            attempts=$((attempts+1))
            sleep 5
        fi
    done

    if [ -z "$SPEEDTEST_OUTPUT" ]; then
        log_error "Speed Test output is empty after all attempts."
        return 1
    fi

    # Extracting fields from speed test output
    DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $7 / 1000000}')
    UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $8 / 1000000}')
    SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $9}')
    SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')

    if [[ -z "$DOWNLOAD_SPEED" || -z "$UPLOAD_SPEED" ]]; then
        log_error "Failed to extract speed results."
        return 1
    fi

    echo -e "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Download Speed" "$DOWNLOAD_SPEED Mbps"
    echo -e "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Upload Speed" "$UPLOAD_SPEED Mbps"
    echo -e "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Shareable ID" "$SHARE_ID"
}

# Main script execution starts here
apply_forced_errors
check_force_update

echo -e "${CYAN}====================================================${NC}"
echo -e "     ${CYAN}Welcome to VeriNexus Speed Test 2024${NC}"
echo -e "${CYAN}====================================================${NC}"

run_speed_test

# Step 7: Save results to the remote server
RESULT_LINE="Download Speed: $DOWNLOAD_SPEED, Upload Speed: $UPLOAD_SPEED"
echo "$RESULT_LINE" > "$SPEEDTEST_RESULTS_CSV"

sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
"cat $SPEEDTEST_RESULTS_CSV >> $REMOTE_PATH"

if [ $? -eq 0 ]; then
    echo -e "${CHECKMARK} Results saved to the remote server."
else
    log_error "Failed to save results to the remote server."
fi

echo -e "${CYAN}====================================================${NC}"
echo -e "     ${CYAN}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
