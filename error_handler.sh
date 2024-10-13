#!/bin/bash

# Error handler script version
ERROR_HANDLER_VERSION="1.0.6"

# Initialize error log
ERROR_LOG=""

log_error() {
    local error_message="$1"
    ERROR_LOG+="===============================\n"
    ERROR_LOG+="Timestamp: $(TZ='Europe/London' date +"%Y-%m-%d %H:%M:%S")\n"
    ERROR_LOG+="Script Version: $SCRIPT_VERSION\n"
    ERROR_LOG+="Error: $error_message\n"
    ERROR_LOG+="===============================\n"
    echo -e "${RED}Error: $error_message${NC}"
}

upload_error_log() {
    if [ -n "$ERROR_LOG" ]; then
        echo -e "$ERROR_LOG" | sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "cat >> $ERROR_LOG_PATH"
        echo -e "${GREEN}All errors logged and uploaded.${NC}"
    fi
}

# Function to check for forced error file and apply its effects
apply_forced_errors() {
    # Download the forced error file if it exists in the GitHub repository
    curl -s "https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/force_error.txt" -o "$FORCED_ERROR_FILE"

    # Check if the forced error file was successfully downloaded
    if [ -s "$FORCED_ERROR_FILE" ]; then
        echo -e "${RED}Forced error file found. Applying forced errors...${NC}"
        source "$FORCED_ERROR_FILE"
    else
        # If the forced error file was previously downloaded but no longer exists in the repo, remove it
        if [ -f "$FORCED_ERROR_FILE" ]; then
            echo -e "${YELLOW}Forced error file removed from GitHub. Deleting local copy...${NC}"
            rm -f "$FORCED_ERROR_FILE"
        fi
    fi
}
