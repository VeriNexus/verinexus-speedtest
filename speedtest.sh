#!/bin/bash

# Version number of the script
SCRIPT_VERSION="2.2.6"

# GitHub repository raw URLs for the script and forced error file
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
FORCED_ERROR_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/force_error.txt"

# Temporary files for comparison and forced error
TEMP_SCRIPT="/tmp/latest_speedtest.sh"
FORCED_ERROR_FILE="/tmp/force_error.txt"
ERROR_LOG=""
MAX_ERROR_LOG_SIZE=2048  # 2KB for testing

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

    # Ensure the directory for the error log exists
    if [ ! -d "$(dirname "$ERROR_LOG_PATH")" ]; then
        mkdir -p "$(dirname "$ERROR_LOG_PATH")"
    fi

    # Format the error log entry as a single line in CSV format
    local error_entry="$error_id,$timestamp,$script_version,$hostname,$private_ip,$public_ip,\"$error_message\""

    # Write the error entry to the log file
    echo -e "$error_entry" >> "$ERROR_LOG_PATH"

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

        # Display the contents of the downloaded force_error.txt file for debugging
        echo -e "Contents of force_error.txt file being applied:"
        cat "$FORCED_ERROR_FILE"

        # Validate the file before sourcing it
        if bash -n "$FORCED_ERROR_FILE"; then
            # Force sourcing to ensure proper application
            . "$FORCED_ERROR_FILE"
            # Debugging statements
            echo -e "${YELLOW}Applied Forced Errors:${NC}"
            echo "FORCE_FAIL_PRIVATE_IP=${FORCE_FAIL_PRIVATE_IP:-false}"
            echo "FORCE_FAIL_PUBLIC_IP=${FORCE_FAIL_PUBLIC_IP:-false}"
            echo "FORCE_FAIL_MAC=${FORCE_FAIL_MAC:-false}"
        else
            log_error "Forced error file contains invalid syntax. Deleting local copy."
            rm -f "$FORCED_ERROR_FILE"
        fi
    else
        # If the forced error file was previously downloaded but no longer exists in the repo, remove it
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

# Function to check for updates with retry logic
check_for_updates() {
    echo -e "${CYAN}====================================================${NC}"
    echo -e "           ${BOLD}Checking for Script Updates...${NC}"
    echo -e "${CYAN}====================================================${NC}"

    # Clear any previous version of the file
    rm -f "$TEMP_SCRIPT"

    local max_attempts=3
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        # Download the latest version of the script with cache control headers
        curl -H 'Cache-Control: no-cache, no-store, must-revalidate' \
             -H 'Pragma: no-cache' \
             -H 'Expires: 0' \
             -s -o "$TEMP_SCRIPT" "$REPO_RAW_URL"
        if [ $? -eq 0 ]; then
            break
        else
            log_error "Failed to download the script from GitHub. Retrying...($attempt)"
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

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

# Retry function to retry the speed test in case of failure
run_speed_test() {
    local attempts=0
    local max_attempts=3
    while [ $attempts -lt $max_attempts ]; do
        echo -e "${BLUE}Attempting speed test (Attempt $((attempts+1)) of $max_attempts)...${NC}"
        SPEEDTEST_OUTPUT=$(speedtest-cli --csv --secure --share)
        if [ $? -eq 0 ]; then
            echo -e "${CHECKMARK} Speed Test completed successfully."
            break
        else
            log_error "Speed Test failed on attempt $((attempts+1))."
            attempts=$((attempts+1))
            sleep 5  # Wait before retrying
        fi
    done

    if [ $attempts -eq $max_attempts ]; then
        return 1  # Fail if all attempts failed
    fi
    return 0
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
run_speed_test
if [ $? -ne 0 ]; then
    log_error "Speed Test failed after maximum attempts."
    exit 1
fi

# Step 2: Fetching Date and Time (UK Time - GMT/BST)
UK_DATE=$(TZ="Europe/London" date +"%Y-%m-%d")
UK_TIME=$(TZ="Europe/London" date +"%H:%M:%S")
printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 2: Fetching Date and Time (UK Time)" "Date (UK): $UK_DATE, Time (UK): $UK_TIME"

# Step 3: Fetching Private/Public IPs
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
printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 3: Fetching Private/Public IPs" "Private IP: $PRIVATE_IP, Public IP: $PUBLIC_IP"

# Step 4: Fetching MAC Address
ACTIVE_IFACE=$(ip route | grep default | awk '{print $5}')
if [ "$FORCE_FAIL_MAC" = true ]; then
    log_error "Forced failure to fetch MAC Address."
    MAC_ADDRESS="N/A"
elif [ -n "$ACTIVE_IFACE" ]; then
    MAC_ADDRESS=$(cat /sys/class/net/$ACTIVE_IFACE/address)
    printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 4: Fetching MAC Address" "MAC Address: $MAC_ADDRESS"
else
    log_error "Could not determine active network interface."
fi

# Step 5: Converting Speed Results
DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $7 / 1000000}')  # Converting download speed from bps to Mbps
UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $8 / 1000000}')    # Converting upload speed from bps to Mbps

