#!/bin/bash

# Version number of the script
SCRIPT_VERSION="2.3.8"

# GitHub repository raw URLs for the script and forced error file
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
FORCED_ERROR_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/force_error.txt"

# Temporary files for comparison and forced error
TEMP_SCRIPT="/tmp/latest_speedtest.sh"
FORCED_ERROR_FILE="/tmp/force_error.txt"
ERROR_LOG=""
MAX_ERROR_LOG_SIZE=2048  # 2KB for testing

# InfluxDB details
INFLUXDB_SERVER="http://82.165.7.116:8086"
INFLUXDB_DATABASE="speedtest_db"

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
    local active_iface=$(ip route | grep default | awk '{print $5}')
    local mac_address=$(cat /sys/class/net/$active_iface/address)

    # Format the error log entry
    local error_entry="$error_id,$timestamp,$script_version,$hostname,$private_ip,$public_ip,$mac_address,\"$error_message\""

    echo -e "${CROSS} ${RED}Error: $error_message${NC}"
}

# Function to check for forced error file and apply its effects
apply_forced_errors() {
    curl -s -H 'Cache-Control: no-cache, no-store, must-revalidate' \
         -H 'Pragma: no-cache' \
         -H 'Expires: 0' \
         -o "$FORCED_ERROR_FILE" "$FORCED_ERROR_URL"

    if [ -s "$FORCED_ERROR_FILE" ]; then
        echo -e "${RED}Forced error file found. Applying forced errors...${NC}"
        if bash -n "$FORCED_ERROR_FILE"; then
            . "$FORCED_ERROR_FILE"
        else
            log_error "Invalid forced error file syntax."
            rm -f "$FORCED_ERROR_FILE"
        fi
    fi
}

# Function to check for updates
check_for_updates() {
    echo -e "${CYAN}Checking for Script Updates...${NC}"
    rm -f "$TEMP_SCRIPT"

    curl -s -H 'Cache-Control: no-cache, no-store, must-revalidate' \
         -o "$TEMP_SCRIPT" "$REPO_RAW_URL"

    LATEST_VERSION=$(grep -oP 'SCRIPT_VERSION="\K[0-9.]+' "$TEMP_SCRIPT")
    if [ -z "$LATEST_VERSION" ]; then
        log_error "Failed to retrieve the latest version."
        return 1
    fi

    if awk -v v1="$LATEST_VERSION" -v v2="$SCRIPT_VERSION" 'BEGIN {
            split(v1, a, "."); split(v2, b, ".");
            for (i=1; i<=length(a); i++) if (a[i] != b[i]) exit a[i] > b[i];
            exit 0;
        }'; then
        cp "$TEMP_SCRIPT" "$0"
        chmod +x "$0"
        echo -e "${CHECKMARK} Update completed. Please re-run the script."
        exit 0
    else
        echo -e "${GREEN}No updates available.${NC}"
    fi
}

# Function to test speed and store the results
run_speed_test() {
    SPEEDTEST_OUTPUT=$(speedtest-cli --csv --secure --share)
    IFS=',' read -r SERVER_ID SERVER_NAME LOCATION LATENCY DOWNLOAD_SPEED UPLOAD_SPEED _ PUBLIC_IP <<< "$SPEEDTEST_OUTPUT"

    # Check if values are valid
    if [[ -z "$DOWNLOAD_SPEED" || -z "$UPLOAD_SPEED" || -z "$LATENCY" ]]; then
        log_error "Speed Test returned invalid results."
        return 1
    fi

    # Prepare the InfluxDB line protocol entry
    INFLUX_LINE="speedtest,server_id=$SERVER_ID,server_name=\"$SERVER_NAME\",location=\"$LOCATION\" latency=$LATENCY,download_speed=$DOWNLOAD_SPEED,upload_speed=$UPLOAD_SPEED,public_ip=\"$PUBLIC_IP\",hostname=\"$(hostname)\",lan_ip=\"$(hostname -I | awk '{print $1}')\""

    # Send the results to InfluxDB
    curl -i -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DATABASE" --data-binary "$INFLUX_LINE"

    return 0
}

# Main execution starts here
apply_forced_errors
check_for_updates

echo -e "${CYAN}Starting VeriNexus Speed Test...${NC}"

run_speed_test || log_error "Failed to complete speed test."

echo -e "${CYAN}VeriNexus Speed Test Completed!${NC}"
