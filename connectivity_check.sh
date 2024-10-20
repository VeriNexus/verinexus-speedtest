#!/bin/bash

# Version number of the script
SCRIPT_VERSION="1.2"

# GitHub repository raw URL for the script
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/connectivity_check.sh"

# Temporary file for comparison
TEMP_SCRIPT="/tmp/latest_connectivity_check.sh"
LOG_FILE="/var/log/verinexus_connectivity.log"
[ -w "/var/log" ] || LOG_FILE="/tmp/verinexus_connectivity.log"
MAX_LOG_SIZE=5242880  # 5MB

# InfluxDB Configuration
INFLUXDB_SERVER="http://82.165.7.116:8086"
INFLUXDB_DB="connectivity_db"
INFLUXDB_MEASUREMENT="connectivity"
HEARTBEAT_MEASUREMENT="heartbeat"

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Maximum number of retries to prevent infinite loops
MAX_RETRIES=3
RETRY_COUNT=0

# Logging levels
LOG_LEVELS=("INFO" "WARN" "ERROR")

# Initialize variables
CURRENT_STATUS="unknown"
LAST_CHANGE_TIME=$(date +%s)
UPTIME=0
DOWNTIME=0
OUTAGE_COUNT=0
LAST_OUTAGE_TIME="N/A"
HEARTBEAT_INTERVAL=60  # Heartbeat every 60 seconds
HEARTBEAT_LAST_SENT=$(date +%s)

# Function to rotate log file
rotate_log_file() {
    if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -ge "$MAX_LOG_SIZE" ]; then
        mv "$LOG_FILE" "${LOG_FILE}_$(date '+%Y%m%d%H%M%S')"
        touch "$LOG_FILE"
    fi
}

# Function to get MAC address
get_mac_address() {
    ACTIVE_IFACE=$(ip route | grep default | awk '{print $5}')
    if [ -n "$ACTIVE_IFACE" ]; then
        MAC_ADDRESS=$(cat /sys/class/net/$ACTIVE_IFACE/address)
    else
        MAC_ADDRESS="00:00:00:00:00:00"
        log_message "WARN" "Could not determine active network interface."
    fi
}

# Function to log messages with levels
log_message() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    local script_version="$SCRIPT_VERSION"

    if [[ " ${LOG_LEVELS[*]} " == *" $level "* ]]; then
        echo "$timestamp [Version $script_version] [$level]: $message" >> "$LOG_FILE"
    else
        echo "$timestamp [Version $script_version] [UNKNOWN]: $message" >> "$LOG_FILE"
    fi
}

# Rotate log file at the start
rotate_log_file

# Function to check dependencies
check_dependencies() {
    local missing_dependencies=false
    local dependencies=("curl" "ping" "tput" "ip" "awk")

    for dep in "${dependencies[@]}"; do
        if ! command -v $dep &> /dev/null; then
            echo -e "${RED}Error: $dep is not installed.${NC}"
            log_message "ERROR" "$dep is not installed."
            missing_dependencies=true
        fi
    done

    if [ "$missing_dependencies" = true ]; then
        echo -e "${RED}Please install the missing dependencies and rerun the script.${NC}"
        exit 1
    fi
}

# Call the check_dependencies function early in the script
check_dependencies

# Get MAC address
get_mac_address

