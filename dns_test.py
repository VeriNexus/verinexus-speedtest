#!/bin/bash

# Script Metadata
VERSION="v1.8"
SCRIPT_NAME="dns_test.sh"
TODAY_DATE=$(date "+%d/%m/%Y")
TEST_ID="run-$(date +%Y%m%d%H%M%S)"

# InfluxDB settings
INFLUXDB_URL="http://82.165.7.116:8086"
DATABASE="speedtest_db_clean"
MEASUREMENT="dns"

# Retrieve the MAC address of the primary network interface
MAC_ADDRESS=$(ip link show | awk '/ether/ {print $2; exit}' | tr '[:upper:]' '[:lower:]')

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
    echo -e "         DNS Test Script - $SCRIPT_NAME"
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

# Function to read DNS servers and FQDNs from InfluxDB
read_endpoints_from_influx() {
    print_progress "Reading DNS servers and FQDNs from InfluxDB..."

    # Query InfluxDB for DNS servers
    DNS_SERVERS=$(curl -s "$INFLUXDB_URL/query?db=$DATABASE" --data-urlencode "q=SELECT DISTINCT(\"field_endpoint\") FROM \"endpoints\" WHERE \"tag_check_dns_server\"='true' AND
 \"tag_type\"='IP'" | jq -r '.results[0].series[0].values[][1]' 2>/dev/null)

    # Query InfluxDB for FQDNs to resolve
    FQDNS=$(curl -s "$INFLUXDB_URL/query?db=$DATABASE" --data-urlencode "q=SELECT DISTINCT(\"field_endpoint\") FROM \"endpoints\" WHERE \"tag_check_name_resolution\"='true' AND 
\"tag_type\"='FQDN'" | jq -r '.results[0].series[0].values[][1]' 2>/dev/null)
    
    # Validate the extracted values
    if [[ -z "$DNS_SERVERS" ]]; then
        echo -e "${RED}Error: No valid DNS servers found for testing.${NC}"
        exit 1
    fi

    if [[ -z "$FQDNS" ]]; then
        echo -e "${RED}Error: No valid FQDNs found for testing.${NC}"
        exit 1
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

# Function to perform DNS test
perform_dns_test() {
    print_progress "Performing DNS tests..."

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
            write_to_influxdb "$STATUS" "$TOTAL_TIME_MS" "$QUERY_TIME" "$AUTHORITY_STATUS" "$ERROR_MESSAGE" "$TEST_ID" "$MAC_ADDRESS"
        done
    done
}

# Function to write results to InfluxDB
write_to_influxdb() {
    local status=$1
    local total_time=$2
    local query_time=$3
    local authority_status=$4
    local error_message=$5
    local test_id=$6
    local mac_address=$7

    # Compose InfluxDB line protocol data
    data="$MEASUREMENT,tag_dns_server=$DNS_SERVER,tag_fqdn=$FQDN,tag_test_id=$test_id,tag_mac=$mac_address field_status=\"$status\",field_total_time=$total_time,field_query_time
=$query_time,field_authority=\"$authority_status\""

    if [[ "$status" == "fail" ]]; then
        data+=",field_error_message=\"$error_message\""
    fi

    # Debugging info to verify InfluxDB line protocol
    echo -e "${YELLOW}DEBUG: Data to write to InfluxDB: $data${NC}"

    # Send data to InfluxDB
    print_progress "Writing DNS test results to InfluxDB..."
    response=$(curl -s -i -XPOST "$INFLUXDB_URL/write?db=$DATABASE" --data-binary "$data")

    if echo "$response" | grep -q "204 No Content"; then
        print_progress "Results successfully written to InfluxDB."
    else
        echo -e "${RED}Error: Failed to write results to InfluxDB.${NC}"
    fi
}

# Main Execution
print_header
read_endpoints_from_influx
perform_dns_test