if [[ -z "$DOWNLOAD_SPEED" || -z "$UPLOAD_SPEED" ]]; then
    log_error "Speed Test did not return valid download/upload speeds."
    DOWNLOAD_SPEED="0.00"
    UPLOAD_SPEED="0.00"
fi
printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 5: Converting Speed Results" "Download Speed: $DOWNLOAD_SPEED Mbps, Upload Speed: $UPLOAD_SPEED Mbps"

# Step 6: Extracting Shareable ID
SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $9}')
SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')
printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 6: Extracting Shareable ID" "Shareable ID: $SHARE_ID"

# Step 7: Saving Results (Remove the distance field)
HOSTNAME=$(hostname)
CLIENT_ID=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $1}')
SERVER_NAME=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $2}')
LOCATION=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $3}')
LATENCY=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $5}')
JITTER=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $6}')

RESULT_LINE="$CLIENT_ID,$SERVER_NAME,$LOCATION,$LATENCY,$JITTER,$DOWNLOAD_SPEED,$UPLOAD_SPEED,$SHARE_ID,$PRIVATE_IP,$PUBLIC_IP,$HOSTNAME,$UK_DATE,$UK_TIME,$MAC_ADDRESS"

# Define the header for the CSV file
HEADER_LINE="Client ID,Server Name,Location,Latency (ms),Jitter (ms),Download Speed (Mbps),Upload Speed (Mbps),Shareable ID,Private IP,Public IP,Hostname,Date (UK),Time (UK),MAC Address"

# Check if the CSV file exists and is non-empty, if not, add the header
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "
    if [ ! -s '$REMOTE_PATH' ]; then
        echo '$HEADER_LINE' >> '$REMOTE_PATH'
    fi
"

# Run the SSH command with password authentication to save results
echo -e "${BLUE}Running SSH command to save results...${NC}"
ssh_attempts=0
max_ssh_attempts=3
while [ $ssh_attempts -lt $max_ssh_attempts ]; do
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
    "echo '$RESULT_LINE' >> '$REMOTE_PATH'"
    if [ $? -eq 0 ]; then
        printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 7: Saving Results" "Results saved to the remote server."
        break
    else
        log_error "Failed to save results to remote server. Retrying...($ssh_attempts)"
        ssh_attempts=$((ssh_attempts + 1))
        sleep 5
    fi
done

# If any errors occurred, upload the error log
if [ -n "$ERROR_LOG" ]; then
    echo -e "${BLUE}Uploading error log...${NC}"
    # Create a temporary file for the error log
    TEMP_ERROR_LOG=$(mktemp)
    echo -e "$ERROR_LOG" > "$TEMP_ERROR_LOG"

    # Upload the error log and implement size limitation on the remote server
    sshpass -p "$REMOTE_PASS" scp -o StrictHostKeyChecking=no "$TEMP_ERROR_LOG" "$REMOTE_USER@$REMOTE_HOST:/tmp/error_temp.txt"
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "
        if [ -f '$ERROR_LOG_PATH' ]; then
            mv '$ERROR_LOG_PATH' '/tmp/old_error_log.txt'
            cat /tmp/error_temp.txt /tmp/old_error_log.txt > '$ERROR_LOG_PATH'
            rm /tmp/old_error_log.txt
        else
            mv /tmp/error_temp.txt '$ERROR_LOG_PATH'
        fi
        rm /tmp/error_temp.txt
        FILE_SIZE=\$(stat -c%s '$ERROR_LOG_PATH')
        MAX_SIZE=$MAX_ERROR_LOG_SIZE
        if [ \$FILE_SIZE -gt \$MAX_SIZE ]; then
            while [ \$FILE_SIZE -gt \$MAX_SIZE ]; do
                sed -i '1d' '$ERROR_LOG_PATH'  # Delete older entries to maintain latest logs
                FILE_SIZE=\$(stat -c%s '$ERROR_LOG_PATH')
            done
        fi
    "

    if [ $? -eq 0 ]; then
        echo -e "${CHECKMARK} All errors logged and uploaded."
    else
        echo -e "${CROSS} ${RED}Failed to upload error log to the remote server.${NC}"
    fi
    rm -f "$TEMP_ERROR_LOG"
fi

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
