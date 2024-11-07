#!/bin/bash
# File: traceroute.sh
# Version: 1.1.7
# Date: 07/11/2024

# Description:
# Script to run MTR for endpoints and store results in InfluxDB in a format suitable for Node Graph visualization, including the MAC address of the active NIC.

# Version number of the script
SCRIPT_VERSION="1.1.6"

# Base directory for all operations
BASE_DIR="/VeriNexus"

# Log file configuration
LOG_FILE="$BASE_DIR/verinexus_traceroute.log"
MAX_LOG_SIZE=5242880  # 5MB

# InfluxDB Configuration
INFLUXDB_SERVER="http://82.165.7.116:8086"
INFLUXDB_DB="speedtest_db_clean"
INFLUXDB_MEASUREMENT="trace"

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    echo -e "${level}: ${message}" | tee -a "$LOG_FILE"
}

# Function to check and install dependencies
install_if_missing() {
    if ! command -v "$1" &> /dev/null; then
        log_message "${YELLOW}[INFO]" "$1 not found, installing..."
        sudo apt-get update
        sudo apt-get install -y "$1"
    else
        log_message "${GREEN}[INFO]" "$1 is already installed."
    fi
}

# Check and install dependencies
log_message "${CYAN}[INFO]" "Checking dependencies..."
install_if_missing "curl"
install_if_missing "jq"
install_if_missing "mtr"

# Function to query InfluxDB
query_influxdb() {
    local query="$1"
    curl -s -G "$INFLUXDB_SERVER/query" --data-urlencode "db=$INFLUXDB_DB" --data-urlencode "q=$query"
}

# Function to write to InfluxDB
write_to_influxdb() {
    local data="$1"
    curl -i -XPOST "$INFLUXDB_SERVER/write?db=$INFLUXDB_DB" --data-binary "$data"
}

# Function to get the MAC address of the active NIC
get_active_mac_address() {
    ip link show | awk '/state UP/ {getline; print $2}' | head -n 1
}

# Get the MAC address of the active NIC
ACTIVE_MAC_ADDRESS=$(get_active_mac_address)
if [ -z "$ACTIVE_MAC_ADDRESS" ]; then
    log_message "${RED}[ERROR]" "Could not determine the MAC address of the active NIC."
    exit 1
fi

# Ensure the InfluxDB database exists
log_message "${CYAN}[INFO]" "Ensuring InfluxDB database exists..."
query_influxdb "CREATE DATABASE $INFLUXDB_DB"

# Query InfluxDB for endpoints with traceroute enabled
log_message "${CYAN}[INFO]" "Querying InfluxDB for endpoints with traceroute enabled..."
endpoints=$(query_influxdb 'SELECT "field_endpoint" FROM "endpoints" WHERE "field_check_traceroute" = true' | jq -r '.results[0].series[0].values[][1]')

if [ -z "$endpoints" ]; then
    log_message "${RED}[ERROR]" "No endpoints found with traceroute enabled."
    exit 1
fi

# Run MTR for each endpoint and save results to InfluxDB
for endpoint in $endpoints; do
    log_message "${CYAN}[INFO]" "Running MTR for endpoint: $endpoint"
    mtr_output=$(mtr -r -c 1 --json "$endpoint")
    if [ $? -ne 0 ]; then
        log_message "${RED}[ERROR]" "MTR failed for endpoint: $endpoint"
        continue
    fi

    # Parse MTR output and prepare data for InfluxDB
    hops=$(echo "$mtr_output" | jq -c '.report.hubs[]')
    report_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    for hop in $hops; do
        hop_no=$(echo "$hop" | jq -r '.count')
        hop_ip_full=$(echo "$hop" | jq -r '.host')
        hop_loss=$(echo "$hop" | jq -r '.["Loss%"] // 0')
        hop_snt=$(echo "$hop" | jq -r '.Snt // 0')
        hop_last=$(echo "$hop" | jq -r '.Last // 0')
        hop_avg=$(echo "$hop" | jq -r '.Avg // 0')
        hop_best=$(echo "$hop" | jq -r '.Best // 0')
        hop_wrst=$(echo "$hop" | jq -r '.Wrst // 0')
        hop_stdev=$(echo "$hop" | jq -r '.StDev // 0')

        # Extract only the IP address part (remove DNS-resolved name, if any)
        hop_ip=$(echo "$hop_ip_full" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' || echo "$hop_ip_full")

        # Ensure all fields have valid values
        if [ -z "$hop_ip" ] || [ -z "$hop_no" ]; then
            log_message "${YELLOW}[WARNING]" "Skipping hop due to missing IP or hop number."
            continue
        fi

        # Prepare the hop field as "hop_no-hop_ip"
        hop_field="$hop_no-$hop_ip"

        # Prepare InfluxDB line protocol data, including hop_id, hop_ip, and hop fields
        data="trace,destination=$endpoint hop_id=$hop_no,hop_ip=\"$hop_ip\",hop=\"$hop_field\",loss=$hop_loss,snt=$hop_snt,last=$hop_last,avg=$hop_avg,best=$hop_best,wrst=$hop_wrst,stdev=$hop_stdev,mac_address=\"$ACTIVE_MAC_ADDRESS\""
        write_to_influxdb "$data"
        log_message "${GREEN}[INFO]" "MTR data for hop $hop_no (IP: $hop_ip) written to InfluxDB with MAC address $ACTIVE_MAC_ADDRESS."
    done
done

log_message "${GREEN}[INFO]" "Traceroute script completed successfully."
