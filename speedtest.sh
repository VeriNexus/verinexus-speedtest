#!/bin/bash
# File: speedtest.sh
# Version: 3.4.1
# Date: 05/11/2024

# Description:
# This script performs a speed test, DHCP test, DNS test, and ping test, collecting various network metrics.
# It uploads the results to an InfluxDB server for monitoring.
# Now includes ISP information retrieved from an external API.

# Version number of the script
SCRIPT_VERSION="3.4.1"

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
    local dependencies=("awk" "curl" "jq" "dig" "speedtest-cli" "ping" "ip" "tput" "grep" "sed" "hostname" "date" "sleep" "dhclient")

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

        # Install missing dependencies
        echo -e "${BLUE}Installing missing dependencies...${NC}"
        sudo apt-get update
        for dep in "${missing_dependencies[@]}"; do
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
                "dhclient")
                    sudo apt-get install -y isc-dhcp-client
                    ;;
                *)
                    sudo apt-get install -y "$dep"
                    ;;
            esac
        done
        echo -e "${CHECKMARK} ${GREEN}Dependencies installed.${NC}"
    fi
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

# Function to escape tag values for InfluxDB line protocol
escape_tag_value() {
    echo "$1" | sed 's/ /\\ /g; s/,/\\,/g; s/=/\\=/g'
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

# Step 5: Extracting Speed Test Results
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

# Step 6: Fetching ISP Information
echo -ne "${CYAN}Step 6: Fetching ISP Information... "
ISP=$(curl -s http://ip-api.com/json/ | jq -r '.isp')
if [ -n "$ISP" ] && [ "$ISP" != "null" ]; then
    echo -e "${CHECKMARK}${GREEN}ISP: $ISP${NC}"
else
    ISP="N/A"
    echo -e "${CROSS}${RED}Failed to retrieve ISP information.${NC}"
    log_message "WARN" "Failed to retrieve ISP information from ip-api.com."
fi

# Step 7: Extracting Shareable ID
echo -ne "${CYAN}Step 7: Extracting Shareable ID... "
SHARE_URL=$(echo "$SPEEDTEST_OUTPUT" | awk -F, '{print $9}')
SHARE_ID=$(echo "$SHARE_URL" | awk -F'/' '{print $NF}' | sed 's/.png//')
echo -e "${CHECKMARK}${GREEN}Shareable ID: $SHARE_ID${NC}"

# Prepare InfluxDB data
# Escape tag values
ESCAPED_MAC_ADDRESS=$(escape_tag_value "$MAC_ADDRESS")
ESCAPED_SERVER_ID=$(escape_tag_value "$SERVER_ID")
ESCAPED_PUBLIC_IP=$(escape_tag_value "$PUBLIC_IP")
ESCAPED_HOSTNAME=$(escape_tag_value "$(hostname)")
ESCAPED_LOCATION=$(escape_tag_value "$LOCATION")
ESCAPED_ISP=$(escape_tag_value "$ISP")

# Ensure field string values are properly quoted and escaped
ESCAPED_LAN_IP=$(echo "$LAN_IP" | sed 's/"/\\"/g')
ESCAPED_UK_DATE=$(echo "$UK_DATE" | sed 's/"/\\"/g')
ESCAPED_UK_TIME=$(echo "$UK_TIME" | sed 's/"/\\"/g')
ESCAPED_SERVER_NAME=$(echo "$SERVER_NAME" | sed 's/"/\\"/g')
ESCAPED_SHARE_ID=$(echo "$SHARE_ID" | sed 's/"/\\"/g')
ESCAPED_SCRIPT_VERSION=$(echo "$SCRIPT_VERSION" | sed 's/"/\\"/g')

# Initialize InfluxDB data
INFLUXDB_DATA="$INFLUXDB_MEASUREMENT"

# Prepare tags with consistent prefix
TAGS=""
[ -n "$ESCAPED_MAC_ADDRESS" ] && TAGS+=",tag_mac_address=$ESCAPED_MAC_ADDRESS"
[ -n "$ESCAPED_SERVER_ID" ] && TAGS+=",tag_server_id=$ESCAPED_SERVER_ID"
[ -n "$ESCAPED_PUBLIC_IP" ] && TAGS+=",tag_public_ip=$ESCAPED_PUBLIC_IP"
[ -n "$ESCAPED_HOSTNAME" ] && TAGS+=",tag_hostname=$ESCAPED_HOSTNAME"
[ -n "$ESCAPED_LOCATION" ] && TAGS+=",tag_location=$ESCAPED_LOCATION"
[ -n "$ESCAPED_ISP" ] && TAGS+=",tag_isp=$ESCAPED_ISP"

# Append tags to InfluxDB data
INFLUXDB_DATA+="$TAGS"

# Prepare fields with consistent prefix
FIELDS=""
[ -n "$LATENCY" ] && FIELDS+="field_latency=$LATENCY"
[ -n "$DOWNLOAD_SPEED" ] && FIELDS+=",field_download_speed=$DOWNLOAD_SPEED"
[ -n "$UPLOAD_SPEED" ] && FIELDS+=",field_upload_speed=$UPLOAD_SPEED"
[ -n "$ESCAPED_LAN_IP" ] && FIELDS+=",field_lan_ip=\"$ESCAPED_LAN_IP\""
[ -n "$ESCAPED_UK_DATE" ] && FIELDS+=",field_date=\"$ESCAPED_UK_DATE\""
[ -n "$ESCAPED_UK_TIME" ] && FIELDS+=",field_time=\"$ESCAPED_UK_TIME\""
[ -n "$ESCAPED_SERVER_NAME" ] && FIELDS+=",field_server_name=\"$ESCAPED_SERVER_NAME\""
[ -n "$ESCAPED_SHARE_ID" ] && FIELDS+=",field_share_id=\"$ESCAPED_SHARE_ID\""
[ -n "$ESCAPED_SCRIPT_VERSION" ] && FIELDS+=",field_script_version=\"$ESCAPED_SCRIPT_VERSION\""

# Remove leading comma if necessary
FIELDS=$(echo "$FIELDS" | sed 's/^,//')

# Append fields to InfluxDB data
INFLUXDB_DATA+=" $FIELDS"

# Ensure the database exists
create_database_if_not_exists "$INFLUXDB_DB"

# Get current timestamp in nanoseconds
CURRENT_TIME=$(date +%s%N)

# Append timestamp to InfluxDB data
INFLUXDB_DATA+=" $CURRENT_TIME"

# Step 8: Saving Speed Test Results to InfluxDB
echo -ne "${CYAN}Step 8: Saving Speed Test Results to InfluxDB... "
curl -s -o /dev/null -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DB" --data-binary "$INFLUXDB_DATA"
if [ $? -eq 0 ]; then
    echo -e "${CHECKMARK}${GREEN}Data successfully saved to InfluxDB.${NC}"
    log_message "INFO" "Speed test data saved to InfluxDB database $INFLUXDB_DB."
else
    echo -e "${CROSS}${RED}Failed to save data to InfluxDB.${NC}"
    log_message "ERROR" "Failed to save speed test data to InfluxDB."
fi

# Step 9: Performing DHCP Test
echo -e "${CYAN}${BOLD}Step 9: Performing DHCP Test...${NC}"
perform_dhcp_test() {
    local START_TIME
    local END_TIME
    local RESPONSE_TIME
    local IP_ADDR
    local GATEWAY
    local DNS
    local LEASE_DURATION
    local STATUS
    local ERROR_MESSAGE
    local DHCP_INFLUX_DATA
    local MEASUREMENT="dhcp"

    print_debug() {
        echo -e "${YELLOW}DEBUG: $1${NC}"
    }

    print_progress() {
        echo -e "${GREEN}>>> $1${NC}"
    }

    print_progress "Performing DHCP test on interface $ACTIVE_IFACE..."

    # Release and renew DHCP lease, capture start time
    START_TIME=$(date +%s%N)
    print_debug "Releasing current DHCP lease..."
    sudo dhclient -v -r $ACTIVE_IFACE 2>&1 | tee dhcp_release.log

    print_debug "Renewing DHCP lease..."
    DHCP_OUTPUT=$(sudo dhclient -v $ACTIVE_IFACE 2>&1 | tee dhcp_renew.log)

    # Check if the DHCP lease was successfully renewed
    if [[ $? -ne 0 ]]; then
        STATUS="fail"
        ERROR_MESSAGE="DHCP lease renewal failed"
        print_debug "DHCP renewal failed. See dhcp_renew.log for details."
    else
        END_TIME=$(date +%s%N)
        RESPONSE_TIME=$(( (END_TIME - START_TIME) / 1000000 ))  # Convert nanoseconds to milliseconds
        print_progress "DHCP lease successfully renewed."

        # Capture current IP and lease information
        IP_ADDR=$(ip addr show $ACTIVE_IFACE | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        GATEWAY=$(ip route show default | awk '{print $3}')

        # Attempt to capture DNS from resolv.conf
        DNS=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')

        # Extract lease duration from DHCP output
        LEASE_DURATION=$(echo "$DHCP_OUTPUT" | grep -oP 'renewal in \K[0-9]+')
        LEASE_DURATION=${LEASE_DURATION:-"N/A"}

        STATUS="pass"
    fi

    # Prepare InfluxDB data
    DHCP_INFLUX_DATA="$MEASUREMENT,tag_mac_address=$ESCAPED_MAC_ADDRESS,tag_public_ip=$ESCAPED_PUBLIC_IP"

    FIELDS=""
    FIELDS+="field_status=\"$STATUS\""
    if [[ "$STATUS" == "pass" ]]; then
        [ -n "$IP_ADDR" ] && FIELDS+=",field_ip=\"$IP_ADDR\""
        [ -n "$GATEWAY" ] && FIELDS+=",field_gateway=\"$GATEWAY\""
        [ -n "$DNS" ] && FIELDS+=",field_dns=\"$DNS\""
        [ -n "$RESPONSE_TIME" ] && FIELDS+=",field_response_time=$RESPONSE_TIME"
        [ -n "$LEASE_DURATION" ] && FIELDS+=",field_lease_duration=\"$LEASE_DURATION\""
    else
        [ -n "$ERROR_MESSAGE" ] && FIELDS+=",field_error_message=\"$ERROR_MESSAGE\""
    fi

    # Remove leading comma if necessary
    FIELDS=$(echo "$FIELDS" | sed 's/^,//')

    # Append fields to data
    DHCP_INFLUX_DATA+=" $FIELDS"

    # Append timestamp
    CURRENT_TIME=$(date +%s%N)
    DHCP_INFLUX_DATA+=" $CURRENT_TIME"

    # Send data to InfluxDB
    print_progress "Writing DHCP test results to InfluxDB..."
    curl -s -o /dev/null -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DB" --data-binary "$DHCP_INFLUX_DATA"

    if [ $? -eq 0 ]; then
        print_progress "DHCP results successfully written to InfluxDB."
        log_message "INFO" "DHCP test data saved to InfluxDB database $INFLUXDB_DB."
    else
        echo -e "${RED}Error: Failed to write DHCP results to InfluxDB.${NC}"
        log_message "ERROR" "Failed to save DHCP test data to InfluxDB."
    fi
}
perform_dhcp_test

# Step 10: Performing DNS Test
echo -e "${CYAN}${BOLD}Step 10: Performing DNS Test...${NC}"
perform_dns_test() {
    local TEST_ID="run-$(date +%Y%m%d%H%M%S)"
    local MEASUREMENT="dns"
    local DNS_SERVERS
    local FQDNS

    print_debug() {
        echo -e "${YELLOW}DEBUG: $1${NC}"
    }

    print_progress() {
        echo -e "${GREEN}>>> $1${NC}"
    }

    read_endpoints_from_influx() {
        print_progress "Reading DNS servers and FQDNs from InfluxDB..."

        # Query InfluxDB for DNS servers
        local dns_query='SELECT last("field_check_dns_server") FROM "endpoints" WHERE "field_check_dns_server" = true GROUP BY "tag_endpoint"'
        print_debug "DNS Query: $dns_query"

        local dns_query_result=$(curl -sG "$INFLUXDB_SERVER/query" \
            --data-urlencode "db=$INFLUXDB_DB" \
            --data-urlencode "q=$dns_query")
        print_debug "DNS Query Result: $dns_query_result"

        if echo "$dns_query_result" | jq -e '.results[0].series' >/dev/null 2>&1; then
            DNS_SERVERS=$(echo "$dns_query_result" | jq -r '.results[0].series[].tags.tag_endpoint')
        else
            echo -e "${RED}Error: No valid DNS servers found for testing.${NC}"
            log_message "ERROR" "No valid DNS servers found for testing."
            return 1
        fi

        # Query InfluxDB for FQDNs to resolve
        local fqdn_query='SELECT last("field_check_name_resolution") FROM "endpoints" WHERE "field_check_name_resolution" = true GROUP BY "tag_endpoint"'
        print_debug "FQDN Query: $fqdn_query"

        local fqdn_query_result=$(curl -sG "$INFLUXDB_SERVER/query" \
            --data-urlencode "db=$INFLUXDB_DB" \
            --data-urlencode "q=$fqdn_query")
        print_debug "FQDN Query Result: $fqdn_query_result"

        if echo "$fqdn_query_result" | jq -e '.results[0].series' >/dev/null 2>&1; then
            FQDNS=$(echo "$fqdn_query_result" | jq -r '.results[0].series[].tags.tag_endpoint')
        else
            echo -e "${RED}Error: No valid FQDNs found for testing.${NC}"
            log_message "ERROR" "No valid FQDNs found for testing."
            return 1
        fi

        print_debug "DNS Servers: $DNS_SERVERS"
        print_debug "FQDNs: $FQDNS"

        # Display the list of tests to be performed
        echo -e "${BLUE}Tests to be performed:${NC}"
        for DNS_SERVER in $DNS_SERVERS; do
            for FQDN in $FQDNS; do
                echo -e "${BLUE}- DNS Server: $DNS_SERVER, FQDN: $FQDN${NC}"
            done
        done
    }

    write_dns_results_to_influxdb() {
        local DNS_INFLUX_DATA="$MEASUREMENT,tag_dns_server=$DNS_SERVER,tag_fqdn=$FQDN,tag_test_id=$TEST_ID,tag_mac_address=$ESCAPED_MAC_ADDRESS,tag_public_ip=$ESCAPED_PUBLIC_IP"

        local FIELDS=""
        FIELDS+="field_status=\"$STATUS\",field_total_time=$TOTAL_TIME_MS,field_query_time=$QUERY_TIME,field_authority=\"$AUTHORITY_STATUS\""
        if [[ "$STATUS" == "fail" ]]; then
            FIELDS+=",field_error_message=\"$ERROR_MESSAGE\""
        fi

        # Remove leading comma if necessary
        FIELDS=$(echo "$FIELDS" | sed 's/^,//')

        # Append fields to data
        DNS_INFLUX_DATA+=" $FIELDS"

        # Append timestamp
        CURRENT_TIME=$(date +%s%N)
        DNS_INFLUX_DATA+=" $CURRENT_TIME"

        # Send data to InfluxDB
        print_progress "Writing DNS test results to InfluxDB..."
        curl -s -o /dev/null -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DB" --data-binary "$DNS_INFLUX_DATA"

        if [ $? -eq 0 ]; then
            print_progress "DNS results successfully written to InfluxDB."
            log_message "INFO" "DNS test data saved to InfluxDB database $INFLUXDB_DB."
        else
            echo -e "${RED}Error: Failed to write DNS results to InfluxDB.${NC}"
            log_message "ERROR" "Failed to save DNS test data to InfluxDB."
        fi
    }

    perform_dns_test_logic() {
        for DNS_SERVER in $DNS_SERVERS; do
            for FQDN in $FQDNS; do
                if [[ -z "$DNS_SERVER" || -z "$FQDN" ]]; then
                    echo -e "${RED}Error: Skipping invalid DNS server or FQDN.${NC}"
                    continue
                fi

                print_progress "Testing $FQDN with DNS server $DNS_SERVER..."

                # Capture start time
                START_TIME=$(date +%s%N)

                # Perform DNS lookup and capture details
                DNS_RESPONSE=$(dig @$DNS_SERVER $FQDN +stats +noall +answer 2>&1)
                END_TIME=$(date +%s%N)
                TOTAL_TIME_MS=$(( (END_TIME - START_TIME) / 1000000 ))  # Convert to milliseconds

                # Extract relevant DNS metrics
                QUERY_TIME=$(echo "$DNS_RESPONSE" | grep -oP '(?<=Query time: )[0-9]+' || echo "0")
                AUTHORITY_STATUS=$(echo "$DNS_RESPONSE" | grep -q "status: NOERROR" && echo "authoritative" || echo "non-authoritative")

                # Determine success or failure based on presence of an "ANSWER" section in the dig output
                if echo "$DNS_RESPONSE" | grep -q "IN"; then
                    STATUS="pass"
                else
                    STATUS="fail"
                    ERROR_MESSAGE=$(echo "$DNS_RESPONSE" | grep -m 1 ";;" || echo "N/A")
                fi

                # Slimmed-down output for users and detailed debug info for logs
                print_debug "[$DNS_SERVER | $FQDN] - Status: $STATUS, Total Time: $TOTAL_TIME_MS ms, Query Time: $QUERY_TIME ms"

                # Write results to InfluxDB
                write_dns_results_to_influxdb
            done
        done
    }

    # Main Execution of DNS Test
    read_endpoints_from_influx
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Skipping DNS test due to previous errors.${NC}"
        return 1
    fi
    perform_dns_test_logic
}
perform_dns_test || echo -e "${YELLOW}DNS test encountered errors but continuing to Ping Test.${NC}"

# Step 11: Performing Ping Test
echo -e "${CYAN}${BOLD}Step 11: Performing Ping Test...${NC}"
perform_ping_test() {
    local MEASUREMENT="ping"
    local PING_ENDPOINTS

    print_debug() {
        echo -e "${YELLOW}DEBUG: $1${NC}"
    }

    print_progress() {
        echo -e "${GREEN}>>> $1${NC}"
    }

    read_ping_endpoints_from_influx() {
        print_progress "Reading ping endpoints from InfluxDB..."

        # Query InfluxDB for endpoints to ping
        local ping_query='SELECT last("field_check_ping") FROM "endpoints" WHERE "field_check_ping" = true GROUP BY "tag_endpoint"'
        print_debug "Ping Query: $ping_query"

        local ping_query_result=$(curl -sG "$INFLUXDB_SERVER/query" \
            --data-urlencode "db=$INFLUXDB_DB" \
            --data-urlencode "q=$ping_query")
        print_debug "Ping Query Result: $ping_query_result"

        if echo "$ping_query_result" | jq -e '.results[0].series' >/dev/null 2>&1; then
            PING_ENDPOINTS=$(echo "$ping_query_result" | jq -r '.results[0].series[].tags.tag_endpoint')
        else
            echo -e "${RED}Error: No valid endpoints found for ping testing.${NC}"
            log_message "ERROR" "No valid endpoints found for ping testing."
            return 1
        fi

        print_debug "Ping Endpoints: $PING_ENDPOINTS"
    }

    write_ping_results_to_influxdb() {
        local PING_INFLUX_DATA="$MEASUREMENT,tag_endpoint=$ENDPOINT,tag_mac_address=$ESCAPED_MAC_ADDRESS,tag_public_ip=$ESCAPED_PUBLIC_IP"

        local FIELDS=""
        FIELDS+="field_status=\"$STATUS\",field_latency_ms=$LATENCY_MS"
        if [[ "$STATUS" == "fail" ]]; then
            FIELDS+=",field_error_message=\"$ERROR_MESSAGE\""
        fi

        # Remove leading comma if necessary
        FIELDS=$(echo "$FIELDS" | sed 's/^,//')

        # Append fields to data
        PING_INFLUX_DATA+=" $FIELDS"

        # Append timestamp
        CURRENT_TIME=$(date +%s%N)
        PING_INFLUX_DATA+=" $CURRENT_TIME"

        # Send data to InfluxDB
        print_progress "Writing ping test results to InfluxDB..."
        curl -s -o /dev/null -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DB" --data-binary "$PING_INFLUX_DATA"

        if [ $? -eq 0 ]; then
            print_progress "Ping results successfully written to InfluxDB."
            log_message "INFO" "Ping test data saved to InfluxDB database $INFLUXDB_DB."
        else
            echo -e "${RED}Error: Failed to write ping results to InfluxDB.${NC}"
            log_message "ERROR" "Failed to save ping test data to InfluxDB."
        fi
    }

    perform_ping_test_logic() {
        for ENDPOINT in $PING_ENDPOINTS; do
            print_progress "Pinging $ENDPOINT..."

            # Perform ping test
            PING_OUTPUT=$(ping -c 1 -s 16 $ENDPOINT 2>&1)
            if [ $? -eq 0 ]; then
                STATUS="pass"
                LATENCY_MS=$(echo "$PING_OUTPUT" | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}')
                ERROR_MESSAGE=""
            else
                STATUS="fail"
                LATENCY_MS=0
                ERROR_MESSAGE=$(echo "$PING_OUTPUT" | head -1)
            fi

            # Log and write results
            print_debug "[$ENDPOINT] - Status: $STATUS, Latency: $LATENCY_MS ms"
            write_ping_results_to_influxdb
        done
    }

    # Main Execution of Ping Test
    read_ping_endpoints_from_influx
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Skipping Ping test due to previous errors.${NC}"
        return 1
    fi
    perform_ping_test_logic
}
perform_ping_test

# Footer
echo -e "${CYAN}====================================================${NC}"
echo -e "${BOLD}VeriNexus Speed Test Completed Successfully!${NC}"
echo -e "${CYAN}====================================================${NC}"

# Exit script
exit 0
