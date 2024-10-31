#!/bin/bash
# File: speedtest.sh
# Version: 2.9.0
# Date: 30/10/2024

# Description:
# This script performs a speed test and collects various network metrics.
# It uploads the results to an InfluxDB server for monitoring.

# Version number of the script
SCRIPT_VERSION="2.9.0"

# Base directory for all operations
BASE_DIR="/VeriNexus"

# Log file configuration
LOG_FILE="$BASE_DIR/verinexus_speedtest.log"
MAX_LOG_SIZE=5242880  # 5MB

# InfluxDB Configuration
INFLUXDB_SERVER="http://82.165.7.116:8086"
INFLUXDB_DB="speedtest_db_clean"
INFLUXDB_MEASUREMENT="speedtest"

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Symbols
CHECKMARK="${GREEN}✔${NC}"
CROSS="${RED}✖${NC}"

# Logging levels
LOG_LEVELS=("INFO" "WARN" "ERROR")

# Function to rotate log file
rotate_log_file() {
    if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -ge "$MAX_LOG_SIZE" ]; then
        mv "$LOG_FILE" "${LOG_FILE}_$(date '+%Y%m%d%H%M%S')"
        touch "$LOG_FILE"
    fi
}

# Function to log messages with levels
log_message() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    local hostname="$(hostname)"
    local script_version="$SCRIPT_VERSION"

    if [[ " ${LOG_LEVELS[*]} " == *" $level "* ]]; then
        echo "$timestamp [$hostname] [Version $script_version] [$level]: $message" >> "$LOG_FILE"
    else
        echo "$timestamp [$hostname] [Version $script_version] [UNKNOWN]: $message" >> "$LOG_FILE"
    fi
}

# Rotate log file at the start
rotate_log_file

# Function to check and install dependencies
check_and_install_dependencies() {
    local missing_dependencies=()
    local dependencies=("awk" "curl" "jq" "dig" "speedtest-cli" "ping" "ip" "tput" "grep" "sed" "hostname" "date" "sleep")

    for dep in "${dependencies[@]}"; do
        if ! command -v $dep &> /dev/null; then
            missing_dependencies+=("$dep")
        fi
    done

    if [ ${#missing_dependencies[@]} -gt 0 ]; then
        echo -e "${CROSS} ${RED}Error: The following dependencies are missing:${NC}"
        for dep in "${missing_dependencies[@]}"; do
            echo -e "   - $dep"
            log_message "ERROR" "$dep is not installed."
        done

        # Prompt user to install missing dependencies
        read -p "Do you want to install the missing dependencies now? (y/n): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            install_dependencies "${missing_dependencies[@]}"
        else
            echo -e "${CROSS} ${RED}Please install the missing dependencies and rerun the script.${NC}"
            exit 1
        fi
    fi
}

# Function to install dependencies
install_dependencies() {
    local dependencies=("$@")
    echo -e "${BLUE}Installing missing dependencies...${NC}"
    sudo apt-get update
    for dep in "${dependencies[@]}"; do
        case "$dep" in
            "dig")
                sudo apt-get install -y dnsutils
                ;;
            "ip")
                sudo apt-get install -y iproute2
                ;;
            "speedtest-cli")
                sudo apt-get install -y speedtest-cli
                ;;
            "ping")
                sudo apt-get install -y iputils-ping
                ;;
            *)
                sudo apt-get install -y "$dep"
                ;;
        esac
    done
    echo -e "${CHECKMARK} ${GREEN}Dependencies installed.${NC}"
}

# Call the check_and_install_dependencies function early in the script
check_and_install_dependencies

# Function to ensure the wrapper script exists
ensure_wrapper_script() {
    local WRAPPER_SCRIPT="$BASE_DIR/speedtest_wrapper.sh"
    local WRAPPER_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest_wrapper.sh"

    if [ ! -f "$WRAPPER_SCRIPT" ]; then
        echo -e "${YELLOW}Wrapper script not found. Downloading...${NC}"
        curl -s -o "$WRAPPER_SCRIPT" "$WRAPPER_URL"
        if [ $? -ne 0 ] || [ ! -s "$WRAPPER_SCRIPT" ]; then
            echo -e "${CROSS}${RED} Failed to download wrapper script.${NC}"
            log_message "ERROR" "Failed to download wrapper script from GitHub."
            exit 1
        fi
        chmod +x "$WRAPPER_SCRIPT"
        echo -e "${CHECKMARK}${GREEN} Wrapper script downloaded and made executable.${NC}"
        log_message "INFO" "Wrapper script downloaded and made executable."
    else
        echo -e "${CHECKMARK}${GREEN} Wrapper script already exists.${NC}"
    fi
}

# Function to create database if it doesn't exist
create_database_if_not_exists() {
    local db_name=$1
    local databases=$(curl -s -G "$INFLUXDB_SERVER/query" --data-urlencode "q=SHOW DATABASES")
    if ! echo "$databases" | grep -q "\"$db_name\""; then
        curl -s -XPOST "$INFLUXDB_SERVER/query" --data-urlencode "q=CREATE DATABASE $db_name" >/dev/null 2>&1
        log_message "INFO" "Created InfluxDB database: $db_name"
    fi
}

