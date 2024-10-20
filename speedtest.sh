#!/bin/bash

# Version number of the script
SCRIPT_VERSION="2.6.1"

# GitHub repository raw URLs for the script and forced error file
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
FORCED_ERROR_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/force_error.txt"

# Temporary files for comparison and forced error
TEMP_SCRIPT="/tmp/latest_speedtest.sh"
FORCED_ERROR_FILE="/tmp/force_error.txt"
LOG_FILE="/var/log/verinexus_speedtest.log"
[ -w "/var/log" ] || LOG_FILE="/tmp/verinexus_speedtest.log"
MAX_LOG_SIZE=5242880  # 5MB

# InfluxDB Configuration
INFLUXDB_SERVER="http://82.165.7.116:8086"
INFLUXDB_DB="speedtest_db_clean"
INFLUXDB_MEASUREMENT="speedtest"
INFLUXDB_TEST_DB="test_db"
INFLUXDB_TEST_MEASUREMENT="endpoints"

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

# Maximum number of retries to prevent infinite loops
MAX_RETRIES=3
RETRY_COUNT=0

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

# Function to perform DNS resolution tests
perform_dns_tests() {
    local dns_server=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | head -n 1)
    if [ -z "$dns_server" ]; then
        log_message "ERROR" "No DNS server found in /etc/resolv.conf."
        return
    fi

    local domains=("example.com" "google.com" "github.com")
    for domain in "${domains[@]}"; do
        local start_time=$(date +%s%N)
        local dns_result=$(dig @$dns_server $domain +short)
        local end_time=$(date +%s%N)
        local dns_time=$((($end_time - $start_time) / 1000000))  # Convert to milliseconds
        if [ -z "$dns_result" ]; then
            dns_time="0"
            log_message "WARN" "DNS resolution failed for $domain."
        fi
        # Add the DNS resolution time to the InfluxDB data
        INFLUXDB_DATA="$INFLUXDB_DATA,field_dns_${domain//./_}=$dns_time"
    done
}

# Function to check dependencies
check_dependencies() {
    local missing_dependencies=false
    local dependencies=("awk" "curl" "jq" "dig" "speedtest-cli" "ping")

    for dep in "${dependencies[@]}"; do
        if ! command -v $dep &> /dev/null; then
            echo -e "${CROSS} ${RED}Error: $dep is not installed.${NC}"
            log_message "ERROR" "$dep is not installed."
            missing_dependencies=true
        fi
    done

    if [ "$missing_dependencies" = true ]; then
        echo -e "${CROSS} ${RED}Please install the missing dependencies and rerun the script.${NC}"
        exit 1
    fi
}

# Call the check_dependencies function early in the script
check_dependencies