# Function to compare versions
version_gt() {
    awk -v v1="$1" -v v2="$2" '
    BEGIN {
        split(v1, a, ".")
        split(v2, b, ".")
        for (i = 1; i <= 3; i++) {
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
    # Clear any previous version of the file
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
            log_message "WARN" "Failed to download the script from GitHub. Retrying...($attempt)"
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    # Ensure the downloaded file is valid
    if [ ! -s "$TEMP_SCRIPT" ]; then
        log_message "ERROR" "Downloaded script is empty."
        return 1
    fi

    # Extract version from the downloaded script
    LATEST_VERSION=$(grep -oP 'SCRIPT_VERSION="\K[0-9.]+' "$TEMP_SCRIPT")
    if [ -z "$LATEST_VERSION" ]; then
        log_message "ERROR" "Failed to extract version from the downloaded script."
        return 1
    fi

    # Compare versions to check if we should upgrade
    if version_gt "$LATEST_VERSION" "$SCRIPT_VERSION"; then
        cp "$TEMP_SCRIPT" "$0"
        chmod +x "$0"
        log_message "INFO" "Updated script to version $LATEST_VERSION."
        if [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; then
            RETRY_COUNT=$((RETRY_COUNT + 1))
            exec "$0"
        else
            log_message "ERROR" "Maximum retries reached. Exiting to prevent infinite loop."
            exit 1
        fi
    fi
}

# Call the update check function
check_for_updates

# Function to create database if it doesn't exist
create_database_if_not_exists() {
    local db_name=$1
    local databases=$(curl -s -G "$INFLUXDB_SERVER/query" --data-urlencode "q=SHOW DATABASES")
    if ! echo "$databases" | grep -q "\"$db_name\""; then
        curl -s -XPOST "$INFLUXDB_SERVER/query" --data-urlencode "q=CREATE DATABASE $db_name" >/dev/null 2>&1
        log_message "INFO" "Created InfluxDB database: $db_name"
    fi
}

# Ensure the database exists
create_database_if_not_exists "$INFLUXDB_DB"

# Function to check connectivity
check_connectivity() {
    local target="8.8.8.8"  # You can change this to any reliable host
    local timestamp=$(date +%s)
    if ping -c 1 -W 1 $target >/dev/null 2>&1; then
        # Connectivity is up
        local status="up"
    else
        # Connectivity is down
        local status="down"
    fi

    # Update uptime/downtime
    local current_time=$(date +%s)
    local time_diff=$((current_time - LAST_CHECK_TIME))
    LAST_CHECK_TIME=$current_time

    if [ "$status" == "up" ]; then
        UPTIME=$((UPTIME + time_diff))
    else
        DOWNTIME=$((DOWNTIME + time_diff))
    fi

    # Check for status change
    if [ "$status" != "$CURRENT_STATUS" ]; then
        # Status has changed
        CURRENT_STATUS="$status"
        LAST_CHANGE_TIME=$current_time

        # Increment outage count if status changed to down
        if [ "$status" == "down" ]; then
            OUTAGE_COUNT=$((OUTAGE_COUNT + 1))
            LAST_OUTAGE_TIME=$(date +"%Y-%m-%d %H:%M:%S")
            log_message "WARN" "Connectivity lost at $LAST_OUTAGE_TIME"
        else
            log_message "INFO" "Connectivity restored at $(date +"%Y-%m-%d %H:%M:%S")"
        fi

        # Prepare data for InfluxDB
        local data="$INFLUXDB_MEASUREMENT,mac_address=$MAC_ADDRESS status=\"$status\" $((timestamp * 1000000000))"

        # Send data to InfluxDB
        curl -s -o /dev/null -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DB" --data-binary "$data"
    fi

    # Send heartbeat every HEARTBEAT_INTERVAL seconds
    if [ $((current_time - HEARTBEAT_LAST_SENT)) -ge "$HEARTBEAT_INTERVAL" ]; then
        send_heartbeat
        HEARTBEAT_LAST_SENT=$current_time
    fi
}

# Function to send heartbeat
send_heartbeat() {
    local timestamp=$(date +%s)
    local data="$HEARTBEAT_MEASUREMENT,mac_address=$MAC_ADDRESS running=1 $((timestamp * 1000000000))"
    curl -s -o /dev/null -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DB" --data-binary "$data"
}

# Function to display UI
display_ui() {
    local clear_screen=$(tput clear)
    local move_top_left=$(tput cup 0 0)
    echo -e "${clear_screen}${move_top_left}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "     ${BOLD}Welcome to VeriNexus Connectivity Tester 2024${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}(C) 2024 VeriNexus. All Rights Reserved.${NC}"
    echo -e "${YELLOW}Script Version: $SCRIPT_VERSION${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"

    # Current Status
    if [ "$CURRENT_STATUS" == "up" ]; then
        local status_display="${GREEN}UP${NC}"
    elif [ "$CURRENT_STATUS" == "down" ]; then
        local status_display="${RED}DOWN${NC}"
    else
        local status_display="${YELLOW}UNKNOWN${NC}"
    fi

    # Uptime Percentage
    local total_time=$((UPTIME + DOWNTIME))
    if [ "$total_time" -gt 0 ]; then
        local uptime_percentage=$(awk "BEGIN {printf \"%.2f\", ($UPTIME / $total_time) * 100}")
    else
        local uptime_percentage="100.00"
    fi

    # Time Since Last Outage
    if [ "$LAST_OUTAGE_TIME" != "N/A" ]; then
        local last_outage_seconds=$(( $(date +%s) - $(date -d "$LAST_OUTAGE_TIME" +%s) ))
        local time_since_last_outage=$(printf '%dd %dh %dm %ds\n' $((last_outage_seconds/86400)) $(( (last_outage_seconds%86400)/3600 )) $(( (last_outage_seconds%3600)/60 )) $((last_outage_seconds%60)))
    else
        local time_since_last_outage="N/A"
    fi

    echo -e "${BOLD}Current Status: ${status_display}${NC}"
    echo -e "${BOLD}Uptime Percentage: ${GREEN}$uptime_percentage%${NC}"
    echo -e "${BOLD}Total Uptime: $(display_time $UPTIME)${NC}"
    echo -e "${BOLD}Total Downtime: $(display_time $DOWNTIME)${NC}"
    echo -e "${BOLD}Outage Count: $OUTAGE_COUNT${NC}"
    echo -e "${BOLD}Time Since Last Outage: $time_since_last_outage${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "${BOLD}Press Ctrl+C to exit.${NC}"
}

# Function to format time in hh:mm:ss
display_time() {
    local total_seconds=$1
    printf '%dd %dh %dm %ds\n' $((total_seconds/86400)) $(( (total_seconds%86400)/3600 )) $(( (total_seconds%3600)/60 )) $((total_seconds%60))
}

# Initialize
LAST_CHECK_TIME=$(date +%s)
HEARTBEAT_LAST_SENT=$(date +%s)

# Trap Ctrl+C to exit gracefully
trap ctrl_c INT

function ctrl_c() {
    echo -e "\n${YELLOW}Exiting...${NC}"
    exit 0
}

# Main loop
while true; do
    rotate_log_file
    check_connectivity
    display_ui
    sleep 2
done
