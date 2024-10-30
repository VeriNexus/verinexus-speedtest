#!/bin/bash

# Script Metadata
VERSION="v1.0"
SCRIPT_NAME="dhcptest.sh"
TODAY_DATE=$(date "+%d/%m/%Y")

# InfluxDB settings
INFLUXDB_URL="http://82.165.7.116:8086"
DATABASE="speedtest_db_clean"
MEASUREMENT="dhcp"
MAC_ADDR=$(cat /sys/class/net/eth0/address)  # Assuming eth0, replace with the actual interface if different

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'  # No color

# Header Function
print_header() {
    echo -e "${CYAN}======================================================"
    echo -e "         DHCP Test Script - $SCRIPT_NAME"
    echo -e "         Version: $VERSION | Date: $TODAY_DATE"
    echo -e "======================================================${NC}"
}

# Function to print progress messages
print_progress() {
    echo -e "${GREEN}>>> $1${NC}"
}

# Function to print debug information
print_debug() {
    echo -e "${YELLOW}DEBUG: $1${NC}"
}

# Function to check if a package is installed and install it if not
check_and_install() {
    PACKAGE_NAME=$1
    if ! dpkg -l | grep -q "^ii  $PACKAGE_NAME"; then
        print_progress "$PACKAGE_NAME not found. Installing..."
        sudo apt update
        sudo apt install -y $PACKAGE_NAME
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to install $PACKAGE_NAME. Please check your network connection or package repository.${NC}"
            exit 1
        fi
    else
        print_debug "$PACKAGE_NAME is already installed."
    fi
}

# Function to check if InfluxDB database exists and create it if not
check_or_create_database() {
    print_progress "Checking for InfluxDB database: $DATABASE..."
    response=$(curl -s -o /dev/null -w "%{http_code}" "$INFLUXDB_URL/query" --data-urlencode "q=SHOW DATABASES")
    if [[ "$response" -ne 200 ]]; then
        echo -e "${RED}Error: Failed to connect to InfluxDB at $INFLUXDB_URL${NC}"
        exit 1
    fi

    db_exists=$(curl -s "$INFLUXDB_URL/query" --data-urlencode "q=SHOW DATABASES" | grep -w "$DATABASE")
    if [[ -z "$db_exists" ]]; then
        print_progress "Creating database $DATABASE..."
        curl -s "$INFLUXDB_URL/query" --data-urlencode "q=CREATE DATABASE $DATABASE"
    fi
}

# Perform DHCP test
perform_dhcp_test() {
    print_progress "Performing DHCP test on $MAC_ADDR..."

    # Release and renew DHCP lease, capture start time
    START_TIME=$(date +%s%N)
    print_debug "Releasing current DHCP lease..."
    sudo dhclient -v -r 2>&1 | tee dhcp_release.log

    print_debug "Renewing DHCP lease..."
    sudo dhclient -v 2>&1 | tee dhcp_renew.log

    # Check if the DHCP lease was successfully renewed
    if [[ $? -ne 0 ]]; then
        STATUS="fail"
        ERROR_MESSAGE="DHCP lease renewal failed"
        print_debug "DHCP renewal failed. See dhcp_renew.log for details."
        write_to_influxdb "$STATUS" "$ERROR_MESSAGE"
        exit 1
    fi

    END_TIME=$(date +%s%N)
    RESPONSE_TIME=$(( (END_TIME - START_TIME) / 1000000 ))  # Convert nanoseconds to milliseconds
    print_progress "DHCP lease successfully renewed."

    # Capture current IP and lease information
    IP_ADDR=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    GATEWAY=$(ip route show default | awk '{print $3}')

    # Attempt to capture DNS from lease file first
    LEASE_FILE=$(ls /var/lib/dhcp/dhclient.*.lease 2>/dev/null | head -n 1)
    if [[ -f "$LEASE_FILE" ]]; then
        DNS=$(grep "option domain-name-servers" "$LEASE_FILE" | awk '{print $3}' | tr '\n' ',')
    fi

    # If lease file doesn't provide DNS, fallback to systemd-resolved if available
    if [[ -z "$DNS" || "$DNS" == "127.0.0.1" ]]; then
        if [[ -f "/run/systemd/resolve/resolv.conf" ]]; then
            DNS=$(grep "nameserver" /run/systemd/resolve/resolv.conf | awk '{print $2}' | tr '\n' ',')
        else
            DNS="Unknown"
        fi
    fi

    LEASE_DURATION=$(ip addr show eth0 | grep "inet " | awk '{print $4}')

    STATUS="pass"
    write_to_influxdb "$STATUS"
}

# Function to write results to InfluxDB
write_to_influxdb() {
    local status=$1
    local error_message=$2

    # Compose InfluxDB line protocol data
    data="$MEASUREMENT,tag_mac=$MAC_ADDR field_status=\"$status\""

    if [[ "$status" == "pass" ]]; then
        data+=",field_ip=\"$IP_ADDR\",field_gateway=\"$GATEWAY\",field_dns=\"$DNS\",field_response_time=$RESPONSE_TIME,field_lease_duration=\"$LEASE_DURATION\""
    else
        data+=",field_error_message=\"$error_message\""
    fi

    # Debugging info to verify InfluxDB line protocol
    echo -e "${YELLOW}DEBUG: Data to write to InfluxDB: $data${NC}"

    # Send data to InfluxDB
    print_progress "Writing results to InfluxDB..."
    response=$(curl -s -i -XPOST "$INFLUXDB_URL/write?db=$DATABASE" --data-binary "$data")

    # Debugging info to verify InfluxDB response
    echo -e "${YELLOW}DEBUG: InfluxDB Response: ${response}${NC}"

    if echo "$response" | grep -q "204 No Content"; then
        print_progress "Results successfully written to InfluxDB."
    else
        echo -e "${RED}Error: Failed to write results to InfluxDB.${NC}"
    fi
}

# Main Execution
print_header
check_and_install isc-dhcp-client
check_or_create_database
perform_dhcp_test