# Function to check for forced error file and apply its effects
apply_forced_errors() {
    local FORCED_ERROR_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/force_error.txt"
    local FORCED_ERROR_FILE="$BASE_DIR/force_error.txt"

    curl -s -H 'Cache-Control: no-cache, no-store, must-revalidate' \
         -H 'Pragma: no-cache' \
         -H 'Expires: 0' \
         -o "$FORCED_ERROR_FILE" "$FORCED_ERROR_URL"

    if [ -s "$FORCED_ERROR_FILE" ]; then
        echo -e "${RED}Forced error file found. Applying forced errors...${NC}"
        log_message "INFO" "Applying forced errors from $FORCED_ERROR_FILE"
        if bash -n "$FORCED_ERROR_FILE"; then
            . "$FORCED_ERROR_FILE"
        else
            log_message "ERROR" "Forced error file contains invalid syntax. Deleting local copy."
            rm -f "$FORCED_ERROR_FILE"
        fi
    else
        # If the forced error file was previously downloaded but no longer exists in the repo, remove it
        if [ -f "$FORCED_ERROR_FILE" ]; then
            echo -e "${YELLOW}Forced error file removed from GitHub. Deleting local copy...${NC}"
            rm -f "$FORCED_ERROR_FILE"
            log_message "INFO" "Deleted local copy of forced error file."
        fi
    fi
}

# Function to update crontab by downloading and running update_crontab.sh
update_crontab() {
    local UPDATE_CRON_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/update_crontab.sh"
    local UPDATE_CRON_SCRIPT="$BASE_DIR/update_crontab.sh"

    echo -e "${CYAN}====================================================${NC}"
    echo -e "           ${BOLD}Updating Crontab...${NC}"
    echo -e "${CYAN}====================================================${NC}"

    # Download the latest update_crontab.sh script
    curl -s -o "$UPDATE_CRON_SCRIPT" "$UPDATE_CRON_URL"
    if [ $? -ne 0 ]; then
        echo -e "${CROSS}${RED} Failed to download update_crontab.sh.${NC}"
        log_message "ERROR" "Failed to download update_crontab.sh from GitHub."
        return 1
    fi
    chmod +x "$UPDATE_CRON_SCRIPT"

    # Run the update_crontab.sh script
    bash "$UPDATE_CRON_SCRIPT"
    if [ $? -ne 0 ]; then
        echo -e "${CROSS}${RED} Failed to update crontab using update_crontab.sh.${NC}"
        log_message "ERROR" "Failed to execute update_crontab.sh."
        return 1
    else
        echo -e "${CHECKMARK}${GREEN} Crontab updated successfully.${NC}"
        log_message "INFO" "Crontab updated successfully using update_crontab.sh."
    fi

    echo -e "${CYAN}====================================================${NC}"
}

# Retry function to retry the speed test in case of failure
run_speed_test() {
    local attempts=0
    local max_attempts=3
    while [ $attempts -lt $max_attempts ]; do
        echo -e "${BLUE}Attempting speed test (Attempt $((attempts+1)) of $max_attempts)...${NC}"
        SPEEDTEST_OUTPUT=$(speedtest-cli --json)
        if [ $? -eq 0 ] && [ -n "$SPEEDTEST_OUTPUT" ]; then
            echo -e "${CHECKMARK} Speed Test completed successfully."
            log_message "INFO" "Speed Test completed successfully."
            break
        else
            log_message "WARN" "Speed Test failed on attempt $((attempts+1))."
            attempts=$((attempts + 1))
            sleep 5  # Wait before retrying
        fi
    done

    if [ $attempts -eq $max_attempts ]; then
        log_message "ERROR" "Speed Test failed after $max_attempts attempts."
        return 1  # Fail if all attempts failed
    fi
    return 0
}

# Ensure the wrapper script exists before updating crontab
ensure_wrapper_script

# Apply any forced errors
apply_forced_errors

# Update crontab by downloading and running update_crontab.sh
update_crontab || log_message "WARN" "update_crontab.sh encountered an error but script will continue."

# Display Title with a Frame
echo -e "${CYAN}====================================================${NC}"
echo -e "     ${BOLD}Welcome to VeriNexus Speed Test 2024${NC}"
echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}(C) 2024 VeriNexus. All Rights Reserved.${NC}"
echo -e "${YELLOW}Script Version: $SCRIPT_VERSION${NC}"

# Fancy Progress Bar Function
progress_bar() {
    echo -ne "${CYAN}["
    for ((i=0; i<=50; i++)); do
        echo -ne "#"
        sleep 0.02
    done
    echo -e "]${NC}"
}

echo -e "${BLUE}${BOLD}Starting VeriNexus Speed Test...${NC}"
progress_bar

# Step 1: Running Speed Test with retry logic
echo -e "${CYAN}${BOLD}Step 1: Running Speed Test...${NC}"
run_speed_test
if [ $? -ne 0 ]; then
    echo -e "${CROSS}${RED} Speed Test failed after maximum attempts.${NC}"
    exit 1