# Function to perform ping tests
perform_ping_tests() {
    local endpoints=$(curl -s -G "$INFLUXDB_SERVER/query" --data-urlencode "db=$INFLUXDB_TEST_DB" --data-urlencode "q=SHOW TAG VALUES FROM \"$INFLUXDB_TEST_MEASUREMENT\" WITH KEY = \"tag_endpoint\"")

    local endpoint_list=$(echo "$endpoints" | jq -r '.results[0].series[0].values[][1] // empty' 2>/dev/null)

    if [ -z "$endpoint_list" ]; then
        echo -e "${YELLOW}No endpoints found in the test database.${NC}"
        log_message "WARN" "No endpoints found in the test database."
        return
    fi

    for endpoint in $endpoint_list; do
        local ping_command="ping -c 1 -s 20 $endpoint"
        local ping_result=$($ping_command | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}')
        if ! [[ $ping_result =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            ping_result="0"
            log_message "WARN" "Ping failed for $endpoint."
        fi
        # Add the ping result to the InfluxDB data
        INFLUXDB_DATA="$INFLUXDB_DATA,field_ping_${endpoint//./_}=$ping_result"
    done
}

# Function to create database if it doesn't exist
create_database_if_not_exists() {
    local db_name=$1
    local databases=$(curl -s -G "$INFLUXDB_SERVER/query" --data-urlencode "q=SHOW DATABASES")
    if ! echo "$databases" | grep -q "\"$db_name\""; then
        curl -s -XPOST "$INFLUXDB_SERVER/query" --data-urlencode "q=CREATE DATABASE $db_name" >/dev/null 2>&1
        log_message "INFO" "Created InfluxDB database: $db_name"
        # Add example.com entry in the correct format
        local test_data="endpoints,tag_endpoint=example.com field_value=1i"
        curl -s -XPOST "$INFLUXDB_SERVER/write?db=$db_name" --data-binary "$test_data" >/dev/null 2>&1
    fi
}

# Function to check for forced error file and apply its effects
apply_forced_errors() {
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

# Function to compare versions using awk
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
    echo -e "${CYAN}====================================================${NC}"
    echo -e "           ${BOLD}Checking for Script Updates...${NC}"
    echo -e "${CYAN}====================================================${NC}"

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

    echo -e "${CHECKMARK} Current version: ${YELLOW}$SCRIPT_VERSION${NC}"
    echo -e "${CHECKMARK} Latest version: ${YELLOW}$LATEST_VERSION${NC}"

    # Compare versions to check if we should upgrade
    if version_gt "$LATEST_VERSION" "$SCRIPT_VERSION"; then
        echo -e "${YELLOW}New version available: $LATEST_VERSION${NC}"
        cp "$TEMP_SCRIPT" "$0"
        chmod +x "$0"
        log_message "INFO" "Updated script to version $LATEST_VERSION."
        if [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; then
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo -e "${CHECKMARK} Update downloaded to version $LATEST_VERSION. Restarting script... (Attempt $RETRY_COUNT of $MAX_RETRIES)"
            exec "$0"
        else
            echo -e "${CROSS} Maximum retries reached. Exiting to prevent infinite loop."
            exit 1
        fi
    else
        echo -e "${GREEN}${CHECKMARK} No update needed. You are using the latest version.${NC}"
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
if [ "$FORCE_FAIL_PRIVATE_IP" = true ]; then
    log_message "WARN" "Forced failure to fetch Private IP."
    PRIVATE_IP="N/A"
else
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
fi

if [ "$FORCE_FAIL_PUBLIC_IP" = true ]; then
    log_message "WARN" "Forced failure to fetch Public IP."
    PUBLIC_IP="N/A"
else
    PUBLIC_IP=$(curl -s ifconfig.co)
fi
echo -e "${CHECKMARK}${GREEN}Private IP: $PRIVATE_IP, Public IP: $PUBLIC_IP${NC}"

# Step 4: Fetching MAC Address and LAN IP
echo -ne "${CYAN}Step 4: Fetching MAC Address and LAN IP... "
ACTIVE_IFACE=$(ip route | grep default | awk '{print $5}')
if [ "$FORCE_FAIL_MAC" = true ]; then
    log_message "WARN" "Forced failure to fetch MAC Address."
    MAC_ADDRESS="N/A"
elif [ -n "$ACTIVE_IFACE" ]; then
    MAC_ADDRESS=$(cat /sys/class/net/$ACTIVE_IFACE/address)
    LAN_IP=$(ip addr show $ACTIVE_IFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)
else
    log_message "ERROR" "Could not determine active network interface."
    MAC_ADDRESS="N/A"
    LAN_IP="N/A"
fi
echo -e "${CHECKMARK}${GREEN}MAC Address: $MAC_ADDRESS, LAN IP: $LAN_IP${NC}"

# Step 5: Extracting the relevant fields
echo -ne "${CYAN}Step 5: Extracting Speed Test Results... "
SERVER_ID=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $1}')
SERVER_NAME=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $2}' | sed 's/\"//g') # Remove quotes
LOCATION=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $3}' | sed 's/\"//g')    # Remove quotes
LATENCY=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $6}')   # Latency is in field 6
DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $7 / 1000000}')  # Convert download speed from bps to Mbps
UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $8 / 1000000}')    # Convert upload speed from bps to Mbps
PUBLIC_IP=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $10}')

if [[ -z "$DOWNLOAD_SPEED" || -z "$UPLOAD_SPEED" || -z "$LATENCY" || -z "$PUBLIC_IP" ]]; then
    log_message "ERROR" "Speed Test did not return valid data."
    DOWNLOAD_SPEED="0.00"
    UPLOAD_SPEED="0.00"
    LATENCY="0.00"
    PUBLIC_IP="N/A"
fi
echo -e "${CHECKMARK}${GREEN}Download: $DOWNLOAD_SPEED Mbps, Upload: $UPLOAD_SPEED Mbps, Latency: $LATENCY ms${NC}"

# Step 6: Extracting Shareable ID
echo -ne "${CYAN}Step 6: Extracting Shareable ID... "
SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $9}')
SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')
echo -e "${CHECKMARK}${GREEN}Shareable ID: $SHARE_ID${NC}"

# Prepare InfluxDB data before calling DNS and ping tests
INFLUXDB_DATA="speedtest,tag_mac_address=$MAC_ADDRESS,tag_server_id=$SERVER_ID,tag_public_ip=$PUBLIC_IP,tag_hostname=$(hostname),tag_location=$LOCATION field_latency=$LATENCY,field_download_speed=$DOWNLOAD_SPEED,field_upload_speed=$UPLOAD_SPEED,field_lan_ip=\"$LAN_IP\",field_date=\"$UK_DATE\",field_time=\"$UK_TIME\",field_server_name=\"$SERVER_NAME\",field_share_id=\"$SHARE_ID\""

# Step 7: Performing DNS Resolution Tests
echo -e "${CYAN}Step 7: Performing DNS Resolution Tests...${NC}"
perform_dns_tests
echo -e "${CHECKMARK}${GREEN} DNS Resolution Tests completed.${NC}"

# Step 8: Performing Ping Tests
echo -e "${CYAN}Step 8: Performing Ping Tests...${NC}"
perform_ping_tests
echo -e "${CHECKMARK}${GREEN} Ping Tests completed.${NC}"

# Ensure the databases exist
create_database_if_not_exists "$INFLUXDB_DB"
create_database_if_not_exists "$INFLUXDB_TEST_DB"

# Step 9: Sending data to InfluxDB
echo -ne "${CYAN}Step 9: Saving Results to InfluxDB... "
curl -s -o /dev/null -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DB" --data-binary "$INFLUXDB_DATA"
echo -e "${CHECKMARK}${GREEN}Data successfully saved to InfluxDB.${NC}"
log_message "INFO" "Data saved to InfluxDB database $INFLUXDB_DB."

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
