#!/bin/bash

# Version number of the script
SCRIPT_VERSION="2.3.7"

# GitHub repository raw URLs for the script and forced error file
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
FORCED_ERROR_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/force_error.txt"

# Temporary files for comparison and forced error
TEMP_SCRIPT="/tmp/latest_speedtest.sh"
FORCED_ERROR_FILE="/tmp/force_error.txt"
ERROR_LOG=""
MAX_ERROR_LOG_SIZE=2048  # 2KB for testing

# InfluxDB configuration
INFLUXDB_URL="http://82.165.7.116:8086"
INFLUXDB_DB="speedtest_db"
INFLUXDB_MEASUREMENT="speedtest"

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
    echo -e "${CROSS} ${RED}Error: $error_message${NC}"
}

# Function to check for dependencies
check_dependencies() {
    local dependencies=("curl" "speedtest-cli" "awk" "ip" "jq")
    local missing=()

    echo -e "${CYAN}Checking for necessary dependencies...${NC}"
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}The following dependencies are missing:${NC} ${missing[*]}"
        echo -e "${YELLOW}Attempting to install missing dependencies...${NC}"
        sudo apt-get update && sudo apt-get install -y "${missing[@]}"
        
        # Check again to confirm installation was successful
        for dep in "${missing[@]}"]; do
            if ! command -v "$dep" &> /dev/null; then
                echo -e "${RED}Failed to install $dep. Exiting.${NC}"
                exit 1
            fi
        done
        echo -e "${CHECKMARK} All dependencies are installed.${NC}"
    else
        echo -e "${CHECKMARK} All dependencies are already installed.${NC}"
    fi
}

# Function to compare versions using awk (Reintroduced)
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

# Function to check for forced error file and apply its effects
apply_forced_errors() {
    curl -H 'Cache-Control: no-cache, no-store, must-revalidate' \
         -H 'Pragma: no-cache' \
         -H 'Expires: 0' \
         -s -o "$FORCED_ERROR_FILE" "$FORCED_ERROR_URL"

    if [ -s "$FORCED_ERROR_FILE" ]; then
        echo -e "${RED}Forced error file found. Applying forced errors...${NC}"
        echo -e "Contents of force_error.txt file being applied:"
        cat "$FORCED_ERROR_FILE"
        
        if bash -n "$FORCED_ERROR_FILE"; then
            . "$FORCED_ERROR_FILE"
        else
            log_error "Forced error file contains invalid syntax. Deleting local copy."
            rm -f "$FORCED_ERROR_FILE"
        fi
    else
        if [ -f "$FORCED_ERROR_FILE" ]; then
            echo -e "${YELLOW}Forced error file removed from GitHub. Deleting local copy...${NC}"
            rm -f "$FORCED_ERROR_FILE"
        fi
    fi
}

# Function to check for updates
check_for_updates() {
    echo -e "${CYAN}====================================================${NC}"
    echo -e "           ${BOLD}Checking for Script Updates...${NC}"
    echo -e "${CYAN}====================================================${NC}"

    rm -f "$TEMP_SCRIPT"

    local max_attempts=3
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
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

# Function to run the speed test
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
            sleep 5
        fi
    done

    if [ $attempts -eq $max_attempts ]; then
        return 1
    fi
    return 0
}

# Apply any forced errors
apply_forced_errors

# Check for dependencies
check_dependencies

# Call the update check function
check_for_updates

# Step 1: Running Speed Test
run_speed_test
if [ $? -ne 0 ]; then
    log_error "Speed Test failed after maximum attempts."
    exit 1
fi

# Step 2: Fetching Date and Time (UK Time - GMT/BST)
UK_DATE=$(TZ="Europe/London" date +"%Y-%m-%d")
UK_TIME=$(TZ="Europe/London" date +"%H:%M:%S")

# Step 3: Fetching Private/Public IPs
PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.co)

# Step 4: Fetching MAC Address and LAN IP
ACTIVE_IFACE=$(ip route | grep default | awk '{print $5}')
MAC_ADDRESS=$(cat /sys/class/net/$ACTIVE_IFACE/address)
LAN_IP=$(ip addr show $ACTIVE_IFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)

# Step 5: Extracting Speedtest Data (Escaping and Unquoting Properly)
SERVER_ID=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $1}')
SERVER_NAME=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $2}' | sed 's/ /\\ /g' | sed 's/,/\\,/g')  # Escape spaces and commas
LOCATION=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $3}' | sed 's/ /\\ /g' | sed 's/,/\\,/g')    # Escape spaces and commas
LATENCY=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $6}')
DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $7 / 1000000}')
UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $8 / 1000000}')
PUBLIC_IP=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $10}')

if [[ -z "$DOWNLOAD_SPEED" || -z "$UPLOAD_SPEED" || -z "$LATENCY" || -z "$PUBLIC_IP" ]]; then
    log_error "Speed Test did not return valid data."
    DOWNLOAD_SPEED="0.00"
    UPLOAD_SPEED="0.00"
    LATENCY="0.00"
    PUBLIC_IP="N/A"
fi

# Step 6: Writing Results to InfluxDB (Tags Unquoted, Fields Quoted Properly)
curl -i -XPOST "$INFLUXDB_URL/write?db=$INFLUXDB_DB" --data-binary \
"$INFLUXDB_MEASUREMENT,server_id=$SERVER_ID,server_name=$SERVER_NAME,location=$LOCATION latency=$LATENCY,download_speed=$DOWNLOAD_SPEED,upload_speed=$UPLOAD_SPEED,public_ip=\"$PUBLIC_IP\",mac_address=\"$MAC_ADDRESS\",lan_ip=\"$LAN_IP\",hostname=\"$HOSTNAME\",date=\"$UK_DATE\",time=\"$UK_TIME\""

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
