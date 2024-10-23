#!/bin/bash

# Version number of the script
SCRIPT_VERSION="1.1.0"

# Define the URL for the reference cron job file
REFERENCE_CRON_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/reference_cron.txt"

# Define the local path for the reference cron job file
REFERENCE_CRON_FILE="/VeriNexus/reference_cron.txt"

# Ensure the base directory exists
BASE_DIR="/VeriNexus"
if [ ! -d "$BASE_DIR" ]; then
    mkdir -p "$BASE_DIR" || { echo "Failed to create directory $BASE_DIR"; exit 1; }
fi

# Download the latest version of the reference cron job file
echo "Downloading the latest version of the reference cron job file..."
curl -s -o "$REFERENCE_CRON_FILE" "$REFERENCE_CRON_URL" --fail --silent --show-error || { echo "Failed to download reference cron file"; exit 1; }

# Check if the reference file exists
if [[ ! -f "$REFERENCE_CRON_FILE" ]]; then
    echo "Reference cron file not found: $REFERENCE_CRON_FILE"
    exit 1
fi

# Read the reference cron job lines from the file, excluding comments and blank lines
REFERENCE_JOBS=$(grep -v '^#' "$REFERENCE_CRON_FILE" | grep -v '^$')

# Get the current user's crontab
CURRENT_CRONTAB=$(crontab -l 2>/dev/null || true)

# Remove any existing entries for speedtest.sh, speedtest_wrapper.sh, and SHELL= lines
CLEANED_CRONTAB=$(echo "$CURRENT_CRONTAB" | grep -v 'speedtest.sh' | grep -v 'speedtest_wrapper.sh' | grep -v '^SHELL=')

# Build the new crontab by placing reference jobs at the top
NEW_CRONTAB=$(cat <<EOF
$REFERENCE_JOBS
$CLEANED_CRONTAB
EOF
)

# Update the crontab
echo "$NEW_CRONTAB" | crontab -

echo "Crontab updated successfully."
