#!/bin/bash

# Version number of the script
SCRIPT_VERSION="2.0.13"

# GitHub repository raw URLs for the script and forced error file
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
FORCED_ERROR_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/force_error.txt"

# Temporary files for comparison and forced error
TEMP_SCRIPT="/tmp/latest_speedtest.sh"
FORCED_ERROR_FILE="/tmp/force_error.txt"
ERROR_LOG=""
MAX_ERROR_LOG_SIZE=2048  # 2KB for testing

# SSH connection details (Password included as per your request)
REMOTE_USER="root"
REMOTE_HOST="88.208.225.250"
REMOTE_PATH="/speedtest/results/speedtest_results.csv"
ERROR_LOG_PATH="/speedtest/results/error.txt"
REMOTE_PASS='[YOUR_PASSWORD]'  # Replace [YOUR_PASSWORD] with your actual password

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

# Function to check for forced error file and apply its effects
apply_forced_errors() {
    # Download the forced error file with cache control to prevent caching
    curl -H 'Cache-Control: no-cache, no-store, must-revalidate' \
         -H 'Pragma: no-cache' \
         -H 'Expires: 0' \
         -s -o "$FORCED_ERROR_FILE" "$FORCED_ERROR_URL"

    # Check if the forced error file was successfully downloaded
    if [ -s "$FORCED_ERROR_FILE" ]; then
        echo -e "${RED}Forced error file found. Applying forced errors...${NC}"
        source "$FORCED_ERROR_FILE"
        # Debugging statements
        echo -e "${YELLOW}Applied Forced Errors:${NC}"
        echo "FORCE_FAIL_PRIVATE_IP=$FORCE_FAIL_PRIVATE_IP"
        echo "FORCE_FAIL_PUBLIC_IP=$FORCE_FAIL_PUBLIC_IP"
        echo "FORCE_FAIL_MAC=$FORCE_FAIL_MAC"
    else
        # If the forced error file was previously downloaded but no longer exists in the repo, remove it
        if [ -f "$FORCED_ERROR_FILE" ]; then
            echo -e "${YELLOW}Forced error file removed from GitHub. Deleting local copy...${NC}"
            rm -f "$FORCED_ERROR_FILE"
        fi
    }
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
        return 1
    fi

    # Ensure the downloaded file is valid
    if [ ! -s "$TEMP_SCRIPT" ]; then
        log_error "Downloaded script is empty."
        return 1
    fi

    # Extract version from the downloaded script
    LATEST_VERSION=$(grep -oP 'SCRIPT_VERSION="\K[0-9.]+' "$TEMP_SCRIPT")
    if [ -z "$LATEST_VERSION" ]; then
        log_error "Failed to extract version from the downloaded script."
        return 1
    fi

    echo -e "${CHECKMARK} Current version: ${YELLOW}$SCRIPT_VERSION${NC}"
    echo -e "${CHECKMARK} Latest version: ${YELLOW}$LATEST_VERSION${NC}"

    # Compare versions to check if we should upgrade
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

# Function to run the speed test with retries
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
            log_error "Speed Test failed on attempt $((attempts+1))."
            attempts=$((attempts+1))
            sleep 5  # Wait before retrying
        fi
    done
    return 1  # Fail if all attempts failed
}

# Apply any forced errors
apply_forced_errors

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
echo -e "${CYAN}│${NC}  Step 1: ${BOLD}Running Speed Test${NC}           ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

if ! run_speed_test; then
    log_error "Speed Test failed after multiple attempts."
fi

# Step 2: Fetching Date and Time (UK Time - GMT/BST)
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 2: ${BOLD}Fetching Date and Time (UK Time)${NC} ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

UK_DATE=$(TZ="Europe/London" date +"%Y-%m-%d")
UK_TIME=$(TZ="Europe/London" date +"%H:%M:%S")
echo -e "${CHECKMARK} Date (UK): ${YELLOW}$UK_DATE${NC}, Time (UK): ${YELLOW}$UK_TIME${NC}"

# Step 3: Fetching Private/Public IPs
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 3: ${BOLD}Fetching Private/Public IPs${NC}    ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

if [ "$FORCE_FAIL_PRIVATE_IP" = true ]; then
    log_error "Forced failure to fetch Private IP."
    PRIVATE_IP="N/A"
else
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
fi

if [ "$FORCE_FAIL_PUBLIC_IP" = true ]; then
    log_error "Forced failure to fetch Public IP."
    PUBLIC_IP="N/A"
else
    PUBLIC_IP=$(curl -s ifconfig.co)
fi