fi
echo -e "${CHECKMARK}${GREEN} Speed Test completed successfully.${NC}"

# Step 2: Fetching Date and Time (UK Time - GMT/BST)
echo -ne "${CYAN}Step 2: Fetching Date and Time (UK Time)... "
UK_DATE=$(TZ="Europe/London" date +"%Y-%m-%d")
UK_TIME=$(TZ="Europe/London" date +"%H:%M:%S")
echo -e "${CHECKMARK}${GREEN}Date (UK): $UK_DATE, Time (UK): $UK_TIME${NC}"

# Step 3: Fetching Private/Public IPs
echo -ne "${CYAN}Step 3: Fetching Private/Public IPs... "
PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.co)
echo -e "${CHECKMARK}${GREEN}Private IP: $PRIVATE_IP, Public IP: $PUBLIC_IP${NC}"

# Step 4: Fetching MAC Address and LAN IP
echo -ne "${CYAN}Step 4: Fetching MAC Address and LAN IP... "
ACTIVE_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
if [ -n "$ACTIVE_IFACE" ]; then
    if [ -f "/sys/class/net/$ACTIVE_IFACE/address" ]; then
        MAC_ADDRESS=$(cat /sys/class/net/$ACTIVE_IFACE/address)
    else
        MAC_ADDRESS="N/A"
        log_message "ERROR" "MAC address file not found for interface $ACTIVE_IFACE."
    fi
    LAN_IP=$(ip addr show $ACTIVE_IFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)
else
    log_message "ERROR" "Could not determine active network interface."
    MAC_ADDRESS="N/A"
    LAN_IP="N/A"
fi
echo -e "${CHECKMARK}${GREEN}MAC Address: $MAC_ADDRESS, LAN IP: $LAN_IP${NC}"

# Step 5: Extracting the relevant fields from JSON output
echo -ne "${CYAN}Step 5: Extracting Speed Test Results... "
if [ -n "$SPEEDTEST_OUTPUT" ]; then
    DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | jq '.download' | awk '{printf "%.2f", $1 / 1000000}')  # Convert from bps to Mbps
    UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | jq '.upload' | awk '{printf "%.2f", $1 / 1000000}')      # Convert from bps to Mbps
    LATENCY=$(echo "$SPEEDTEST_OUTPUT" | jq '.ping')
    SERVER_ID=$(echo "$SPEEDTEST_OUTPUT" | jq '.server.id')
    SERVER_NAME=$(echo "$SPEEDTEST_OUTPUT" | jq -r '.server.name')
    LOCATION=$(echo "$SPEEDTEST_OUTPUT" | jq -r '.server.location')
    ISP=$(echo "$SPEEDTEST_OUTPUT" | jq -r '.client.isp')
    PUBLIC_IP=$(echo "$SPEEDTEST_OUTPUT" | jq -r '.client.ip')
    SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | jq -r '.share')
    SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')
else
    log_message "ERROR" "No output from speedtest-cli."
    DOWNLOAD_SPEED="0.00"
    UPLOAD_SPEED="0.00"
    LATENCY="0.00"
    SERVER_ID="N/A"
    SERVER_NAME="N/A"
    LOCATION="N/A"
    ISP="N/A"
    PUBLIC_IP="N/A"
    SHARE_ID="N/A"
fi
echo -e "${CHECKMARK}${GREEN}Download: $DOWNLOAD_SPEED Mbps, Upload: $UPLOAD_SPEED Mbps, Latency: $LATENCY ms${NC}"

# Step 6: Displaying ISP
echo -e "${CYAN}Step 6: Fetching ISP Information...${NC}"
echo -e "${CHECKMARK}${GREEN}ISP: $ISP${NC}"

# Prepare InfluxDB data
INFLUXDB_DATA="$INFLUXDB_MEASUREMENT,tag_mac_address=$MAC_ADDRESS,tag_server_id=$SERVER_ID,tag_public_ip=$PUBLIC_IP,tag_hostname=$(hostname),tag_location=\"$LOCATION\",tag_isp=\"$ISP\" field_latency=$LATENCY,field_download_speed=$DOWNLOAD_SPEED,field_upload_speed=$UPLOAD_SPEED,field_lan_ip=\"$LAN_IP\",field_date=\"$UK_DATE\",field_time=\"$UK_TIME\",field_server_name=\"$SERVER_NAME\",field_share_id=\"$SHARE_ID\",field_script_version=\"$SCRIPT_VERSION\""

# Ensure the database exists
create_database_if_not_exists "$INFLUXDB_DB"

# Step 7: Sending data to InfluxDB
echo -ne "${CYAN}Step 7: Saving Results to InfluxDB... "
curl -s -o /dev/null -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DB" --data-binary "$INFLUXDB_DATA"
echo -e "${CHECKMARK}${GREEN}Data successfully saved to InfluxDB.${NC}"
log_message "INFO" "Data saved to InfluxDB database $INFLUXDB_DB."

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
echo -e "${GREEN}ISP: $ISP${NC}"

# Exit script
exit 0
