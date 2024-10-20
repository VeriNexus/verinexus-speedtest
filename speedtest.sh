#!/bin/bash

# URL to view result on speedtest.net
# To view a result on speedtest.net, use this URL followed by the field_share_id:
# www.speedtest.net/result/

# Version number of the script
SCRIPT_VERSION="2.3.21"

# GitHub repository raw URLs for the script and forced error file
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
FORCED_ERROR_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/force_error.txt"

# Temporary files for comparison and forced error
TEMP_SCRIPT="/tmp/latest_speedtest.sh"
FORCED_ERROR_FILE="/tmp/force_error.txt"
ERROR_LOG=""
MAX_ERROR_LOG_SIZE=2048  # 2KB for testing

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
NC='\033[0m' # No Color

# Symbols
CHECKMARK="${GREEN}✔${NC}"
CROSS="${RED}✖${NC}"

# Function to ensure the measurement exists with the correct field types
ensure_measurement_exists() {
    local db_name=$1
    local measurement=$2
    local test_data="endpoints,endpoint=example.com value=1i"
    curl -i -XPOST "$INFLUXDB_SERVER/write?db=$db_name" --data-binary "$test_data"
}


# Function to check dependencies
check_dependencies() {
    local missing_dependencies=false

    # Check if 'awk' is installed
    if ! command -v awk &> /dev/null; then
        echo -e "${CROSS} ${RED}Error: awk is not installed.${NC}"
        missing_dependencies=true
    fi

    # Check if 'curl' is installed (used for updates and network calls)
    if ! command -v curl &> /dev/null; then
        echo -e "${CROSS} ${RED}Error: curl is not installed.${NC}"
        missing_dependencies=true
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${CROSS} ${RED}Error: jq is not installed.${NC}"
        missing_dependencies=true
    fi

    if [ "$missing_dependencies" = true ]; then
        echo -e "${CROSS} ${RED}Please install the missing dependencies and rerun the script.${NC}"
        exit 1
    fi
}

# Call the check_dependencies function early in the script
check_dependencies

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
    local mac_address=$(cat /sys/class/net/$active_iface/address)  # Get MAC address

    # Format the error log entry as a single line in CSV format, including the MAC address
    local error_entry="$error_id,$timestamp,$script_version,$hostname,$private_ip,$public_ip,$mac_address,\"$error_message\""

    echo -e "${CROSS} ${RED}Error: $error_message${NC}"
}

# Function to perform ping tests
perform_ping_tests() {
    local endpoints=$(curl -s -G "$INFLUXDB_SERVER/query" --data-urlencode "db=$INFLUXDB_TEST_DB" --data-urlencode "q=SELECT endpoint FROM $INFLUXDB_TEST_MEASUREMENT")
    local endpoint_list=$(echo "$endpoints" | jq -r '.results[0].series[0].values[][1] // empty')

    if [ -z "$endpoint_list" ]; then
        echo "No endpoints found in the test database."
        return
    fi

    for endpoint in $endpoint_list; do
        local ping_result=$(ping -c 1 -s 1 "$endpoint" | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}')
        if [ -z "$ping_result" ]; then
            ping_result="N/A"
        fi
        echo "Ping to $endpoint: $ping_result ms"
        # Add the ping result to the InfluxDB data
        INFLUXDB_DATA="$INFLUXDB_DATA,field_ping_$endpoint=$ping_result"
    done
}

# Function to create database if it doesn't exist
create_database_if_not_exists() {
    local db_name=$1
    local databases=$(curl -s -G "$INFLUXDB_SERVER/query" --data-urlencode "q=SHOW DATABASES")
    if ! echo "$databases" | grep -q "\"$db_name\""; then
        curl -i -XPOST "$INFLUXDB_SERVER/query" --data-urlencode "q=CREATE DATABASE $db_name"
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
        if bash -n "$FORCED_ERROR_FILE"; then
            . "$FORCED_ERROR_FILE"
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

# Step 4: Fetching MAC Address and LAN IP
ACTIVE_IFACE=$(ip route | grep default | awk '{print $5}')
if [ "$FORCE_FAIL_MAC" = true ]; then
    log_error "Forced failure to fetch MAC Address."
    MAC_ADDRESS="N/A"
elif [ -n "$ACTIVE_IFACE" ]; then
    MAC_ADDRESS=$(cat /sys/class/net/$ACTIVE_IFACE/address)
    LAN_IP=$(ip addr show $ACTIVE_IFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 4: Fetching LAN IP" "LAN IP: $LAN_IP"
else
    log_error "Could not determine active network interface."
    LAN_IP="N/A"
fi

# Step 5: Extracting the relevant fields
SERVER_ID=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $1}')
SERVER_NAME=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $2}' | sed 's/\"//g') # Remove quotes
LOCATION=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $3}' | sed 's/\"//g')    # Remove quotes
LATENCY=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $6}')   # Latency is in field 6
DOWNLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $7 / 1000000}')  # Convert download speed from bps to Mbps
UPLOAD_SPEED=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{printf "%.2f", $8 / 1000000}')    # Convert upload speed from bps to Mbps
PUBLIC_IP=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $10}')

if [[ -z "$DOWNLOAD_SPEED" || -z "$UPLOAD_SPEED" || -z "$LATENCY" || -z "$PUBLIC_IP" ]]; then
    log_error "Speed Test did not return valid data."
    DOWNLOAD_SPEED="0.00"
    UPLOAD_SPEED="0.00"
    LATENCY="0.00"
    PUBLIC_IP="N/A"
fi

printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 5: Converting Speed Results" "Download Speed: $DOWNLOAD_SPEED Mbps, Upload Speed: $UPLOAD_SPEED Mbps, Latency: $LATENCY ms"

# Step 6: Extracting Shareable ID
SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $9}')
SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')
printf "${CYAN}%-50s ${CHECKMARK}%s${NC}\n" "Step 6: Extracting Shareable ID" "Shareable ID: $SHARE_ID"

# Step 7: Saving Results to InfluxDB
HOSTNAME=$(hostname)

# Corrected InfluxDB data preparation
INFLUXDB_DATA="speedtest,tag_mac_address=$MAC_ADDRESS,tag_server_id=$SERVER_ID,tag_public_ip=$PUBLIC_IP,tag_hostname=$HOSTNAME,tag_location=$LOCATION field_latency=$LATENCY,field_download_speed=$DOWNLOAD_SPEED,field_upload_speed=$UPLOAD_SPEED,field_lan_ip=\"$LAN_IP\",field_date=\"$UK_DATE\",field_time=\"$UK_TIME\",field_server_name=\"$SERVER_NAME\",field_share_id=\"$SHARE_ID\""

# Ensure the databases exist
create_database_if_not_exists "$INFLUXDB_DB"
create_database_if_not_exists "$INFLUXDB_TEST_DB"

# Ensure the measurement exists with the correct field types
ensure_measurement_exists "$INFLUXDB_TEST_DB" "$INFLUXDB_TEST_MEASUREMENT"

# Perform ping tests
perform_ping_tests

# Sending data to InfluxDB.
curl -i -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DB" --data-binary "$INFLUXDB_DATA"

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
