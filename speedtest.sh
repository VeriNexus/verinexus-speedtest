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
    local timestamp_ms=$(($(date +%s%N)/1000000))  # Unix timestamp in milliseconds
    local timestamp="$(TZ='Europe/London' date +"%Y-%m-%d %H:%M:%S")"
    local error_id="$timestamp_ms"
    local hostname="$(hostname)"
    local private_ip="$(hostname -I | awk '{print $1}')"
    local public_ip="$(curl -s ifconfig.co)"
    local script_version="$SCRIPT_VERSION"
    local active_iface=$(ip route | grep default | awk '{print $5}')
    local mac_address=$(cat /sys/class/net/$active_iface/address)  # Get MAC address

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

# Function to check for updates
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

# Function to test speed and store the results in InfluxDB
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

    # Extract fields from speedtest output
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

    # Send the results to InfluxDB
    curl -i -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DB" --data-binary \
    "$INFLUXDB_MEASUREMENT,server_id=$SERVER_ID,server_name=\"$SERVER_NAME\",location=\"$LOCATION\" latency=$LATENCY,download_speed=$DOWNLOAD_SPEED,upload_speed=$UPLOAD_SPEED,public_ip=\"$PUBLIC_IP\",mac_address=\"$MAC_ADDRESS\",lan_ip=\"$LAN_IP\",hostname=\"$HOSTNAME\",date=\"$UK_DATE\",time=\"$UK_TIME\""
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

# Run the speed test and store results in InfluxDB
run_speed_test

echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"
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
