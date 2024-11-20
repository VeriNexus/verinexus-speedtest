#!/bin/bash
# File: update_crontab.sh
# Version: 1.2.0-nonssl
# Date: 20/11/2024

# Description:
# This script updates the crontab to include the scheduled execution of the speedtest wrapper script.
# It downloads the reference cron file from a secure GitHub repository using a Personal Access Token (PAT).

# Version number of the script
SCRIPT_VERSION="1.2.0"

# Color definitions for UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Variables
REPO_OWNER="VeriNexus"
REPO_NAME="speedtestsecure"
BRANCH="main"
REMOTE_CRON_FILE_PATH="reference_cron.txt"
TOKEN_DIR="/var/lib/token.sh"
BASE_DIR="/VeriNexus"
REFERENCE_CRON_FILE="$BASE_DIR/reference_cron.txt"
LOG_FILE="/var/log/update_crontab.log"

# Ensure log file exists
touch "$LOG_FILE"

# Function to log messages
log_message() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to read the PAT from the file
get_pat_token() {
    PAT_FILE=$(find "$TOKEN_DIR" -type f -name "pat*.txt" | head -n 1)
    if [[ -f "$PAT_FILE" ]]; then
        PAT_TOKEN=$(cat "$PAT_FILE" | tr -d ' \n')
        log_message "${GREEN}PAT token read from $PAT_FILE${NC}"
    else
        log_message "${RED}Error: PAT token file not found in $TOKEN_DIR${NC}"
        echo -e "${RED}Error: PAT token file not found in $TOKEN_DIR${NC}"
        exit 1
    fi
}

# Function to download the remote file using PAT
download_remote_file() {
    local remote_path="$1"
    local local_path="$2"
    local file_name="$(basename "$local_path")"
    RAW_URL="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH/$remote_path"
    log_message "${YELLOW}Downloading the latest version of $file_name from $RAW_URL${NC}"
    HTTP_STATUS=$(curl -w '%{http_code}' -s -H "Authorization: token $PAT_TOKEN" "$RAW_URL" -o "$local_path.tmp")
    if [[ "$HTTP_STATUS" -ne 200 || ! -s "$local_path.tmp" ]]; then
        log_message "${RED}Error: Failed to download $file_name. HTTP status: $HTTP_STATUS${NC}"
        log_message "${RED}Curl output: $(cat "$local_path.tmp")${NC}"
        echo -e "${RED}Error: Failed to download $file_name. HTTP status: $HTTP_STATUS${NC}"
        rm -f "$local_path.tmp"
        exit 1
    else
        # Replace the old file
        mv "$local_path.tmp" "$local_path"
        log_message "${GREEN}Update successful. $file_name downloaded and updated.${NC}"
    fi
}

# Function to display UI
display_ui() {
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${GREEN}       🚀  VeriNexus Crontab Updater - v$SCRIPT_VERSION 🚀${NC}"
    echo -e "${BLUE}====================================================${NC}"
    echo
    echo -e "${YELLOW}🔄 Downloading reference cron file and updating crontab...${NC}"
    echo
}

# Ensure dependencies are installed
for cmd in curl; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${YELLOW}Installing missing dependency: $cmd${NC}"
        sudo apt-get update && sudo apt-get install -y $cmd
    fi
done

# Start of script execution
log_message "${GREEN}Starting update_crontab.sh script.${NC}"

display_ui

# Ensure the base directory exists
if [ ! -d "$BASE_DIR" ]; then
    mkdir -p "$BASE_DIR" || { log_message "${RED}Failed to create directory $BASE_DIR${NC}"; exit 1; }
    log_message "${GREEN}Created base directory $BASE_DIR${NC}"
else
    log_message "${YELLOW}Base directory $BASE_DIR already exists${NC}"
fi

# Get the PAT token
get_pat_token

# Download the latest version of the reference cron job file
download_remote_file "$REMOTE_CRON_FILE_PATH" "$REFERENCE_CRON_FILE"

# Check if the reference file exists
if [[ ! -f "$REFERENCE_CRON_FILE" ]]; then
    log_message "${RED}Reference cron file not found: $REFERENCE_CRON_FILE${NC}"
    echo -e "${RED}Reference cron file not found: $REFERENCE_CRON_FILE${NC}"
    exit 1
else
    log_message "${GREEN}Reference cron file downloaded successfully: $REFERENCE_CRON_FILE${NC}"
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

log_message "${GREEN}Crontab updated successfully.${NC}"

# Provide UI feedback
echo
echo -e "${GREEN}✅ Crontab updated successfully.${NC}"
echo

log_message "${GREEN}Finished update_crontab.sh script.${NC}"