echo -e "${CHECKMARK} Private IP: ${YELLOW}$PRIVATE_IP${NC}, Public IP: ${YELLOW}$PUBLIC_IP${NC}"

# Step 4: Fetching MAC Address
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 4: ${BOLD}Fetching MAC Address${NC}          ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

ACTIVE_IFACE=$(ip route | grep default | awk '{print $5}')
if [ "$FORCE_FAIL_MAC" = true ]; then
    log_error "Forced failure to fetch MAC Address."
    MAC_ADDRESS="N/A"
elif [ -n "$ACTIVE_IFACE" ]; then
    MAC_ADDRESS=$(cat /sys/class/net/$ACTIVE_IFACE/address)
    echo -e "${CHECKMARK} Active Interface: ${YELLOW}$ACTIVE_IFACE${NC}, MAC Address: ${YELLOW}$MAC_ADDRESS${NC}"
else
    log_error "Could not determine active network interface."
    MAC_ADDRESS="N/A"
fi

# Step 5: Converting Speed Results
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 5: ${BOLD}Converting Speed Results${NC}      ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $7 / 1000000}')
UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $8 / 1000000}')
echo -e "${CHECKMARK} Download Speed: ${GREEN}$DOWNLOAD_SPEED Mbps${NC}, Upload Speed: ${GREEN}$UPLOAD_SPEED Mbps${NC}"

# Step 6: Extracting Shareable ID
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 6: ${BOLD}Extracting Shareable ID${NC}       ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $9}')
SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')
echo -e "${CHECKMARK} Shareable ID: ${YELLOW}$SHARE_ID${NC}"

# Step 7: Saving Results
echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  Step 7: ${BOLD}Saving Results${NC}                ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

HOSTNAME=$(hostname)
CLIENT_ID=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $1}')
SERVER_NAME=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $2}')
LOCATION=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $3}')
LATENCY=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $5}')
JITTER=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $6}')

RESULT_LINE="$CLIENT_ID,$SERVER_NAME,$LOCATION,$LATENCY,$JITTER,$DOWNLOAD_SPEED,$UPLOAD_SPEED,$SHARE_ID,$PRIVATE_IP,$PUBLIC_IP,$HOSTNAME,$UK_DATE,$UK_TIME,$MAC_ADDRESS"

# Run the SSH command with password authentication to save results
echo -e "${BLUE}Running SSH command to save results...${NC}"
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
"echo '$RESULT_LINE' >> '$REMOTE_PATH'"

if [ $? -eq 0 ]; then
    echo -e "${CHECKMARK} Results saved to the remote server."
else
    log_error "Failed to save results to the remote server."
fi

# If any errors occurred, upload the error log
if [ -n "$ERROR_LOG" ]; then
    echo -e "${BLUE}Uploading error log...${NC}"
    # Create a temporary file for the error log
    TEMP_ERROR_LOG=$(mktemp)
    echo -e "$ERROR_LOG" > "$TEMP_ERROR_LOG"

    # Upload the error log and implement size limitation on the remote server
    sshpass -p "$REMOTE_PASS" scp -o StrictHostKeyChecking=no "$TEMP_ERROR_LOG" "$REMOTE_USER@$REMOTE_HOST:/tmp/error_temp.txt"
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "
        # Prepend the new error log entry to the existing error log
        if [ -f '$ERROR_LOG_PATH' ]; then
            mv '$ERROR_LOG_PATH' '/tmp/old_error_log.txt'
            cat /tmp/error_temp.txt /tmp/old_error_log.txt > '$ERROR_LOG_PATH'
            rm /tmp/old_error_log.txt
        else
            mv /tmp/error_temp.txt '$ERROR_LOG_PATH'
        fi
        # Remove the temporary error log file
        rm /tmp/error_temp.txt
        # Check the size of the error log file
        FILE_SIZE=\$(stat -c%s '$ERROR_LOG_PATH')
        MAX_SIZE=$MAX_ERROR_LOG_SIZE
        if [ \$FILE_SIZE -gt \$MAX_SIZE ]; then
            # Truncate the oldest entries from the end to reduce the file size
            while [ \$FILE_SIZE -gt \$MAX_SIZE ]; do
                # Remove the last line (oldest entry)
                sed -i '\$d' '$ERROR_LOG_PATH'
                FILE_SIZE=\$(stat -c%s '$ERROR_LOG_PATH')
            done
        fi
    "

    if [ $? -eq 0 ]; then
        echo -e "${CHECKMARK} All errors logged and uploaded."
    else
        echo -e "${CROSS} ${RED}Failed to upload error log to the remote server.${NC}"
    fi

    # Remove the temporary error log file
    rm -f "$TEMP_ERROR_LOG"
fi

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
